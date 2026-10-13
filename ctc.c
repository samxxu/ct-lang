/*
 * ctc.c - C with Traits compiler (Phase 0)
 *
 * A minimal source-to-source compiler: it rewrites the .ct trait syntax
 * into plain C. No type checking, no optimisation, structure only.
 *
 *   gcc ctc.c -o ctc
 *   ./ctc example.ct -o example.c
 *
 * Input constructs:
 *
 *   trait Greeter { void greet(); }
 *      -> struct Greeter_vtbl { void (*greet)(void *); };
 *
 *   struct Person { char *name; } use Greeter;
 *      -> struct Person { char *name; struct Greeter_vtbl *__greeter_vptr; };
 *
 *   impl Greeter for Person { void greet() { ... } }
 *      -> static void Person_Greeter_greet(void *self) {
 *             struct Person *_self = (struct Person *)self;
 *             ...
 *         }
 *         static struct Greeter_vtbl Person_Greeter_vtable = {
 *             .greet = Person_Greeter_greet
 *         };
 *
 *   Person p = { .name = "Tom" };   p.greet();
 *      -> struct Person p = { .name = "Tom", .__greeter_vptr = &Person_Greeter_vtable };
 *         p.__greeter_vptr->greet(&p);
 *
 * Anything else (includes, globals, functions, main, ...) is copied through.
 * A matching .h file is written next to the .c output.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Sam X. Xu <samxxu@gmail.com>
 *
 * ctc is free software under the GNU GPL v3 or later (see LICENSE). Generated
 * output is not: the .c/.h files ctc emits carry an exception that frees them
 * from the GPL (see LICENSE.EXCEPTION), which is why every generated file
 * repeats that notice in its banner.
 */

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NAME   128
#define MAX_PARAM  256
#define MAX_PARAMS 16
#define MAX_METHOD 32
#define MAX_TRAITS 16
#define MAX_STRUCT 32
#define MAX_FIELDS 32
#define MAX_VARS   512
#define MAX_SCOPE  256
#define MAX_DEPTH  8
#define MAX_FUNCS  64
#define MAX_BUILD  32
#define MAX_IMPORTS 16

#define CTC_VERSION "0.0.1"

/* ---------------------------------------------------------------- data */

typedef struct {
    char ret[MAX_NAME];
    char name[MAX_NAME];
    char params[MAX_PARAM];            /* verbatim params, e.g. "int a, int b" */
    char ptypes[MAX_PARAMS][MAX_NAME]; /* types only, for the vtable, e.g. "int" */
    int  nparams;
} Method;

typedef struct {
    char   name[MAX_NAME];
    char   cname[MAX_NAME];            /* namespace-mangled C name (ns + name) */
    Method m[MAX_METHOD];
    int    nm;
} Trait;

typedef struct {
    char name[MAX_NAME];
    char cname[MAX_NAME];              /* namespace-mangled C name (ns + name) */
    char use_t[MAX_TRAITS][MAX_NAME];  /* used trait short names (vptr field, messages) */
    int  use_i[MAX_TRAITS];            /* their index into g_traits (for the mangled name) */
    int  nu;
    char fname[MAX_FIELDS][MAX_NAME];  /* value fields whose type is a known struct */
    int  ftype[MAX_FIELDS];            /* ... and their index into g_structs */
    int  nf;
    int  has_drop;                     /* 1 when the use-clause mentions the reserved 'Drop' */
    int  drop_used;                    /* 1 when a delete of this type was seen (drives lazy emit) */
    int  has_user_drop;                /* 1 when the user wrote `impl Drop for T` */
    size_t drop_bstart, drop_blen;     /* the user drop() body, when has_user_drop */
    size_t def_line;                   /* 1-based source line of the definition (for #line) */
} Struct;

typedef struct {
    char name[MAX_NAME];
    int  s;                            /* index into g_structs */
    int  ptr;                          /* 1 when declared as a pointer (uses '->') */
    int  arr;                          /* 1 when declared as an array (uses '[n]') */
    int  iface;                        /* 1 when this is an interface value */
    int  tr;                           /* index into g_traits when iface */
} Var;

/* one recorded function signature, used to box interface arguments */
typedef struct {
    char name[MAX_NAME];
    int  nparams;
    int  ptrait[MAX_PARAMS];           /* >=0 when that parameter is an interface value */
    int  rettrait;                     /* >=0 when the return type is an interface value */
} FuncSig;

typedef struct {
    char   name[MAX_NAME];
    char   params[MAX_PARAM];
    size_t bstart, blen;               /* body location inside g_src */
} ImplMethod;

/* -------------------------------------------------------------- globals */

static const char *g_src  = NULL;
static size_t      g_len  = 0;
static const char *g_path = "<input>";

static FILE *g_out  = NULL;            /* generated .c */
static FILE *g_hout = NULL;            /* generated .h */

static Trait  g_traits[MAX_TRAITS];   static int g_ntraits  = 0;
static Struct g_structs[MAX_STRUCT];  static int g_nstructs = 0;
static Var    g_vars[MAX_VARS];       static int g_nvars    = 0;
static FuncSig g_funcs[MAX_FUNCS];    static int g_nfuncs   = 0;
static int    g_cur_rettr = -1;       /* return trait of the function being scanned */

/* block scopes: g_nvars is restored to the saved value at every closing brace */
static int g_scope[MAX_SCOPE];        static int g_nscope = 0;
static size_t g_body_abs = 0;         /* position of a pending function body '{' */
static int    g_body_pre = 0;         /* g_nvars before that function's parameters */
static int    g_no_box = 0;           /* while emitting a signature: never box args */

static char g_ns[MAX_NAME];           /* current namespace prefix, e.g. "HAL_UART_" ("" at top level) */

/* multi-file mode (`ct build`): the generated .c includes its own .h, and `pub`
   symbols are routed into the .h instead of the .c */
static int g_multi = 0;               /* 1 when compiling in multi-file mode */
static int g_ctor_pub = 0;            /* 1 when the current trait/struct is 'pub' */
static int g_line_pub = 0;            /* 1 when the current raw line was 'pub'-prefixed */

/* Phase 1.5 `#line` (D4 = A): on in multi-file mode so gcc errors in the
   generated .c map back to the .ct; single-file output stays byte-identical to
   Phase 0 (where the mapping would diverge anyway). `--line` / `--no-line`
   override the per-mode default. Only the .c is tracked, never the .h. */
static int  g_emit_line  = 0;         /* 1 while #line directives are written */
static int  g_line_force = -1;        /* -1 default (by mode), 0 force off, 1 force on */
static long g_line_next  = -1;        /* source line the next .c line maps to, or -1 */
static size_t g_lc_off   = 0;         /* line_of cache: byte offset ... */
static size_t g_lc_ln    = 1;         /* ... and its 1-based line number */

/* the imported units' header basenames, emitted as #includes by the .c */
static char g_imp_h[MAX_IMPORTS][MAX_NAME];
static int  g_nimp_h = 0;

/* in multi-file mode symbols accumulate across units (so a unit can reference
   an imported unit's types); these are the tables that must NOT be reset. */
#define MAX_UNITS 64

/* structs declared in the current unit that opt into Drop; their bodies are
   emitted lazily, only when a delete of that type is seen */
static int g_own_drop[MAX_STRUCT];
static int g_nown_drop = 0;

static char g_guard[MAX_NAME * 2];     /* include guard of the generated .h */

/* ---------------------------------------------------------------- util */

static void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p) { fprintf(stderr, "ctc: out of memory\n"); exit(1); }
    return p;
}

static char *xstrndup(const char *s, size_t n)
{
    char *p = xmalloc(n + 1);
    memcpy(p, s, n);
    p[n] = 0;
    return p;
}

static int is_ident_char(int c) { return isalnum((unsigned char)c) || c == '_'; }

static void die(size_t pos, const char *fmt, ...)
{
    va_list ap;
    int line = 1, col = 1;
    size_t i;

    for (i = 0; i < pos && i < g_len; i++) {
        if (g_src[i] == '\n') { line++; col = 1; } else col++;
    }
    fprintf(stderr, "%s:%d:%d: error: ", g_path, line, col);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

/* leading/trailing whitespace trim, in place */
static void trim(char *s)
{
    size_t n, i = 0;
    while (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r') i++;
    if (i) memmove(s, s + i, strlen(s + i) + 1);
    n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1])) s[--n] = 0;
}

static size_t trim_right_len(const char *s, size_t n)
{
    while (n && isspace((unsigned char)s[n - 1])) n--;
    return n;
}

static void to_lower(const char *in, char *out)
{
    size_t i;
    for (i = 0; in[i] && i < MAX_NAME - 1; i++)
        out[i] = (char)tolower((unsigned char)in[i]);
    out[i] = 0;
}

/* build the namespace-mangled C name for `name` in namespace `ns` */
static void set_cname(char *out, size_t cap, const char *ns, const char *name, size_t pos)
{
    int k = snprintf(out, cap, "%s%s", ns, name);
    if (k < 0 || (size_t)k >= cap) die(pos, "namespace-qualified name too long");
}

/* dynamic string buffer */
typedef struct { char *p; size_t n, cap; } Buf;

/* File-scope ct objects/arrays (Phase 1.6): their vptr writes are statements,
   which C cannot hold at file scope. They are accumulated here and emitted in a
   per-unit constructor (`__attribute__((constructor))`, decision D5 = A) that
   runs before main. `static`, so each translation unit has its own. */
static Buf g_unit_init;
static int g_has_unit_init = 0;

static void buf_init(Buf *b)   { b->cap = 256; b->n = 0; b->p = xmalloc(b->cap); b->p[0] = 0; }
static void buf_putn(Buf *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        while (b->cap < b->n + n + 1) b->cap *= 2;
        b->p = realloc(b->p, b->cap);
        if (!b->p) { fprintf(stderr, "ctc: out of memory\n"); exit(1); }
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = 0;
}
static void buf_puts(Buf *b, const char *s) { buf_putn(b, s, strlen(s)); }
static void buf_putc(Buf *b, char c)        { buf_putn(b, &c, 1); }

/* --------------------------------------------------- source-level helpers */

static int word_at(size_t p, const char *w)
{
    size_t l = strlen(w);
    if (p + l > g_len) return 0;
    if (memcmp(g_src + p, w, l) != 0) return 0;
    if (p > 0 && is_ident_char((unsigned char)g_src[p - 1])) return 0;
    if (p + l < g_len && is_ident_char((unsigned char)g_src[p + l])) return 0;
    return 1;
}

static size_t skip_literal(size_t p)
{
    char q = g_src[p++];
    while (p < g_len) {
        if (g_src[p] == '\\' && p + 1 < g_len) { p += 2; continue; }
        if (g_src[p] == q) return p + 1;
        p++;
    }
    return p;
}

static size_t skip_comment(size_t p)
{
    if (p + 1 < g_len && g_src[p] == '/' && g_src[p + 1] == '/') {
        p += 2;
        while (p < g_len && g_src[p] != '\n') p++;
        return p;
    }
    if (p + 1 < g_len && g_src[p] == '/' && g_src[p + 1] == '*') {
        p += 2;
        while (p + 1 < g_len && !(g_src[p] == '*' && g_src[p + 1] == '/')) p++;
        return (p + 1 < g_len) ? p + 2 : g_len;
    }
    return p;
}

/* skip whitespace and comments (newlines included) */
static size_t skip_ws_comments(size_t p)
{
    for (;;) {
        while (p < g_len && isspace((unsigned char)g_src[p])) p++;
        if (p + 1 < g_len && g_src[p] == '/' &&
            (g_src[p + 1] == '/' || g_src[p + 1] == '*')) {
            p = skip_comment(p);
            continue;
        }
        return p;
    }
}

static size_t read_ident(size_t p, char *buf, size_t n)
{
    size_t i = 0;
    while (p < g_len && is_ident_char((unsigned char)g_src[p])) {
        if (i + 1 >= n) die(p, "identifier too long (max %d)", (int)n - 1);
        buf[i++] = g_src[p];
        p++;
    }
    buf[i] = 0;
    return p;
}

/* Copy the identifier at `src` (a NUL-terminated string) into `buf` (MAX_NAME
   bytes) and return its length. A longer identifier is a hard error — dropping
   the tail would silently misparse (AGENTS §3 forbids silent truncation). */
static size_t copy_ident(const char *src, char *buf, size_t pos)
{
    size_t k = 0;
    while (is_ident_char((unsigned char)src[k])) {
        if (k + 1 >= MAX_NAME) die(pos, "identifier too long (max %d)", MAX_NAME - 1);
        buf[k] = src[k];
        k++;
    }
    buf[k] = 0;
    return k;
}

static size_t match_delim(size_t p, char open, char close)
{
    int depth = 0;
    size_t start = p;
    while (p < g_len) {
        char c = g_src[p];
        if (c == '"' || c == '\'') { p = skip_literal(p); continue; }
        if (c == '/' && p + 1 < g_len &&
            (g_src[p + 1] == '/' || g_src[p + 1] == '*')) { p = skip_comment(p); continue; }
        if (c == open) depth++;
        else if (c == close) { depth--; if (depth == 0) return p; }
        p++;
    }
    die(start, "unterminated '%c'", open);
    return p;
}

/* 1-based line number of byte offset `pos` in g_src. The scan is cached from the
   previous call so a forward walk over the file stays linear. */
static size_t line_of(size_t pos)
{
    if (pos < g_lc_off) { g_lc_off = 0; g_lc_ln = 1; }
    while (g_lc_off < pos && g_lc_off < g_len) {
        if (g_src[g_lc_off] == '\n') g_lc_ln++;
        g_lc_off++;
    }
    return g_lc_ln;
}

/* ------------------------------------------------ tables / lookups */

/* Namespace-aware lookup: an unqualified name resolves inside the current
   namespace first, then at top level (the design's "unqualified falls back to
   the enclosing, then the root namespace"). Comparison is on the mangled C
   name, so a plain-C namespace never collides with a real name. */
static Trait *find_trait(const char *name)
{
    char q[MAX_NAME * 2];
    int i;

    if (snprintf(q, sizeof q, "%s%s", g_ns, name) < (int)sizeof q) {
        for (i = 0; i < g_ntraits; i++)
            if (strcmp(g_traits[i].cname, q) == 0) return &g_traits[i];
    }
    for (i = 0; i < g_ntraits; i++)
        if (strcmp(g_traits[i].cname, name) == 0) return &g_traits[i];
    return NULL;
}

static Struct *find_struct(const char *name)
{
    char q[MAX_NAME * 2];
    int i;

    if (snprintf(q, sizeof q, "%s%s", g_ns, name) < (int)sizeof q) {
        for (i = 0; i < g_nstructs; i++)
            if (strcmp(g_structs[i].cname, q) == 0) return &g_structs[i];
    }
    for (i = 0; i < g_nstructs; i++)
        if (strcmp(g_structs[i].cname, name) == 0) return &g_structs[i];
    return NULL;
}

/* lookup by an already-mangled C name (what a qualified `A::B::X` maps to) */
static Struct *find_struct_c(const char *cname)
{
    int i;
    for (i = 0; i < g_nstructs; i++)
        if (strcmp(g_structs[i].cname, cname) == 0) return &g_structs[i];
    return NULL;
}

static Trait *find_trait_c(const char *cname)
{
    int i;
    for (i = 0; i < g_ntraits; i++)
        if (strcmp(g_traits[i].cname, cname) == 0) return &g_traits[i];
    return NULL;
}

static int struct_uses(const Struct *s, const char *trait)
{
    int i;
    for (i = 0; i < s->nu; i++)
        if (strcmp(s->use_t[i], trait) == 0) return 1;
    return 0;
}

/* index of a nested struct field, or -1 */
static int find_field(const Struct *s, const char *name)
{
    int i;
    for (i = 0; i < s->nf; i++)
        if (strcmp(s->fname[i], name) == 0) return i;
    return -1;
}

/* which trait of struct `s` declares method `m`? NULL if none */
static const char *resolve_method(const Struct *s, const char *m)
{
    int i, k;
    for (i = 0; i < s->nu; i++) {
        const Trait *t = &g_traits[s->use_i[i]];
        for (k = 0; k < t->nm; k++)
            if (strcmp(t->m[k].name, m) == 0) return t->name;
    }
    return NULL;
}

static int find_var(const char *name)
{
    int i;
    for (i = 0; i < g_nvars; i++)
        if (strcmp(g_vars[i].name, name) == 0) return i;
    return -1;
}

/* Reserve the next variable slot. Overflow is a hard error: AGENTS §3 forbids
   silent truncation, and a dropped registration would miscompile method calls. */
static int new_var(void)
{
    if (g_nvars >= MAX_VARS) die(0, "too many variables (max %d)", MAX_VARS);
    return g_nvars++;
}

/* does trait `t` declare method `m`? */
static int trait_has_method(const Trait *t, const char *m)
{
    int i;
    for (i = 0; i < t->nm; i++)
        if (strcmp(t->m[i].name, m) == 0) return 1;
    return 0;
}

/* the last recorded signature of `name`, or NULL (a later definition wins) */
static FuncSig *find_func(const char *name)
{
    int i;
    for (i = g_nfuncs - 1; i >= 0; i--)
        if (strcmp(g_funcs[i].name, name) == 0) return &g_funcs[i];
    return NULL;
}

/* ------------------------------------------------------- signature parsing */

static int is_type_keyword(const char *s)
{
    static const char *kw[] = {
        "void", "char", "short", "int", "long", "float", "double",
        "signed", "unsigned", "_Bool", "bool", "const", "volatile",
        "struct", "union", "enum", "size_t", "ssize_t", "FILE", "wchar_t",
        "int8_t", "int16_t", "int32_t", "int64_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t", "ptrdiff_t", NULL
    };
    int i;
    for (i = 0; kw[i]; i++)
        if (strcmp(kw[i], s) == 0) return 1;
    return 0;
}

/* "char *name" -> "char *" ; "int" -> "int" (already a type) */
static void param_type_only(const char *piece, char *out)
{
    char t[MAX_NAME * 2];
    int end, st;
    char id[MAX_NAME];

    snprintf(t, sizeof t, "%s", piece);
    trim(t);

    end = (int)strlen(t);
    st = end;
    while (st > 0 && is_ident_char((unsigned char)t[st - 1])) st--;
    if (st == end) { snprintf(out, MAX_NAME, "%s", t); return; }   /* ends with '*' etc. */

    snprintf(id, sizeof id, "%.*s", end - st, t + st);
    if (is_type_keyword(id)) { snprintf(out, MAX_NAME, "%s", t); return; }

    t[st] = 0;
    trim(t);
    snprintf(out, MAX_NAME, "%s", t);
}

/* raw param list -> verbatim params + type-only list */
static void parse_params(Method *m, const char *raw)
{
    char tmp[MAX_PARAM * 2];
    char *p;
    int depth = 0;
    size_t start = 0, i, n;

    snprintf(tmp, sizeof tmp, "%s", raw);
    trim(tmp);

    m->nparams = 0;
    m->params[0] = 0;

    if (!tmp[0] || strcmp(tmp, "void") == 0) return;

    p = tmp;
    n = strlen(p);
    for (i = 0; i <= n; i++) {
        char c = (i < n) ? p[i] : ',';
        if (i < n) {
            if (c == '(' || c == '[') depth++;
            else if (c == ')' || c == ']') depth--;
        }
        if (c == ',' && depth == 0) {
            char piece[MAX_NAME * 2];
            size_t len = i - start;
            if (len >= sizeof piece) len = sizeof piece - 1;
            memcpy(piece, p + start, len);
            piece[len] = 0;
            trim(piece);
            if (piece[0]) {
                if (m->nparams >= MAX_PARAMS)
                    die(0, "too many parameters in method '%s'", m->name);
                if (m->nparams) strncat(m->params, ", ", sizeof m->params - strlen(m->params) - 1);
                strncat(m->params, piece, sizeof m->params - strlen(m->params) - 1);
                param_type_only(piece, m->ptypes[m->nparams]);
                m->nparams++;
            }
            start = i + 1;
        }
    }
}

/* "void greet(int a)" -> ret="void", name="greet", params="int a" */
static void split_decl(const char *decl, size_t pos, Method *m)
{
    const char *lp = strchr(decl, '(');
    const char *rp;
    char pre[MAX_NAME * 2];
    int end, st;

    if (!lp) die(pos, "expected '(' in method declaration");
    snprintf(pre, sizeof pre, "%.*s", (int)(lp - decl), decl);
    trim(pre);

    end = (int)strlen(pre);
    st = end;
    while (st > 0 && is_ident_char((unsigned char)pre[st - 1])) st--;
    if (st == end) die(pos, "expected method name in declaration");
    snprintf(m->name, sizeof m->name, "%.*s", end - st, pre + st);
    pre[st] = 0;
    trim(pre);
    if (!pre[0]) die(pos, "expected return type for method '%s'", m->name);
    snprintf(m->ret, sizeof m->ret, "%s", pre);

    rp = strchr(lp, ')');
    if (!rp) die(pos, "expected ')' in declaration of '%s'", m->name);
    {
        char raw[MAX_PARAM * 2];
        size_t len = (size_t)(rp - lp - 1);
        if (len >= sizeof raw) len = sizeof raw - 1;
        memcpy(raw, lp + 1, len);
        raw[len] = 0;
        parse_params(m, raw);
    }
    {
        const char *tail = rp + 1;
        while (*tail == ' ' || *tail == '\t') tail++;
        if (*tail) die(pos, "unexpected '%s' after declaration of '%s'", tail, m->name);
    }
}

/* C keywords that can never be a function's return type or its name */
static int is_stmt_keyword(const char *s)
{
    static const char *kw[] = {
        "if", "else", "while", "for", "switch", "case", "default", "do",
        "return", "goto", "break", "continue", "sizeof", NULL
    };
    int i;
    for (i = 0; kw[i]; i++)
        if (strcmp(kw[i], s) == 0) return 1;
    return 0;
}

/* the last identifier token in s[0..n): 1 and [*a,*b) when there is one */
static int last_ident(const char *s, size_t n, size_t *a, size_t *b)
{
    size_t e = n, st;
    while (e > 0 && !is_ident_char((unsigned char)s[e - 1])) e--;
    if (e == 0) return 0;
    st = e;
    while (st > 0 && is_ident_char((unsigned char)s[st - 1])) st--;
    *a = st;
    *b = e;
    return 1;
}

/* The last namespace path `A::B::Name` (or a plain `Name`) in s[0..n): 1 and the
   full span [*a,*b) including the `::` separators. */
static int last_qual_name(const char *s, size_t n, size_t *a, size_t *b)
{
    size_t st, e, z;

    if (!last_ident(s, n, &st, &e)) return 0;
    for (;;) {
        z = st;
        while (z > 0 && isspace((unsigned char)s[z - 1])) z--;
        if (z >= 2 && s[z - 1] == ':' && s[z - 2] == ':') {
            size_t w = z - 2, e2, s2;
            while (w > 0 && isspace((unsigned char)s[w - 1])) w--;
            e2 = w;
            s2 = e2;
            while (s2 > 0 && is_ident_char((unsigned char)s[s2 - 1])) s2--;
            if (s2 == e2) break;
            st = s2;
            continue;
        }
        break;
    }
    *a = st;
    *b = e;
    return 1;
}

/* mangle a namespace path span (`A::B::Name`) into a C name (`A_B_Name`) */
static void qual_to_c(const char *s, size_t a, size_t b, char *out, size_t cap)
{
    size_t i = a, k = 0;
    while (i < b) {
        char c = s[i];
        if (c == ':') {
            if (k + 1 < cap) out[k++] = '_';
            i++;
            if (i < b && s[i] == ':') i++;
        } else if (isspace((unsigned char)c)) {
            i++;
        } else {
            if (k + 1 < cap) out[k++] = c;
            i++;
        }
    }
    out[k] = 0;
}

/* does the span [a,b) contain a `::`? (i.e. is it a qualified reference) */
static int span_qualified(const char *s, size_t a, size_t b)
{
    size_t i;
    for (i = a; i < b; i++)
        if (s[i] == ':') return 1;
    return 0;
}

/* is the identifier at `off` in `type` already preceded by "struct"? */
static int already_qualified(const char *type, size_t off)
{
    size_t q = off;
    while (q > 0 && isspace((unsigned char)type[q - 1])) q--;
    return q >= 6 && memcmp(type + q - 6, "struct", 6) == 0 &&
           (q == 6 || !is_ident_char((unsigned char)type[q - 7]));
}

/* Analyse one declaration piece (a parameter, a struct field or a return type):
   the struct its type names (an index into g_structs, or -1), the trait when the
   type is an interface value (`*tr`, or -1), the identifier span [*ia,*ib) of
   the base type name and its namespace-mangled spelling (`cbase`), whether the
   "struct " keyword must be inserted (`*need_struct`), the declared name ("" when
   unnamed) and whether it is a pointer. Arrays are qualified but carry no name. */
static int analyse_param(const char *s, size_t n, int *ia, int *ib,
                         char *cbase, int *need_struct,
                         char *name, int *isptr, int *tr)
{
    size_t a, b, lim = 0, tn, ea, eb;
    char type[MAX_NAME * 2], base[MAX_NAME];
    int idx = -1;
    const Struct *S;
    const Trait *T;

    *ia = -1;
    *ib = -1;
    *need_struct = 0;
    *tr = -1;
    cbase[0] = 0;
    base[0] = 0;
    name[0] = 0;
    *isptr = 0;

    while (lim < n && s[lim] != '[') lim++;
    if (!last_qual_name(s, lim, &a, &b)) return -1;

    {
        size_t lsx = b;
        char last[MAX_NAME];
        while (lsx > a && is_ident_char((unsigned char)s[lsx - 1])) lsx--;
        snprintf(last, sizeof last, "%.*s", (int)(b - lsx), s + lsx);
        if (!span_qualified(s, a, b) &&
            !is_type_keyword(last) && !find_struct(last) && !find_trait(last)) {
            snprintf(name, MAX_NAME, "%s", last);
            snprintf(type, sizeof type, "%.*s", (int)a, s);
        } else {
            snprintf(type, sizeof type, "%.*s", (int)n, s);   /* the type itself */
        }
    }
    if (lim < n) name[0] = 0;                                 /* array: no object to bind */

    /* the base type name: drop trailing '*'/space, then take the last (possibly
       qualified) name */
    tn = strlen(type);
    while (tn > 0 && (type[tn - 1] == '*' || isspace((unsigned char)type[tn - 1]))) tn--;
    if (tn == 0 || !last_qual_name(type, tn, &ea, &eb)) return -1;

    if (span_qualified(type, ea, eb)) {
        qual_to_c(type, ea, eb, cbase, MAX_NAME);            /* A::B::Name -> A_B_Name */
        S = find_struct_c(cbase);
        T = S ? NULL : find_trait_c(cbase);
    } else {
        size_t bl = eb - ea;
        if (bl >= sizeof base) bl = sizeof base - 1;
        memcpy(base, type + ea, bl);
        base[bl] = 0;
        S = find_struct(base);
        T = S ? NULL : find_trait(base);
        if (S) snprintf(cbase, MAX_NAME, "%s", S->cname);
        else if (T) snprintf(cbase, MAX_NAME, "%s", T->cname);
    }

    if (S) {
        idx = (int)(S - g_structs);
        *ia = (int)ea;
        *ib = (int)eb;
        *need_struct = !already_qualified(type, ea);
    } else if (T) {
        *tr = (int)(T - g_traits);
        *ia = (int)ea;
        *ib = (int)eb;
        *need_struct = !already_qualified(type, ea);
    } else if (strlen(base) > 6 && strcmp(base + strlen(base) - 6, "_iface") == 0) {
        /* the already-expanded spelling "struct X_iface" */
        char pre[MAX_NAME];
        size_t pl = strlen(base) - 6;
        if (pl < sizeof pre) {
            memcpy(pre, base, pl);
            pre[pl] = 0;
            T = find_trait(pre);
            if (T) *tr = (int)(T - g_traits);
        }
    }

    *isptr = (strchr(type, '*') != NULL);
    return idx;
}

/* emit a declaration piece: replace the base type identifier [ia,ib) with its
   mangled spelling, inserting "struct " (and "_iface" for a trait) as needed */
static void emit_qualified_type(Buf *b, const char *piece, size_t len,
                                int ia, int ib, const char *cbase,
                                int need_struct, int is_trait)
{
    if (ia < 0) { buf_putn(b, piece, len); return; }
    buf_putn(b, piece, (size_t)ia);
    if (need_struct) buf_puts(b, "struct ");
    buf_puts(b, cbase);
    if (is_trait) buf_puts(b, "_iface");
    buf_putn(b, piece + ib, len - (size_t)ib);
}

/* ------------------------------------------------------------ emitters */

/* ---------------------------------------------------------- #line emission */

/* Invalidate the running mapping so the next line_at always writes an explicit
   directive — used after a run of generated boilerplate. */
static void line_break(void) { g_line_next = -1; }

/* Begin an output line of `f` that originates at `srcline` in the .ct. A `#line`
   directive is written only when the running mapping would diverge, so a run of
   consecutive source lines stays directive-free. Only the .c (f == g_out) is
   tracked; the .h is left untouched. */
static void line_at(FILE *f, size_t srcline)
{
    if (f != g_out || !g_emit_line) return;
    if ((long)srcline != g_line_next)
        fprintf(f, "#line %ld \"%s\"\n", (long)srcline, g_path);
    g_line_next = (long)srcline + 1;
}

static void emit_trait_def(FILE *f, const Trait *T, size_t srcline)
{
    int i, k;
    line_at(f, srcline);
    fprintf(f, "struct %s_vtbl {\n", T->cname);
    for (i = 0; i < T->nm; i++) {
        const Method *m = &T->m[i];
        fprintf(f, "    %s (*%s)(void *", m->ret, m->name);
        for (k = 0; k < m->nparams; k++) fprintf(f, ", %s", m->ptypes[k]);
        fprintf(f, ");\n");
    }
    fprintf(f, "};\n");
    /* the interface value type: a fat pointer to an object plus its vtable */
    fprintf(f, "struct %s_iface {\n    void *self;\n    struct %s_vtbl *vt;\n};\n",
            T->cname, T->cname);
    line_break();
}

static void emit_struct_def(FILE *f, const Struct *S, const char *body, size_t srcline)
{
    int i;
    size_t blen = strlen(body);

    line_at(f, srcline);
    fprintf(f, "struct %s {", S->cname);
    if (blen && body[0] != '\n') fputc('\n', f);
    if (blen) fputs(body, f);
    if (blen == 0 || body[blen - 1] != '\n') fputc('\n', f);
    for (i = 0; i < S->nu; i++) {
        char low[MAX_NAME];
        to_lower(S->use_t[i], low);
        fprintf(f, "    struct %s_vtbl *__%s_vptr;\n", g_traits[S->use_i[i]].cname, low);
    }
    fprintf(f, "};\n");
    line_break();
}

/* does the body call a sibling method, i.e. `self->m(` for a used trait method? */
static int body_calls_sibling(size_t bstart, size_t blen, const Struct *S)
{
    size_t i = bstart, end = bstart + blen;
    while (i < end) {
        char c = g_src[i];
        if (c == '"' || c == '\'') { size_t j = skip_literal(i); i = (j > end) ? end : j; continue; }
        if (c == '/' && i + 1 < end &&
            (g_src[i + 1] == '/' || g_src[i + 1] == '*')) {
            size_t j = skip_comment(i); i = (j > end) ? end : j; continue;
        }
        if (is_ident_char((unsigned char)c) && !isdigit((unsigned char)c)) {
            size_t j = i;
            while (j < end && is_ident_char((unsigned char)g_src[j])) j++;
            if (j - i == 4 && memcmp(g_src + i, "self", 4) == 0 &&
                j + 2 < end && g_src[j] == '-' && g_src[j + 1] == '>') {
                size_t ms = j + 2, e = ms, ml;
                char mem[MAX_NAME];
                while (e < end && is_ident_char((unsigned char)g_src[e])) e++;
                ml = e - ms;
                if (ml > 0 && ml < MAX_NAME && e < end && g_src[e] == '(') {
                    memcpy(mem, g_src + ms, ml);
                    mem[ml] = 0;
                    if (resolve_method(S, mem)) return 1;
                }
            }
            i = j;
            continue;
        }
        i++;
    }
    return 0;
}

/* `self` -> `_self`; `self->m(...)` -> `_self->__<trait>_vptr->m(_self, ...)`.
   Strings and comments are copied verbatim. */
static void replace_self(size_t bstart, size_t blen, const Struct *S, Buf *out)
{
    size_t i = bstart, end = bstart + blen;
    while (i < end) {
        char c = g_src[i];
        if (c == '"' || c == '\'') {
            size_t j = skip_literal(i);
            if (j > end) j = end;
            buf_putn(out, g_src + i, j - i);
            i = j;
            continue;
        }
        if (c == '/' && (i + 1 < end) &&
            (g_src[i + 1] == '/' || g_src[i + 1] == '*')) {
            size_t j = skip_comment(i);
            if (j > end) j = end;
            buf_putn(out, g_src + i, j - i);
            i = j;
            continue;
        }
        if (is_ident_char((unsigned char)c) && !isdigit((unsigned char)c)) {
            size_t j = i;
            while (j < end && is_ident_char((unsigned char)g_src[j])) j++;
            if (j - i == 4 && memcmp(g_src + i, "self", 4) == 0) {
                if (j + 2 < end && g_src[j] == '-' && g_src[j + 1] == '>') {
                    size_t ms = j + 2, e = ms, ml;
                    char mem[MAX_NAME], low[MAX_NAME];
                    const char *tr;
                    while (e < end && is_ident_char((unsigned char)g_src[e])) e++;
                    ml = e - ms;
                    if (ml > 0 && ml < MAX_NAME && e < end && g_src[e] == '(') {
                        size_t z = e + 1;
                        int empty;
                        memcpy(mem, g_src + ms, ml);
                        mem[ml] = 0;
                        tr = resolve_method(S, mem);
                        while (z < end && isspace((unsigned char)g_src[z])) z++;
                        empty = (z < end && g_src[z] == ')');
                        if (tr) {
                            to_lower(tr, low);
                            buf_puts(out, "_self->__");
                            buf_puts(out, low);
                            buf_puts(out, "_vptr->");
                            buf_puts(out, mem);
                            buf_putc(out, '(');
                            buf_puts(out, "_self");
                            if (!empty) buf_puts(out, ", ");
                            i = e + 1;
                            continue;
                        }
                    }
                }
                buf_puts(out, "_self");
            } else {
                buf_putn(out, g_src + i, j - i);
            }
            i = j;
            continue;
        }
        buf_putc(out, c);
        i++;
    }
}

/* re-indent a method body: drop the shared indentation, use 4 spaces */
static void emit_body(FILE *f, size_t bstart, size_t blen, const Struct *S)
{
    Buf r;
    size_t i, j, n;
    size_t bl_first = line_of(bstart);   /* source line of body line 0 */
    int minind = 1 << 30;
    size_t *ls, *le;
    int nlines = 0, first = -1, last = -1, k;

    buf_init(&r);
    replace_self(bstart, blen, S, &r);
    n = r.n;

    ls = xmalloc(sizeof(size_t) * (n + 2));
    le = xmalloc(sizeof(size_t) * (n + 2));

    i = 0;
    while (i < n) {
        j = i;
        while (j < n && r.p[j] != '\n') j++;
        ls[nlines] = i;
        le[nlines] = j;
        nlines++;
        i = j + 1;
        if (j == n) break;
    }

    for (k = 0; k < nlines; k++) {
        size_t t = ls[k];
        while (t < le[k] && (r.p[t] == ' ' || r.p[t] == '\t')) t++;
        if (t < le[k]) {
            int ind = (int)(t - ls[k]);
            if (ind < minind) minind = ind;
            if (first < 0) first = k;
            last = k;
        }
    }

    if (first < 0) { free(ls); free(le); free(r.p); return; }
    if (minind == 1 << 30) minind = 0;

    line_break();   /* anchor: the first body line always carries a #line */
    for (k = first; k <= last; k++) {
        size_t t = ls[k];
        while (t < le[k] && (r.p[t] == ' ' || r.p[t] == '\t')) t++;
        line_at(f, bl_first + (size_t)k);
        if (t >= le[k]) { fputc('\n', f); continue; }
        fputs("    ", f);
        fwrite(r.p + ls[k] + minind, 1, le[k] - ls[k] - minind, f);
        fputc('\n', f);
    }
    line_break();

    free(ls);
    free(le);
    free(r.p);
}

/* ------------------------------------------------------- construct parsers */

static size_t parse_trait(size_t p)
{
    char name[MAX_NAME];
    Trait *T;
    size_t close, bstart, bend, i;
    size_t tline = line_of(p);                   /* source line of 'trait' */
    Buf raw, clean;

    p += 5;                                     /* "trait" */
    p = skip_ws_comments(p);
    p = read_ident(p, name, sizeof name);
    if (!name[0]) die(p, "expected trait name");
    if (strcmp(name, "Drop") == 0) die(p, "'Drop' is a reserved built-in trait and cannot be defined");
    p = skip_ws_comments(p);
    if (p >= g_len || g_src[p] != '{') die(p, "expected '{' after trait '%s'", name);

    close = match_delim(p, '{', '}');
    bstart = p + 1;
    bend = close;

    if (g_ntraits >= MAX_TRAITS) die(p, "too many traits (max %d)", MAX_TRAITS);
    T = &g_traits[g_ntraits++];
    snprintf(T->name, sizeof T->name, "%s", name);
    set_cname(T->cname, sizeof T->cname, g_ns, name, p);
    T->nm = 0;

    buf_init(&raw);
    buf_putn(&raw, g_src + bstart, bend - bstart);
    buf_init(&clean);
    {
        /* strip comments once so ';' inside them does not split declarations */
        size_t k = 0, ln = raw.n;
        while (k < ln) {
            char c = raw.p[k];
            if (c == '"' || c == '\'') {
                char q = c;
                buf_putc(&clean, raw.p[k++]);
                while (k < ln) {
                    if (raw.p[k] == '\\' && k + 1 < ln) {
                        buf_putc(&clean, raw.p[k]);
                        buf_putc(&clean, raw.p[k + 1]);
                        k += 2;
                        continue;
                    }
                    buf_putc(&clean, raw.p[k]);
                    if (raw.p[k] == q) { k++; break; }
                    k++;
                }
                continue;
            }
            if (c == '/' && k + 1 < ln && raw.p[k + 1] == '/') {
                while (k < ln && raw.p[k] != '\n') k++;
                continue;
            }
            if (c == '/' && k + 1 < ln && raw.p[k + 1] == '*') {
                k += 2;
                while (k + 1 < ln && !(raw.p[k] == '*' && raw.p[k + 1] == '/')) k++;
                k = (k + 1 < ln) ? k + 2 : ln;
                continue;
            }
            buf_putc(&clean, raw.p[k++]);
        }
    }
    free(raw.p);

    i = 0;
    for (;;) {
        size_t j = i;
        while (j <= clean.n && !(j < clean.n && clean.p[j] == ';')) j++;
        {
            char *seg = xstrndup(clean.p + i, j - i);
            trim(seg);
            if (seg[0]) {
                if (T->nm >= MAX_METHOD)
                    die(close, "too many methods in trait '%s'", T->name);
                split_decl(seg, close, &T->m[T->nm]);
                T->nm++;
            }
            free(seg);
        }
        if (j >= clean.n) break;
        i = j + 1;
    }
    free(clean.p);

    if (!g_multi) { emit_trait_def(g_out, T, tline); emit_trait_def(g_hout, T, tline); }
    else if (g_ctor_pub) emit_trait_def(g_hout, T, tline);
    else emit_trait_def(g_out, T, tline);
    return close + 1;
}

/* Rewrite a struct body so that a field whose type names a known struct gains
   the "struct " keyword, and record those fields (for nested construction and
   chained calls). Returns a new body string. */
static char *parse_fields(const char *body, Struct *S, size_t pos)
{
    Buf out;
    size_t n = strlen(body), i = 0;

    S->nf = 0;
    buf_init(&out);

    while (i < n) {
        size_t j = i, depth = 0;
        int ia = -1, ib = -1, need_struct = 0, ptr = 0, idx, tr;
        char fname[MAX_NAME], cbase[MAX_NAME];

        /* one field: up to the next top-level ';' */
        while (j < n) {
            char c = body[j];
            if (c == '"' || c == '\'') {
                char q = c;
                j++;
                while (j < n) {
                    if (body[j] == '\\' && j + 1 < n) { j += 2; continue; }
                    if (body[j] == q) { j++; break; }
                    j++;
                }
                continue;
            }
            if (c == '{' || c == '(' || c == '[') depth++;
            else if (c == '}' || c == ')' || c == ']') depth--;
            else if (c == ';' && depth == 0) break;
            j++;
        }

        idx = analyse_param(body + i, j - i, &ia, &ib, cbase, &need_struct, fname, &ptr, &tr);
        emit_qualified_type(&out, body + i, j - i, ia, ib, cbase, need_struct, tr >= 0);
        if (idx >= 0 && fname[0] && !ptr) {          /* value field of a known struct */
            if (S->nf >= MAX_FIELDS) die(pos, "too many struct fields in '%s'", S->name);
            snprintf(S->fname[S->nf], MAX_NAME, "%s", fname);
            S->ftype[S->nf] = idx;
            S->nf++;
        }
        if (j < n) { buf_putc(&out, ';'); j++; }
        i = j;
    }
    return out.p;
}

static size_t parse_struct(size_t p)
{
    char name[MAX_NAME];
    Struct *S;
    size_t close, bstart, bend, q, probe;
    size_t sline = line_of(p);                    /* source line of 'struct' */
    int i;

    p += 6;                                     /* "struct" */
    p = skip_ws_comments(p);
    p = read_ident(p, name, sizeof name);
    if (!name[0]) die(p, "expected struct name");
    p = skip_ws_comments(p);
    if (p >= g_len || g_src[p] != '{') die(p, "expected '{' after struct '%s'", name);

    close = match_delim(p, '{', '}');
    bstart = p + 1;
    bend = close;

    if (g_nstructs >= MAX_STRUCT) die(p, "too many structs (max %d)", MAX_STRUCT);
    S = &g_structs[g_nstructs++];
    snprintf(S->name, sizeof S->name, "%s", name);
    set_cname(S->cname, sizeof S->cname, g_ns, name, p);
    S->nu = 0;
    S->has_drop = 0;
    S->drop_used = 0;
    S->has_user_drop = 0;
    S->drop_bstart = S->drop_blen = 0;
    S->def_line = sline;

    q = close + 1;
    probe = q;
    while (probe < g_len && (g_src[probe] == ' ' || g_src[probe] == '\t')) probe++;
    if (probe < g_len && g_src[probe] == '\n') {
        size_t t = probe + 1;
        while (t < g_len && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
        if (word_at(t, "use")) probe = t;
    }

    if (word_at(probe, "use")) {
        size_t u = skip_ws_comments(probe + 3);
        for (;;) {
            char tn[MAX_NAME];
            u = read_ident(u, tn, sizeof tn);
            if (!tn[0]) die(u, "expected trait name in 'use' clause of '%s'", S->name);
            if (strcmp(tn, "Drop") == 0) {
                S->has_drop = 1;              /* reserved marker: no vtable/vptr, no impl needed */
            } else {
                if (S->nu >= MAX_TRAITS) die(u, "too many traits used by '%s'", S->name);
                snprintf(S->use_t[S->nu], MAX_NAME, "%s", tn);
                S->nu++;
            }
            u = skip_ws_comments(u);
            if (u < g_len && g_src[u] == ',') { u = skip_ws_comments(u + 1); continue; }
            break;
        }
        if (u >= g_len || g_src[u] != ';') die(u, "expected ';' after 'use' clause of '%s'", S->name);
        q = u + 1;
    } else {
        size_t t = q;
        while (t < g_len && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
        if (t < g_len && g_src[t] == ';') q = t + 1;
    }

    for (i = 0; i < S->nu; i++) {
        Trait *T = find_trait(S->use_t[i]);
        if (!T)
            die(p, "struct '%s' uses undefined trait '%s'", S->name, S->use_t[i]);
        S->use_i[i] = (int)(T - g_traits);
    }

    if (S->has_drop && g_nown_drop < MAX_STRUCT)
        g_own_drop[g_nown_drop++] = (int)(S - g_structs);

    {
        char *raw = xstrndup(g_src + bstart, bend - bstart);
        char *qbody = parse_fields(raw, S, p);
        free(raw);
        if (!g_multi) { emit_struct_def(g_out, S, qbody, sline); emit_struct_def(g_hout, S, qbody, sline); }
        else if (g_ctor_pub) emit_struct_def(g_hout, S, qbody, sline);
        else emit_struct_def(g_out, S, qbody, sline);
        free(qbody);
    }
    return q;
}

static size_t parse_impl(size_t p)
{
    char trait_name[MAX_NAME], struct_name[MAX_NAME];
    Trait *T;
    Struct *S;
    size_t close, i, k;
    size_t dline = line_of(p);                    /* source line of 'impl' */
    ImplMethod impl[MAX_METHOD];
    int nimpl = 0, found;

    p += 4;                                     /* "impl" */
    p = skip_ws_comments(p);
    p = read_ident(p, trait_name, sizeof trait_name);
    if (!trait_name[0]) die(p, "expected trait name after 'impl'");
    p = skip_ws_comments(p);
    if (!word_at(p, "for")) die(p, "expected 'for' in impl of '%s'", trait_name);
    p = skip_ws_comments(p + 3);
    p = read_ident(p, struct_name, sizeof struct_name);
    if (!struct_name[0]) die(p, "expected struct name after 'for'");
    p = skip_ws_comments(p);
    if (p >= g_len || g_src[p] != '{') die(p, "expected '{' in impl body");

    close = match_delim(p, '{', '}');

    if (strcmp(trait_name, "Drop") == 0) {
        /* `impl Drop for T { void drop() { … } }` — capture the user body; the
           drop function itself is emitted lazily (only when a delete is seen). */
        size_t i2 = skip_ws_comments(p + 1), rp, bp, be;
        S = find_struct(struct_name);
        if (!S) die(p, "impl for undefined struct '%s'", struct_name);
        if (!S->has_drop) die(p, "struct '%s' does not use trait 'Drop'", S->name);
        while (i2 < close && g_src[i2] != '(') i2++;
        if (i2 >= close) die(p, "expected 'drop()' in impl of 'Drop' for '%s'", S->name);
        rp = match_delim(i2, '(', ')');
        bp = skip_ws_comments(rp + 1);
        if (bp >= close || g_src[bp] != '{') die(bp, "expected '{' to start the drop() body");
        be = match_delim(bp, '{', '}');
        S->has_user_drop = 1;
        S->drop_bstart = bp + 1;
        S->drop_blen = be - bp - 1;
        {
            size_t q = close + 1, t = q;
            while (t < g_len && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
            if (t < g_len && g_src[t] == ';') q = t + 1;
            return q;
        }
    }

    T = find_trait(trait_name);
    if (!T) die(p, "impl for undefined trait '%s'", trait_name);
    S = find_struct(struct_name);
    if (!S) die(p, "impl for undefined struct '%s'", struct_name);
    if (!struct_uses(S, T->name))
        die(p, "struct '%s' does not use trait '%s'", S->name, T->name);

    /* collect the methods written in the impl block */
    i = p + 1;
    while (1) {
        size_t lp, rp, bp, be;
        char header[MAX_NAME * 2];
        char pre[MAX_NAME * 2];
        int end, st;

        i = skip_ws_comments(i);
        if (i >= close) break;

        lp = i;
        while (lp < close && g_src[lp] != '(') lp++;
        if (lp >= close) die(i, "expected method declaration inside impl of '%s' for '%s'",
                             T->name, S->name);

        snprintf(pre, sizeof pre, "%.*s", (int)(lp - i), g_src + i);
        trim(pre);
        end = (int)strlen(pre);
        st = end;
        while (st > 0 && is_ident_char((unsigned char)pre[st - 1])) st--;
        if (st == end) die(i, "expected method name inside impl of '%s' for '%s'",
                           T->name, S->name);
        if (nimpl >= MAX_METHOD) die(i, "too many methods in impl of '%s'", T->name);
        snprintf(header, sizeof header, "%.*s", end - st, pre + st);

        rp = match_delim(lp, '(', ')');
        {
            size_t blen = (rp > lp + 1) ? (rp - lp - 1) : 0;
            if (blen >= MAX_PARAM) die(lp, "parameter list too long (max %d)", MAX_PARAM - 1);
            memcpy(impl[nimpl].params, g_src + lp + 1, blen);
            impl[nimpl].params[blen] = 0;
            trim(impl[nimpl].params);
        }

        bp = skip_ws_comments(rp + 1);
        if (bp >= close || g_src[bp] != '{')
            die(bp, "expected '{' to start body of method '%s'", header);
        be = match_delim(bp, '{', '}');

        snprintf(impl[nimpl].name, MAX_NAME, "%s", header);
        impl[nimpl].bstart = bp + 1;
        impl[nimpl].blen = be - bp - 1;
        nimpl++;

        i = be + 1;
    }

    /* every impl method must belong to the trait */
    for (k = 0; k < (size_t)nimpl; k++) {
        found = 0;
        for (int j = 0; j < T->nm; j++)
            if (strcmp(T->m[j].name, impl[k].name) == 0) { found = 1; break; }
        if (!found)
            die(p, "method '%s' is not declared in trait '%s'", impl[k].name, T->name);
    }

    /* bodies that call a sibling method need the vtable declared up front */
    {
        int needs_vtable = 0;
        for (k = 0; k < (size_t)nimpl; k++)
            if (body_calls_sibling(impl[k].bstart, impl[k].blen, S)) { needs_vtable = 1; break; }
        if (needs_vtable) {
            line_at(g_out, dline);
            fprintf(g_out, "static struct %s_vtbl %s_%s_vtable;\n\n",
                    T->cname, S->cname, T->name);
            line_break();
        }
    }

    /* emit one function per trait method, in trait order */
    for (k = 0; k < (size_t)T->nm; k++) {
        Method *tm = &T->m[k];
        int idx = -1;
        for (int j = 0; j < nimpl; j++)
            if (strcmp(impl[j].name, tm->name) == 0) { idx = j; break; }
        if (idx < 0)
            die(p, "trait method '%s' is not implemented for struct '%s'",
                tm->name, S->name);

        line_at(g_out, dline);
        fprintf(g_out, "static %s %s_%s_%s(void *self", tm->ret, S->cname, T->name, tm->name);
        if (tm->nparams > 0) fprintf(g_out, ", %s", impl[idx].params);
        fprintf(g_out, ") {\n");
        fprintf(g_out, "    struct %s *_self = (struct %s *)self;\n", S->cname, S->cname);
        emit_body(g_out, impl[idx].bstart, impl[idx].blen, S);
        fprintf(g_out, "}\n\n");
        line_break();
    }

    line_at(g_out, dline);
    fprintf(g_out, "static struct %s_vtbl %s_%s_vtable = {\n",
            T->cname, S->cname, T->name);
    for (k = 0; k < (size_t)T->nm; k++)
        fprintf(g_out, "    .%s = %s_%s_%s%s\n",
                T->m[k].name, S->cname, T->name, T->m[k].name,
                (k + 1 < (size_t)T->nm) ? "," : "");
    fprintf(g_out, "};\n\n");
    line_break();

    {
        size_t q = close + 1;
        size_t t = q;
        while (t < g_len && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
        if (t < g_len && g_src[t] == ';') q = t + 1;
        return q;
    }
}

/* ------------------------------------------------- raw line rewriting */

static size_t line_literal_end(const char *s, size_t i, size_t n)
{
    char q = s[i++];
    while (i < n) {
        if (s[i] == '\\' && i + 1 < n) { i += 2; continue; }
        if (s[i] == q) return i + 1;
        i++;
    }
    return n;
}

static size_t line_match_paren(const char *s, size_t k, size_t n)
{
    int depth = 0;
    while (k < n) {
        char c = s[k];
        if (c == '"' || c == '\'') { k = line_literal_end(s, k, n); continue; }
        if (c == '(') depth++;
        else if (c == ')') { depth--; if (!depth) return k; }
        k++;
    }
    return (size_t)-1;
}

/* append one ".__<trait>_vptr = &<Struct>_<Trait>_vtable" per used trait */
static void put_own_vptr(Buf *b, const Struct *S, int *first)
{
    int h;
    for (h = 0; h < S->nu; h++) {
        char low[MAX_NAME];
        to_lower(S->use_t[h], low);
        if (!*first) buf_puts(b, ", ");
        *first = 0;
        buf_puts(b, ".__");
        buf_puts(b, low);
        buf_puts(b, "_vptr = &");
        buf_puts(b, S->cname);
        buf_putc(b, '_');
        buf_puts(b, S->use_t[h]);
        buf_puts(b, "_vtable");
    }
}

/* does S (recursively) contain a field whose vptr must be written? */
static int needs_nested_init(const Struct *S, int depth)
{
    int i;
    if (depth >= MAX_DEPTH) die(0, "nesting too deep in struct '%s'", S->name);
    for (i = 0; i < S->nf; i++) {
        const Struct *F = &g_structs[S->ftype[i]];
        if (F->nu > 0 || needs_nested_init(F, depth + 1)) return 1;
    }
    return 0;
}

/* emit "recv.__<trait>_vptr = &...;" for recv (when `with_self`) and, recursively,
   for its fields. Statements (not designators) are used so that a nested object
   the user has already initialised is never overridden. */
static void put_nested_assignments(Buf *b, const Struct *S, const char *recv,
                                   const char *ind, int with_self, int depth)
{
    int i, h;
    for (h = 0; with_self && h < S->nu; h++) {
        char low[MAX_NAME];
        to_lower(S->use_t[h], low);
        buf_puts(b, ind);
        buf_puts(b, recv);
        buf_puts(b, ".__");
        buf_puts(b, low);
        buf_puts(b, "_vptr = &");
        buf_puts(b, S->cname);
        buf_putc(b, '_');
        buf_puts(b, S->use_t[h]);
        buf_puts(b, "_vtable;\n");
    }
    for (i = 0; i < S->nf; i++) {
        const Struct *F = &g_structs[S->ftype[i]];
        char sub[MAX_NAME * (MAX_DEPTH + 3)];
        if (F->nu == 0 && !needs_nested_init(F, depth + 1)) continue;
        if ((size_t)snprintf(sub, sizeof sub, "%s.%s", recv, S->fname[i]) >= sizeof sub)
            die(0, "nested field path too long in struct '%s'", S->name);
        put_nested_assignments(b, F, sub, ind, 1, depth + 1);
    }
}

/* write the vptrs of a heap object obtained from malloc/calloc: the object's own
   vptrs use '->', its value fields recurse with '.'. */
static void put_heap_vpts(Buf *b, const Struct *S, const char *ptr, const char *ind)
{
    int i, h;
    for (h = 0; h < S->nu; h++) {
        char low[MAX_NAME];
        to_lower(S->use_t[h], low);
        buf_puts(b, ind);
        buf_puts(b, ptr);
        buf_puts(b, "->__");
        buf_puts(b, low);
        buf_puts(b, "_vptr = &");
        buf_puts(b, S->cname);
        buf_putc(b, '_');
        buf_puts(b, S->use_t[h]);
        buf_puts(b, "_vtable;\n");
    }
    for (i = 0; i < S->nf; i++) {
        const Struct *F = &g_structs[S->ftype[i]];
        char sub[MAX_NAME * (MAX_DEPTH + 3)];
        if (F->nu == 0 && !needs_nested_init(F, 1)) continue;
        if ((size_t)snprintf(sub, sizeof sub, "%s->%s", ptr, S->fname[i]) >= sizeof sub)
            die(0, "nested field path too long in struct '%s'", S->name);
        put_nested_assignments(b, F, sub, ind, 1, 1);
    }
}

/* is the tail of a declaration nothing but ';' (optionally a trailing comment)? */
static int decl_end_is_bare(const char *s)
{
    while (*s == ' ' || *s == '\t') s++;
    if (*s != ';') return 0;
    s++;
    for (;;) {
        while (*s == ' ' || *s == '\t') s++;
        if (!*s) return 1;
        if (s[0] == '/' && s[1] == '/') return 1;
        if (s[0] == '/' && s[1] == '*') {
            const char *e = strstr(s + 2, "*/");
            if (!e) return 1;
            s = e + 2;
            continue;
        }
        return 0;
    }
}

/* Append `e` boxed into the interface value of trait `tr`, or verbatim when it
   already is an interface value of that trait. Dies when the expression's type
   cannot be inferred (only a variable or `&variable` can be boxed). */
static void box_to_iface(Buf *out, const char *e, size_t len, int tr, size_t pos)
{
    char id[MAX_NAME];
    const char *q = e, *r;
    size_t ql = len, k = 0;
    int vi, amped = 0;
    Struct *S;

    while (ql > 0 && isspace((unsigned char)*q)) { q++; ql--; }
    while (ql > 0 && isspace((unsigned char)q[ql - 1])) ql--;
    if (ql == 0) die(pos, "cannot infer the type of the boxed value");
    if (*q == '&') { amped = 1; q++; ql--; }
    if (ql == 0 || ql >= MAX_NAME) die(pos, "cannot infer the type of the boxed value");

    while (k < ql && is_ident_char((unsigned char)q[k])) k++;
    if (k == 0) die(pos, "cannot infer the type of the boxed value");
    memcpy(id, q, k);
    id[k] = 0;
    r = q + k;
    while (r < q + ql && isspace((unsigned char)*r)) r++;

    if (*r == '(') {                       /* a call: it must already return this interface */
        FuncSig *FS = find_func(id);
        if (FS && FS->rettrait == tr) { buf_putn(out, e, len); return; }
        if (FS && FS->rettrait >= 0)
            die(pos, "'%s' returns an interface value of a different trait", id);
        die(pos, "cannot infer the type of the boxed value");
    }
    if (r != q + ql)
        die(pos, "cannot infer the type of the boxed value");   /* not a plain name */

    vi = find_var(id);
    if (vi < 0) die(pos, "cannot infer the type of '%s'", id);
    if (g_vars[vi].iface) {
        if (g_vars[vi].tr != tr)
            die(pos, "'%s' is an interface value of a different trait", id);
        if (amped) die(pos, "'%s' is already an interface value", id);
        buf_putn(out, e, len);                       /* already an interface value */
        return;
    }
    if (amped && g_vars[vi].ptr)
        die(pos, "'&%s' is not an object of a struct type", id);

    S = &g_structs[g_vars[vi].s];
    if (!struct_uses(S, g_traits[tr].name))
        die(pos, "struct '%s' does not use trait '%s'", S->name, g_traits[tr].name);

    buf_puts(out, "(struct ");
    buf_puts(out, g_traits[tr].cname);
    buf_puts(out, "_iface){ (void *)");
    if (g_vars[vi].ptr) buf_puts(out, id);
    else { buf_putc(out, '&'); buf_puts(out, id); }
    buf_puts(out, ", &");
    buf_puts(out, S->cname);
    buf_putc(out, '_');
    buf_puts(out, g_traits[tr].name);
    buf_puts(out, "_vtable }");
}

static void transform_calls(const char *s, Buf *out)
{
    size_t i = 0, n = strlen(s);
    while (i < n) {
        char c = s[i];

        if (c == '"' || c == '\'') {
            size_t j = line_literal_end(s, i, n);
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        if (c == '/' && i + 1 < n && s[i + 1] == '/') {
            buf_putn(out, s + i, n - i);
            break;
        }
        if (c == '/' && i + 1 < n && s[i + 1] == '*') {
            size_t j = i + 2;
            while (j + 1 < n && !(s[j] == '*' && s[j + 1] == '/')) j++;
            j = (j + 1 < n) ? j + 2 : n;
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        if (is_ident_char((unsigned char)c) && !isdigit((unsigned char)c)) {
            size_t j = i;
            char tok[MAX_NAME];
            size_t tl;
            int vi;

            while (j < n && is_ident_char((unsigned char)s[j])) j++;
            tl = j - i;
            if (tl >= sizeof tok) tl = sizeof tok - 1;
            memcpy(tok, s + i, tl);
            tok[tl] = 0;

            /* namespace path `A::B::name`: a call drops the path (functions are
               not mangled), anything else is mangled to a C name `A_B_name` */
            if (j + 1 < n && s[j] == ':' && s[j + 1] == ':') {
                size_t z = j, finalstart = i, chainend = j;
                int ok = 0;
                while (z + 1 < n && s[z] == ':' && s[z + 1] == ':') {
                    size_t w = z + 2;
                    while (w < n && isspace((unsigned char)s[w])) w++;
                    if (!(w < n && is_ident_char((unsigned char)s[w]) && !isdigit((unsigned char)s[w]))) break;
                    finalstart = w;
                    while (w < n && is_ident_char((unsigned char)s[w])) w++;
                    chainend = w;
                    ok = 1;
                    z = w;
                    while (z < n && isspace((unsigned char)s[z])) z++;
                }
                if (ok) {
                    if (chainend < n && s[chainend] == '(') {
                        i = finalstart;
                    } else {
                        char mc[MAX_NAME * 2];
                        qual_to_c(s, i, chainend, mc, sizeof mc);
                        buf_puts(out, mc);
                        i = chainend;
                    }
                    continue;
                }
            }

            vi = find_var(tok);
            if (vi >= 0 && g_vars[vi].iface) {
                /* interface dispatch: g.m(args) -> g.vt->m(g.self, args) */
                if (j < n && s[j] == '.') {
                    size_t k = j + 1, ms = k, ml;
                    char mem[MAX_NAME];
                    while (k < n && is_ident_char((unsigned char)s[k])) k++;
                    ml = k - ms;
                    if (ml >= sizeof mem) ml = sizeof mem - 1;
                    memcpy(mem, s + ms, ml);
                    mem[ml] = 0;
                    if (ml && k < n && s[k] == '(' &&
                        trait_has_method(&g_traits[g_vars[vi].tr], mem)) {
                        size_t z = k + 1;
                        int empty;
                        while (z < n && isspace((unsigned char)s[z])) z++;
                        empty = (z < n && s[z] == ')');
                        buf_puts(out, tok);
                        buf_puts(out, ".vt->");
                        buf_puts(out, mem);
                        buf_putc(out, '(');
                        buf_puts(out, tok);
                        buf_puts(out, ".self");
                        if (!empty) buf_puts(out, ", ");
                        i = k + 1;
                        continue;
                    }
                }
            }
            if (!g_no_box && vi < 0 && j < n && s[j] == '(') {
                /* a call to a function with interface parameters: box those args */
                FuncSig *FS = find_func(tok);
                size_t cp = (size_t)-1;
                int any = 0, q;
                if (FS) {
                    for (q = 0; q < FS->nparams; q++)
                        if (FS->ptrait[q] >= 0) { any = 1; break; }
                    if (any) cp = line_match_paren(s, j, n);
                }
                if (any && cp != (size_t)-1) {
                    Buf ab;
                    size_t a = j + 1, pi = 0;
                    buf_init(&ab);
                    while (a <= cp) {
                        size_t bb = a;
                        int dep = 0, tr;
                        while (bb < cp) {
                            char cc = s[bb];
                            if (cc == '"' || cc == '\'') { bb = line_literal_end(s, bb, cp); continue; }
                            if (cc == '(' || cc == '[' || cc == '{') dep++;
                            else if (cc == ')' || cc == ']' || cc == '}') dep--;
                            else if (cc == ',' && dep == 0) break;
                            bb++;
                        }
                        tr = (pi < (size_t)FS->nparams) ? FS->ptrait[pi] : -1;
                        if (tr >= 0 && bb > a) box_to_iface(&ab, s + a, bb - a, tr, 0);
                        else buf_putn(&ab, s + a, bb - a);
                        pi++;
                        if (bb < cp) { buf_putc(&ab, ','); a = bb + 1; }
                        else break;
                    }
                    buf_puts(out, tok);
                    buf_putc(out, '(');
                    buf_puts(out, ab.p);
                    buf_putc(out, ')');
                    free(ab.p);
                    i = cp + 1;
                    continue;
                }
            }
            if (vi >= 0) {
                /* walk ".field" hops, then rewrite the final ".m(" / "->m(" */
                char mem[MAX_NAME], low[MAX_NAME];
                const char *tr = NULL;
                size_t pos = j, mp = 0;
                int cur = g_vars[vi].s, need_amp = 1, hit = 0;

                for (;;) {
                    size_t ms, k, ml;
                    int isptr, fi;

                    if (pos == j && g_vars[vi].arr) {
                        /* the receiver is an element: consume "[<n>]" */
                        if (!(pos < n && s[pos] == '[')) break;
                        k = pos + 1;
                        while (k < n && s[k] >= '0' && s[k] <= '9') k++;
                        if (!(k < n && s[k] == ']')) break;
                        pos = k + 1;
                        continue;
                    }
                    isptr = (pos == j) ? g_vars[vi].ptr : 0;

                    if (isptr) {
                        if (!(pos + 1 < n && s[pos] == '-' && s[pos + 1] == '>')) break;
                        k = pos + 2;
                    } else {
                        if (!(pos < n && s[pos] == '.')) break;
                        k = pos + 1;
                    }
                    ms = k;
                    while (k < n && is_ident_char((unsigned char)s[k])) k++;
                    ml = k - ms;
                    if (ml == 0) break;
                    if (ml >= sizeof mem) ml = sizeof mem - 1;
                    memcpy(mem, s + ms, ml);
                    mem[ml] = 0;

                    tr = resolve_method(&g_structs[cur], mem);
                    if (tr && k < n && s[k] == '(') {
                        need_amp = !isptr;
                        mp = k;
                        hit = 1;
                        break;
                    }
                    tr = NULL;
                    fi = find_field(&g_structs[cur], mem);
                    if (fi < 0) break;
                    cur = g_structs[cur].ftype[fi];
                    pos = k;
                }

                if (hit) {
                    size_t z = mp + 1;
                    int empty;
                    while (z < n && isspace((unsigned char)s[z])) z++;
                    empty = (z < n && s[z] == ')');

                    to_lower(tr, low);
                    buf_putn(out, s + i, pos - i);            /* receiver */
                    buf_puts(out, need_amp ? ".__" : "->__");
                    buf_puts(out, low);
                    buf_puts(out, "_vptr->");
                    buf_puts(out, mem);
                    buf_putc(out, '(');
                    if (need_amp) buf_putc(out, '&');
                    buf_putn(out, s + i, pos - i);            /* receiver again */
                    if (!empty) buf_puts(out, ", ");
                    i = mp + 1;
                    continue;
                }
            }
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        buf_putc(out, c);
        i++;
    }
}

/* Read `Ident(::Ident)*` at p (used at the head of a declaration). Fills
   `cname` with the mangled C name (namespace prefix added when unqualified),
   `shortname` with the last segment and `*qualified`. Returns a pointer just
   past the name, or NULL when there is no name. */
static const char *read_qual_ref(const char *p, char *cname, char *shortname, int *qualified)
{
    char buf[MAX_NAME * 2], seg[MAX_NAME];
    size_t i;

    *qualified = 0;
    for (i = 0; is_ident_char((unsigned char)p[i]); i++)
        if (i + 1 >= MAX_NAME) die(0, "identifier too long (max %d)", MAX_NAME - 1);
    if (i == 0) return NULL;
    memcpy(seg, p, i);
    seg[i] = 0;
    snprintf(buf, sizeof buf, "%s", seg);
    p += i;

    for (;;) {
        const char *z = p;
        while (*z == ' ' || *z == '\t') z++;
        if (z[0] == ':' && z[1] == ':') {
            char tmp[MAX_NAME * 2];
            z += 2;
            while (*z == ' ' || *z == '\t') z++;
            for (i = 0; is_ident_char((unsigned char)z[i]); i++)
                if (i + 1 >= MAX_NAME) die(0, "identifier too long (max %d)", MAX_NAME - 1);
            if (i == 0) return NULL;
            memcpy(seg, z, i);
            seg[i] = 0;
            if (snprintf(tmp, sizeof tmp, "%s_%s", buf, seg) >= (int)sizeof tmp) return NULL;
            snprintf(buf, sizeof buf, "%s", tmp);
            *qualified = 1;
            p = z + i;
            continue;
        }
        break;
    }

    snprintf(shortname, MAX_NAME, "%s", seg);
    if (*qualified) snprintf(cname, MAX_NAME, "%s", buf);
    else snprintf(cname, MAX_NAME, "%s%s", g_ns, buf);
    return p;
}

/* "Greeter g;" / "Greeter g = p;" / "Greeter *g;" — an interface-value declaration */
static char *try_iface_decl(const char *line, int tr, size_t ws, const char *after)
{
    char var[MAX_NAME];
    size_t vk = 0;
    const char *p = after;
    const char *rest, *r;
    Buf b;
    int ptr = 0;

    while (*p == ' ' || *p == '\t') p++;
    if (*p == '*') { ptr = 1; p++; while (*p == ' ' || *p == '\t') p++; }
    vk = copy_ident(p, var, 0);
    var[vk] = 0;
    if (!vk) return NULL;
    rest = p + vk;
    r = rest;
    while (*r == ' ' || *r == '\t') r++;

    buf_init(&b);
    buf_putn(&b, line, ws);
    buf_puts(&b, "struct ");
    buf_puts(&b, g_traits[tr].cname);
    buf_puts(&b, ptr ? "_iface *" : "_iface ");
    buf_puts(&b, var);

    if (ptr) {                                       /* a pointer to an interface value */
        if (!decl_end_is_bare(r)) die(0, "unsupported declaration of interface type");
        buf_puts(&b, rest);
        return b.p;
    }

    if (!*r || (*r == ';' && decl_end_is_bare(r))) {
        buf_puts(&b, " = { 0, 0 }");
        buf_puts(&b, rest);
    } else if (*r == '=') {
        const char *e = r + 1;
        size_t el = 0;
        while (*e == ' ' || *e == '\t') e++;
        if (*e == '{') {
            buf_puts(&b, rest);                      /* user-provided aggregate initialiser */
        } else {
            while (e[el] && e[el] != ';') el++;
            buf_puts(&b, " = ");
            box_to_iface(&b, e, el, tr, 0);
            buf_puts(&b, e + el);
        }
    } else {
        die(0, "unsupported declaration of interface type '%s'", g_traits[tr].name);
    }

    {
        int vi = new_var();
        snprintf(g_vars[vi].name, MAX_NAME, "%s", var);
        g_vars[vi].s = -1;
        g_vars[vi].ptr = 0;
        g_vars[vi].arr = 0;
        g_vars[vi].iface = 1;
        g_vars[vi].tr = tr;
    }
    return b.p;
}

/* "return <object>;" inside a function whose return type is an interface value */
static char *try_return(const char *line)
{
    const char *p = line, *e;
    size_t el = 0;
    Buf b;

    if (g_cur_rettr < 0) return NULL;
    while (*p == ' ' || *p == '\t') p++;
    if (strncmp(p, "return", 6) != 0 || is_ident_char((unsigned char)p[6])) return NULL;
    e = p + 6;
    while (*e == ' ' || *e == '\t') e++;
    if (!*e || *e == ';') return NULL;                       /* "return;" */
    if (*e == '{' || strncmp(e, "(struct ", 8) == 0) return NULL;
    while (e[el] && e[el] != ';') el++;
    if (!el) return NULL;

    buf_init(&b);
    buf_putn(&b, line, (size_t)(e - line));
    box_to_iface(&b, e, el, g_cur_rettr, 0);
    buf_puts(&b, e + el);
    return b.p;
}

/* "g = p;" — assigning into an interface value (the target type is the variable) */
static char *try_iface_assign(const char *line)
{
    const char *p = line, *r;
    char id[MAX_NAME];
    size_t k = 0, el = 0;
    int vi;
    Buf b;

    while (*p == ' ' || *p == '\t') p++;
    k = copy_ident(p, id, 0);
    id[k] = 0;
    if (!k) return NULL;
    vi = find_var(id);
    if (vi < 0 || !g_vars[vi].iface) return NULL;
    r = p + k;
    while (*r == ' ' || *r == '\t') r++;
    if (*r != '=' || r[1] == '=') return NULL;
    r++;
    while (*r == ' ' || *r == '\t') r++;
    if (!*r || *r == '{' || strncmp(r, "(struct ", 8) == 0) return NULL;
    while (r[el] && r[el] != ';') el++;
    if (!el) return NULL;

    buf_init(&b);
    buf_putn(&b, line, (size_t)(r - line));
    box_to_iface(&b, r, el, g_vars[vi].tr, 0);
    buf_puts(&b, r + el);
    return b.p;
}

/* "<Struct> x = {...};" / "struct <Struct> x = {...};" -> add struct + vptr */
static char *try_var_decl(const char *line)
{
    size_t i = 0, ws, vk;
    const char *p, *after;
    char name[MAX_NAME], cname[MAX_NAME], var[MAX_NAME];
    Struct *S;
    int qual = 0, done = 0;
    const char *rest;
    Buf b;

    while (line[i] == ' ' || line[i] == '\t') i++;
    ws = i;
    p = line + i;

    if (strncmp(p, "struct", 6) == 0 && !is_ident_char((unsigned char)p[6])) {
        p += 6;
        while (*p == ' ' || *p == '\t') p++;
    }

    after = read_qual_ref(p, cname, name, &qual);
    if (!after) return NULL;
    p = after;
    S = qual ? find_struct_c(cname) : find_struct(name);
    if (!S) {
        Trait *TR = qual ? find_trait_c(cname) : find_trait(name);
        if (!TR) return NULL;
        return try_iface_decl(line, (int)(TR - g_traits), ws, p);
    }
    while (*p == ' ' || *p == '\t') p++;

    if (*p == '*') {                              /* pointer decl: qualify + register */
        const char *q = p;
        char pv[MAX_NAME];
        int pk = 0;
        while (*q == '*' || *q == ' ' || *q == '\t') q++;
        pk = copy_ident(q, pv, 0);
        pv[pk] = 0;
        if (pk) {
            int vi = new_var();
            snprintf(g_vars[vi].name, MAX_NAME, "%s", pv);
            g_vars[vi].s = (int)(S - g_structs);
            g_vars[vi].ptr = 1;
            g_vars[vi].arr = 0;
            g_vars[vi].iface = 0;
            g_vars[vi].tr = -1;
        }
        buf_init(&b);
        buf_putn(&b, line, ws);
        buf_puts(&b, "struct ");
        buf_puts(&b, S->cname);
        buf_putc(&b, ' ');
        buf_puts(&b, p);
        /* heap creation (Phase 1, D1=A): `T *x = malloc(...)` / calloc gets its
           vptrs written, so a heap object is usable without a hand-written vptr */
        {
            const char *eq = strchr(p, '=');
            const char *rhs = eq ? eq + 1 : NULL;
            if (rhs) {
                while (*rhs == ' ' || *rhs == '\t') rhs++;
                if (((strncmp(rhs, "malloc", 6) == 0 && !is_ident_char((unsigned char)rhs[6])) ||
                     (strncmp(rhs, "calloc", 6) == 0 && !is_ident_char((unsigned char)rhs[6]))) &&
                    (S->nu > 0 || needs_nested_init(S, 0))) {
                    char ind[MAX_NAME];
                    size_t t;
                    for (t = 0; t < ws && t + 1 < sizeof ind; t++) ind[t] = ' ';
                    ind[t] = 0;
                    buf_putc(&b, '\n');
                    put_heap_vpts(&b, S, pv, ind);
                }
            }
        }
        return b.p;
    }

    vk = 0;
    vk = copy_ident(p, var, 0);
    var[vk] = 0;
    if (!vk) return NULL;

    rest = p + vk;

    /* array declaration: "Person ps[2];" — vptrs are written per element */
    {
        const char *q = rest;
        int needs;
        while (*q == ' ' || *q == '\t') q++;
        if (*q == '[') {
            const char *d = q + 1, *cl;
            int atfile;
            needs = (S->nu > 0 || needs_nested_init(S, 0));
            while (*d >= '0' && *d <= '9') d++;
            cl = d;
            if (needs && (cl == q + 1 || *cl != ']' || !decl_end_is_bare(cl + 1)))
                die(0, "struct '%s': only 'Type name[<n>];' arrays are supported", S->name);
            /* at file scope the per-element vptr writes cannot be statements, so
               they go into the per-unit constructor instead */
            atfile = (needs && g_nscope == 0);

            buf_init(&b);
            buf_putn(&b, line, ws);
            buf_puts(&b, "struct ");
            buf_puts(&b, S->cname);
            buf_putc(&b, ' ');
            buf_puts(&b, var);
            buf_puts(&b, q);

            if (needs) {
                Buf *tgt = atfile ? &g_unit_init : &b;
                char ind[MAX_NAME], ind2[MAX_NAME], cnt[64], recv[MAX_NAME + 16];
                size_t k2, dl = (size_t)(cl - q - 1);

                if (g_nvars < MAX_VARS) {
                    snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", var);
                    g_vars[g_nvars].s = (int)(S - g_structs);
                    g_vars[g_nvars].ptr = 0;
                    g_vars[g_nvars].arr = 1;
                    g_vars[g_nvars].iface = 0;
                    g_vars[g_nvars].tr = -1;
                    g_nvars++;
                }
                if (atfile) {
                    g_has_unit_init = 1;
                    snprintf(ind, sizeof ind, "    ");
                } else {
                    buf_putc(&b, '\n');
                    for (k2 = 0; k2 < ws && k2 < sizeof ind - 1; k2++) ind[k2] = line[k2];
                    ind[k2] = 0;
                }
                if (dl >= sizeof cnt) dl = sizeof cnt - 1;
                memcpy(cnt, q + 1, dl);
                cnt[dl] = 0;
                snprintf(ind2, sizeof ind2, "%s        ", ind);
                snprintf(recv, sizeof recv, "%s[__ct_i]", var);

                buf_puts(tgt, ind);  buf_puts(tgt, "{\n");
                buf_puts(tgt, ind);  buf_puts(tgt, "    for (unsigned long __ct_i = 0; __ct_i < ");
                buf_puts(tgt, cnt);
                buf_puts(tgt, "; __ct_i++) {\n");
                put_nested_assignments(tgt, S, recv, ind2, 1, 0);
                buf_puts(tgt, ind);  buf_puts(tgt, "    }\n");
                buf_puts(tgt, ind);  buf_puts(tgt, "}\n");
                if (!atfile && b.n > 0 && b.p[b.n - 1] == '\n') { b.n--; b.p[b.n] = 0; }
            }
            return b.p;
        }
    }

    {
        int vi = new_var();
        snprintf(g_vars[vi].name, MAX_NAME, "%s", var);
        g_vars[vi].s = (int)(S - g_structs);
        g_vars[vi].ptr = 0;
        g_vars[vi].arr = 0;
        g_vars[vi].iface = 0;
        g_vars[vi].tr = -1;
    }

    buf_init(&b);
    buf_putn(&b, line, ws);
    buf_puts(&b, "struct ");
    buf_puts(&b, S->cname);
    buf_putc(&b, ' ');
    buf_puts(&b, var);

    {
        const char *r = rest;
        while (*r == ' ' || *r == '\t') r++;
        if (*r == '=' && S->nu > 0) {
            const char *e = r + 1;
            while (*e == ' ' || *e == '\t') e++;
            if (*e == '{') {
                /* find the matching close brace on this line */
                int depth = 0;
                const char *close = NULL;
                size_t ln = strlen(e);
                size_t z;
                for (z = 0; z < ln; z++) {
                    char cc = e[z];
                    if (cc == '"' || cc == '\'') { z = line_literal_end(e, z, ln) - 1; continue; }
                    if (cc == '{') depth++;
                    else if (cc == '}') { depth--; if (!depth) { close = e + z; break; } }
                }
                if (close) {
                    char *inner = xstrndup(e + 1, (size_t)(close - e - 1));
                    size_t it = trim_right_len(inner, strlen(inner));
                    int first = 1;
                    buf_putn(&b, rest, (size_t)(e - rest) + 1);        /* " = {" */
                    buf_putn(&b, inner, it);
                    if (it) buf_puts(&b, ", ");                        /* positional or designated */
                    else buf_putc(&b, ' ');                            /* empty list */
                    put_own_vptr(&b, S, &first);
                    buf_putc(&b, ' ');
                    buf_puts(&b, close);                              /* "}...;" */
                    free(inner);
                    done = 1;
                }
            }
        } else if (S->nu > 0 && decl_end_is_bare(r)) {
            /* "Person p;" has no initialiser, so give it a designated one */
            int first = 1;
            buf_puts(&b, " = { ");
            put_own_vptr(&b, S, &first);
            buf_puts(&b, " }");
            buf_puts(&b, rest);
            done = 1;
        }
        if (!done) buf_puts(&b, rest);
    }

    if (needs_nested_init(S, 0) || (!done && S->nu > 0)) {
        /* the vptr writes are statements: inside a function they follow the
           declaration; at file scope they go into the per-unit constructor */
        int atfile = (g_nscope == 0);
        Buf *tgt = atfile ? &g_unit_init : &b;
        char ind[MAX_NAME];
        size_t k;
        if (atfile) {
            g_has_unit_init = 1;
            snprintf(ind, sizeof ind, "    ");
        } else {
            for (k = 0; k < ws && k < sizeof ind - 1; k++) ind[k] = line[k];
            ind[k] = 0;
            buf_putc(&b, '\n');
        }
        put_nested_assignments(tgt, S, var, ind, !done, 0);
        if (!atfile && b.n > 0 && b.p[b.n - 1] == '\n') { b.n--; b.p[b.n] = 0; }
    }
    return b.p;
}

/* "delete p;" -> "if (p) free(p);" for a registered pointer object */
static char *try_delete(const char *line)
{
    const char *p = line;
    size_t ind_len;
    char id[MAX_NAME];
    size_t k = 0;
    Buf b;

    while (*p == ' ' || *p == '\t') p++;
    ind_len = (size_t)(p - line);
    if (strncmp(p, "delete", 6) != 0 || is_ident_char((unsigned char)p[6])) return NULL;
    p += 6;
    while (*p == ' ' || *p == '\t') p++;
    k = copy_ident(p, id, 0);
    id[k] = 0;
    if (!k || !decl_end_is_bare(p + k)) return NULL;
    {
        int vi = find_var(id);
        /* Phase 1 relaxation: `delete p;` works for any pointer, not only a
           registered ct-struct pointer (so `delete buf;` on a char * frees it).
           A registered *non*-pointer is left as-is — that is user error. */
        if (vi >= 0 && !g_vars[vi].ptr) return NULL;
    }

    buf_init(&b);
    buf_putn(&b, line, ind_len);
    {
        int vi = find_var(id);
        Struct *S = (vi >= 0 && g_vars[vi].ptr && g_vars[vi].s >= 0)
                    ? &g_structs[g_vars[vi].s] : NULL;
        if (S && S->has_drop) {              /* Drop type: run drop() then free */
            S->drop_used = 1;
            buf_puts(&b, "if (");
            buf_puts(&b, id);
            buf_puts(&b, ") { ");
            buf_puts(&b, S->cname);
            buf_puts(&b, "_Drop_drop(");
            buf_puts(&b, id);
            buf_puts(&b, "); free(");
            buf_puts(&b, id);
            buf_puts(&b, "); }");
            return b.p;
        }
    }
    buf_puts(&b, "if (");
    buf_puts(&b, id);
    buf_puts(&b, ") free(");
    buf_puts(&b, id);
    buf_puts(&b, ");");
    return b.p;
}

static char *transform_line(const char *line)
{
    char *del = try_delete(line);
    char *ret;
    char *decl;
    const char *base;
    Buf out;
    char *res;

    if (del) return del;
    ret = try_return(line);
    if (ret) return ret;
    {
        char *asg = try_iface_assign(line);
        if (asg) return asg;
    }

    decl = try_var_decl(line);
    base = decl ? decl : line;
    buf_init(&out);
    transform_calls(base, &out);
    free(decl);
    res = out.p;
    return res;
}

/* Ordinary function definition or prototype? Qualify the struct types in its
   return type and parameters, and register parameters when a body follows.
   Returns a new line, or NULL when `line` is not a function signature. */
static char *parse_func_sig(const char *line, size_t ls, int *has_body, size_t *body_abs)
{
    size_t n = strlen(line), lpo, he, ns, rt, rp, i, end;
    const char *lp;
    char name[MAX_NAME], tok[MAX_NAME];
    Buf b;
    int isdef = 0, ret_tr = -1, ret_ia = -1, ret_ib = -1, ret_ns = 0;
    char ret_cbase[MAX_NAME];

    *has_body = 0;
    *body_abs = 0;

    lp = strchr(line, '(');
    if (!lp) return NULL;
    lpo = (size_t)(lp - line);
    {
        const char *sc = strchr(line, ';');
        if (sc && (size_t)(sc - line) < lpo) return NULL;      /* ';' before '(' */
    }

    he = trim_right_len(line, lpo);
    ns = he;
    while (ns > 0 && is_ident_char((unsigned char)line[ns - 1])) ns--;
    if (ns == he) return NULL;                                 /* no function name */
    rt = trim_right_len(line, ns);
    if (rt == 0) return NULL;                                  /* no return type */

    /* the return type must look like a C type, and neither the return type nor
       the name may be a statement keyword (`else if (x) {` must not match) */
    {
        size_t k, u;
        for (k = 0; k < rt; k++) {
            char c = line[k];
            if (!(is_ident_char((unsigned char)c) || c == '*' || c == ' ' || c == '\t'))
                return NULL;
        }
        snprintf(name, sizeof name, "%.*s", (int)(he - ns), line + ns);
        if (is_stmt_keyword(name)) return NULL;
        for (k = 0; k < rt; ) {
            u = k;
            while (u < rt && !is_ident_char((unsigned char)line[u])) u++;
            k = u;
            while (k < rt && is_ident_char((unsigned char)line[k])) k++;
            if (k > u) {
                size_t tl = k - u;
                if (tl >= sizeof tok) tl = sizeof tok - 1;
                memcpy(tok, line + u, tl);
                tok[tl] = 0;
                if (is_stmt_keyword(tok)) return NULL;
            }
        }
    }

    rp = line_match_paren(line, lpo, n);
    if (rp == (size_t)-1) return NULL;                         /* ')' on another line */

    {
        size_t k = skip_ws_comments(ls + rp + 1);
        if (k < g_len && g_src[k] == '{') { isdef = 1; *has_body = 1; *body_abs = k; }
        else if (k < g_len && g_src[k] == ';') { isdef = 0; }
        else return NULL;
    }

    /* the return type: qualify a known struct, or expand a trait to its iface */
    {
        char rname[MAX_NAME];
        int rptr = 0;
        analyse_param(line, rt, &ret_ia, &ret_ib, ret_cbase, &ret_ns, rname, &rptr, &ret_tr);
    }

    buf_init(&b);
    emit_qualified_type(&b, line, lpo, ret_ia, ret_ib, ret_cbase, ret_ns, ret_tr >= 0);
    buf_putc(&b, '(');

    {
        int npar = 0, ptrait[MAX_PARAMS];
        for (i = lpo + 1, end = rp; i < end; ) {
            size_t j = i;
            int depth = 0, pia = -1, pib = -1, pns = 0, ptr = 0, sidx, ptrtr = -1;
            char pname[MAX_NAME], pcbase[MAX_NAME];

            while (j < end) {
                char c = line[j];
                if (c == '"' || c == '\'') { j = line_literal_end(line, j, end); continue; }
                if (c == '(' || c == '[' || c == '{') depth++;
                else if (c == ')' || c == ']' || c == '}') depth--;
                else if (c == ',' && depth == 0) break;
                j++;
            }
            sidx = analyse_param(line + i, j - i, &pia, &pib, pcbase, &pns, pname, &ptr, &ptrtr);
            emit_qualified_type(&b, line + i, j - i, pia, pib, pcbase, pns, ptrtr >= 0);

            if (isdef && pname[0] && (sidx >= 0 || ptrtr >= 0)) {
                int vi = new_var();
                snprintf(g_vars[vi].name, MAX_NAME, "%s", pname);
                g_vars[vi].s = (sidx >= 0) ? sidx : -1;
                g_vars[vi].ptr = (sidx >= 0) ? ptr : 0;
                g_vars[vi].arr = 0;
                g_vars[vi].iface = (sidx >= 0) ? 0 : 1;
                g_vars[vi].tr = (sidx >= 0) ? -1 : ptrtr;
            }
            {
                char pbuf[MAX_NAME * 2];
                size_t pl = j - i;
                if (pl >= sizeof pbuf) die(0, "parameter too long (max %d)", (int)sizeof pbuf - 1);
                memcpy(pbuf, line + i, pl);
                pbuf[pl] = 0;
                trim(pbuf);
                if (pbuf[0] && strcmp(pbuf, "void") != 0) {
                    if (npar >= MAX_PARAMS) die(0, "too many parameters (max %d)", MAX_PARAMS);
                    ptrait[npar++] = ptrtr;
                }
            }
            if (j < end) { buf_putc(&b, ','); j++; }
            i = j;
        }
        /* record the signature so call sites can box interface arguments */
        if (g_nfuncs >= MAX_FUNCS) die(0, "too many functions (max %d)", MAX_FUNCS);
        {
            FuncSig *FS = &g_funcs[g_nfuncs++];
            int q;
            snprintf(FS->name, MAX_NAME, "%s", name);
            FS->nparams = npar;
            FS->rettrait = ret_tr;
            for (q = 0; q < npar; q++) FS->ptrait[q] = ptrait[q];
        }
        if (isdef) g_cur_rettr = ret_tr;
    }

    buf_putc(&b, ')');
    buf_puts(&b, line + rp + 1);
    return b.p;
}

/* roll g_nvars back at every closing brace so parameters and locals stay in
   their own scope; string and comment contents are ignored */
static void scope_track(size_t ls, size_t le)
{
    size_t p = ls;
    while (p < le) {
        char c = g_src[p];
        if (c == '"' || c == '\'') {
            size_t j = skip_literal(p);
            p = (j > le) ? le : j;
            continue;
        }
        if (c == '/' && p + 1 < le &&
            (g_src[p + 1] == '/' || g_src[p + 1] == '*')) {
            size_t j = skip_comment(p);
            p = (j > le) ? le : j;
            continue;
        }
        if (c == '{') {
            int save = g_nvars;
            if (g_body_abs && p == g_body_abs) { save = g_body_pre; g_body_abs = 0; }
            if (g_nscope >= MAX_SCOPE) die(p, "too many nested scopes (max %d)", MAX_SCOPE);
            g_scope[g_nscope++] = save;
        } else if (c == '}') {
            if (g_nscope > 0) g_nvars = g_scope[--g_nscope];
        }
        p++;
    }
}

static void emit_raw_line(size_t ls, size_t le)
{
    size_t len = le - ls, t = 0;
    char *line, *sig;
    int pre = g_nvars, has_body = 0;
    size_t body_abs = 0;

    line = xstrndup(g_src + ls, len);
    while (t < len && (line[t] == ' ' || line[t] == '\t')) t++;
    if (t < len && line[t] == '#') {                 /* preprocessor: verbatim */
        fputs(line, g_out);
        free(line);
        return;
    }

    /* a leading `pub` marks an exported declaration (multi-file mode); drop it
       and remember it so the signature is routed to the .h */
    g_line_pub = 0;
    if (t + 3 <= len && strncmp(line + t, "pub", 3) == 0 &&
        !is_ident_char((unsigned char)line[t + 3])) {
        size_t z = t + 3;
        while (z < len && (line[z] == ' ' || line[z] == '\t')) z++;
        g_line_pub = 1;
        memmove(line, line + z, len - z + 1);
        len -= z;
        ls += z;
        t = 0;
    }

    sig = parse_func_sig(line, ls, &has_body, &body_abs);
    if (sig) {
        Buf b;
        if (has_body) { g_body_abs = body_abs; g_body_pre = pre; }
        buf_init(&b);
        g_no_box = 1;                        /* the parameter list is not a call */
        transform_calls(sig, &b);
        g_no_box = 0;
        fputs(b.p, (g_line_pub && g_multi && !has_body) ? g_hout : g_out);
        free(b.p);
        free(sig);
    } else {
        char *out = transform_line(line);
        fputs(out, g_out);
        free(out);
    }
    free(line);
    scope_track(ls, le);
}

/* ------------------------------------------------------------------ main */

static void usage(const char *prog)
{
    fprintf(stderr,
            "usage: %s [compile] <input.ct> [-o <output.c>]\n"
            "       %s build <input.ct>... [-o <outdir>]\n\n"
            "Compiles C-with-traits (.ct) files into plain C.\n"
            "`compile` (default) writes <output.c> and a matching header <output.h>;\n"
            "if -o is omitted the output is <input>.c next to the input.\n"
            "`build` compiles every input in multi-file mode (the .c includes its own\n"
            ".h, `pub` symbols go into the .h) and prints the suggested cc command.\n\n"
            "  -o <file|dir>   compile: write the generated C to <file>\n"
            "                  build: write the outputs into <dir>\n"
            "  --line          force `#line` directives in the generated C\n"
            "  --no-line       suppress `#line` directives\n"
            "  -v, --version   print the compiler version and exit\n"
            "  -h, --help      print this help and exit\n",
            prog, prog);
}

static void default_output(const char *in, char *out, size_t n)
{
    size_t l = strlen(in);
    if (l > 3 && strcmp(in + l - 3, ".ct") == 0) {
        snprintf(out, n, "%.*s.c", (int)(l - 3), in);
    } else {
        snprintf(out, n, "%s.c", in);
    }
}

static void header_path(const char *outc, char *out, size_t n)
{
    size_t l = strlen(outc);
    if (l > 2 && strcmp(outc + l - 2, ".c") == 0) {
        snprintf(out, n, "%.*s.h", (int)(l - 2), outc);
    } else {
        snprintf(out, n, "%s.h", outc);
    }
}

static void write_guard(const char *hpath)
{
    const char *b = strrchr(hpath, '/');
    char guard[MAX_NAME * 2];
    size_t i, j = 0;
    b = b ? b + 1 : hpath;

    for (i = 0; b[i] && b[i] != '.' && j + 1 < sizeof guard; i++)
        guard[j++] = (isalnum((unsigned char)b[i]) ? (char)toupper((unsigned char)b[i]) : '_');
    guard[j] = 0;
    if (!j) snprintf(guard, sizeof guard, "CT_OUTPUT");
    if (guard[0] >= '0' && guard[0] <= '9') {
        memmove(guard + 1, guard, j + 1);
        guard[0] = '_';
    }
    strncat(guard, "_H", sizeof guard - strlen(guard) - 1);

    fprintf(g_hout, "#ifndef %s\n#define %s\n\n", guard, guard);
    if (g_multi)
        fprintf(g_hout, "/* Generated by ctc v%s from %s (multi-file mode:\n"
                        "   exported types; the matching .c includes this header).\n"
                        "   Generated output is not covered by the GPL and may be "
                        "used without restriction (LICENSE.EXCEPTION). */\n\n",
                CTC_VERSION, g_path);
    else
        fprintf(g_hout, "/* Generated by ctc v%s from %s (Phase 0: types only, the\n"
                        "   generated .c is self-contained).\n"
                        "   Generated output is not covered by the GPL and may be "
                        "used without restriction (LICENSE.EXCEPTION). */\n\n",
                CTC_VERSION, g_path);
    snprintf(g_guard, sizeof g_guard, "%s", guard);
}

static char *read_file(const char *path, size_t *out_len)
{
    FILE *f = fopen(path, "rb");
    long sz;
    char *buf;

    if (!f) { fprintf(stderr, "ctc: cannot open '%s'\n", path); exit(1); }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fprintf(stderr, "ctc: cannot read '%s'\n", path); exit(1); }

    buf = xmalloc((size_t)sz + 1);
    if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        fprintf(stderr, "ctc: short read on '%s'\n", path);
        exit(1);
    }
    buf[sz] = 0;
    fclose(f);

    /* normalise CRLF / lone CR */
    {
        size_t i = 0, j = 0;
        while (i < (size_t)sz) {
            if (buf[i] == '\r') {
                if (i + 1 < (size_t)sz && buf[i + 1] == '\n') i++;
                buf[j++] = '\n';
                i++;
            } else {
                buf[j++] = buf[i++];
            }
        }
        buf[j] = 0;
        *out_len = j;
    }
    return buf;
}

/* Scan [start,end): expand traits/structs/impls and namespaces, pass the rest
   through. Namespace braces are consumed here (never emitted) so that the
   enclosed constructs are mangled with the namespace prefix. */
static void compile_range(size_t start, size_t end)
{
    size_t pos = start;

    while (pos < end) {
        size_t ls = pos, q, le;

        q = ls;
        while (q < end && (g_src[q] == ' ' || g_src[q] == '\t')) q++;

        /* An optional `pub` marks a trait/struct as exported (multi-file mode);
           `pub` on a function line is stripped later in emit_raw_line. */
        g_ctor_pub = 0;
        if (word_at(q, "pub")) {
            size_t t = skip_ws_comments(q + 3);
            if (word_at(t, "trait") || word_at(t, "struct")) { g_ctor_pub = 1; q = t; }
        }

        /* `import A::B;` — a compilation-unit declaration, resolved by the
           driver (`ct build`); here it is simply consumed (never emitted). */
        if (word_at(q, "import")) {
            size_t t = skip_ws_comments(q + 6);
            int ok = 1;
            size_t nseg = 0;
            for (;;) {
                char seg[MAX_NAME];
                t = read_ident(t, seg, sizeof seg);
                if (!seg[0]) { ok = 0; break; }
                nseg++;
                t = skip_ws_comments(t);
                if (t + 1 < g_len && g_src[t] == ':' && g_src[t + 1] == ':') {
                    t = skip_ws_comments(t + 2);
                    continue;
                }
                break;
            }
            if (ok && nseg && t < g_len && g_src[t] == ';') {
                size_t e = t;
                while (e < end && g_src[e] != '\n') e++;
                pos = (e < end) ? e + 1 : end;
                continue;
            }
        }

        /* A keyword only starts a construct when its full header follows: plain C
           may legally use 'trait' / 'impl' as identifiers (e.g. 'impl[n] = 0;'). */
        if (word_at(q, "trait")) {
            char nm[MAX_NAME];
            size_t t = read_ident(skip_ws_comments(q + 5), nm, sizeof nm);
            t = skip_ws_comments(t);
            if (nm[0] && t < g_len && g_src[t] == '{') { pos = parse_trait(q); continue; }
        }
        if (word_at(q, "impl")) {
            char nm[MAX_NAME];
            size_t t = read_ident(skip_ws_comments(q + 4), nm, sizeof nm);
            if (nm[0] && word_at(skip_ws_comments(t), "for")) { pos = parse_impl(q); continue; }
        }
        if (word_at(q, "struct")) {
            size_t t = skip_ws_comments(q + 6);
            char nm[MAX_NAME];
            t = read_ident(t, nm, sizeof nm);
            if (nm[0]) {
                t = skip_ws_comments(t);
                if (t < g_len && g_src[t] == '{') { pos = parse_struct(q); continue; }
            }
        }
        if (word_at(q, "namespace")) {
            /* namespace A::B::C { ... } -> mangling prefix "A_B_C_". Only a
               complete header is a construct; anything else passes through, so
               prose in a comment or plain C that happens to start a line with
               the word 'namespace' is not mistaken for one. */
            size_t t = skip_ws_comments(q + 9);
            char pre[MAX_NAME], seg[MAX_NAME], saved[MAX_NAME], open[MAX_NAME * 2];
            size_t pl = 0, close = 0;
            int nseg = 0, ok = 1;

            pre[0] = 0;
            for (;;) {
                size_t sl;
                t = read_ident(t, seg, sizeof seg);
                if (!seg[0]) {
                    if (nseg == 0) { ok = 0; break; }        /* not a namespace header */
                    die(t, "expected a name after '::' in namespace");
                }
                sl = strlen(seg);
                if (nseg && pl + sl + 2 >= sizeof pre) die(t, "namespace path too long");
                if (nseg) pre[pl++] = '_';
                memcpy(pre + pl, seg, sl);
                pl += sl;
                pre[pl] = 0;
                nseg++;
                t = skip_ws_comments(t);
                if (t + 1 < g_len && g_src[t] == ':' && g_src[t + 1] == ':') {
                    t = skip_ws_comments(t + 2);
                    continue;
                }
                break;
            }

            if (ok && t < g_len && g_src[t] == '{') {
                close = match_delim(t, '{', '}');

                snprintf(saved, sizeof saved, "%s", g_ns);
                if (snprintf(open, sizeof open, "%s%s_", g_ns, pre) >= (int)sizeof open)
                    die(t, "namespace path too long");
                snprintf(g_ns, sizeof g_ns, "%s", open);

                compile_range(t + 1, close);

                snprintf(g_ns, sizeof g_ns, "%s", saved);
                pos = close + 1;
                continue;
            }
        }

        le = ls;
        while (le < end && g_src[le] != '\n') le++;
        line_at(g_out, line_of(ls));
        emit_raw_line(ls, le);
        if (le < end) { fputc('\n', g_out); le++; }
        pos = le;
    }
}

/* A deleted Drop type pulls in the drops of its Drop value fields: mark them so
   their bodies are emitted too (a default body calls them). A user body is taken
   as-is and marks nothing, so it must not reference generated drop functions. */
static void mark_drop_closure(void)
{
    int changed = 1;
    while (changed) {
        int i, h;
        changed = 0;
        for (i = 0; i < g_nown_drop; i++) {
            Struct *S = &g_structs[g_own_drop[i]];
            if (!S->drop_used || S->has_user_drop) continue;
            for (h = 0; h < S->nf; h++) {
                Struct *F = &g_structs[S->ftype[h]];
                if (F->has_drop && !F->drop_used) { F->drop_used = 1; changed = 1; }
            }
        }
    }
}

/* Does [bstart, bstart+blen) mention `self` as a word? A user drop body need not
   use it, and an unused _self/self would warn under -Wall -Wextra. */
static int body_uses_self(size_t bstart, size_t blen)
{
    size_t i = bstart, end = bstart + blen;
    while (i < end) {
        if (g_src[i] == '"' || g_src[i] == '\'') { i = skip_literal(i); continue; }
        if (g_src[i] == '/' && i + 1 < end && (g_src[i + 1] == '/' || g_src[i + 1] == '*')) {
            i = skip_comment(i);
            continue;
        }
        if (is_ident_char((unsigned char)g_src[i]) && !isdigit((unsigned char)g_src[i])) {
            size_t j = i;
            while (j < end && is_ident_char((unsigned char)g_src[j])) j++;
            if (j - i == 4 && memcmp(g_src + i, "self", 4) == 0) return 1;
            i = j;
            continue;
        }
        i++;
    }
    return 0;
}

/* The drop prototypes go before the body (a delete calls them); the definition
   goes after it (so the structs are complete). Both are emitted only for types a
   delete actually reaches, so an unused drop never appears (-Wunused-function). */

static void emit_drop_prototypes(FILE *f)
{
    int i, any = 0;
    mark_drop_closure();
    for (i = 0; i < g_nown_drop; i++) {
        Struct *S = &g_structs[g_own_drop[i]];
        if (!S->drop_used) continue;
        line_at(f, S->def_line);
        fprintf(f, "static void %s_Drop_drop(void *self);\n", S->cname);
        any = 1;
    }
    if (any) fputc('\n', f);
    line_break();
}

static void emit_drop_bodies(FILE *f)
{
    int i;
    for (i = 0; i < g_nown_drop; i++) {
        Struct *S = &g_structs[g_own_drop[i]];
        int h, need_self = 0;
        if (!S->drop_used) continue;
        if (S->has_user_drop) {
            need_self = body_uses_self(S->drop_bstart, S->drop_blen);
        } else {
            for (h = 0; h < S->nf; h++)
                if (g_structs[S->ftype[h]].has_drop) { need_self = 1; break; }
        }
        line_at(f, S->def_line);
        fprintf(f, "static void %s_Drop_drop(void *self) {\n", S->cname);
        if (need_self)
            fprintf(f, "    struct %s *_self = (struct %s *)self;\n", S->cname, S->cname);
        else
            fprintf(f, "    (void)self;\n");
        if (S->has_user_drop) {
            emit_body(f, S->drop_bstart, S->drop_blen, S);
        } else {
            for (h = 0; h < S->nf; h++) {
                const Struct *F = &g_structs[S->ftype[h]];
                if (!F->has_drop) continue;
                fprintf(f, "    %s_Drop_drop(&_self->%s);\n", F->cname, S->fname[h]);
            }
        }
        fprintf(f, "}\n\n");
        line_break();
    }
}

/* Compile one input to `outc` and a matching header. When `multi` is set the
   generated .c includes its own header and `pub` symbols are routed into the
   header (multi-file mode, `ct build`). Returns 0 on success. */
static int compile_file(const char *in, const char *outc, int multi)
{
    char hbuf[MAX_NAME * 4];
    const char *base;
    FILE *body;

    g_multi = multi;
    g_ns[0] = 0;
    g_nvars = 0;
    g_nscope = 0;
    g_cur_rettr = -1;
    g_body_abs = 0;
    g_body_pre = 0;
    g_no_box = 0;
    g_ctor_pub = 0;
    g_line_pub = 0;
    g_nown_drop = 0;
    /* in multi-file mode traits/structs/signatures accumulate across units so a
       unit can reference an imported unit's types */
    if (!multi) { g_ntraits = 0; g_nstructs = 0; g_nfuncs = 0; }

    header_path(outc, hbuf, sizeof hbuf);
    g_path = in;
    g_src = read_file(in, &g_len);

    /* #line is on by default in multi-file mode (D4 = A); --line/--no-line win.
       Single-file output is left untouched so it stays byte-identical to Phase 0,
       which keeps every existing golden valid. */
    g_emit_line = (g_line_force >= 0) ? g_line_force : multi;
    g_lc_off = 0;
    g_lc_ln = 1;
    g_line_next = -1;

    g_out = fopen(outc, "w");
    if (!g_out) { fprintf(stderr, "ctc: cannot write '%s'\n", outc); return 1; }
    g_hout = fopen(hbuf, "w");
    if (!g_hout) { fprintf(stderr, "ctc: cannot write '%s'\n", hbuf); fclose(g_out); return 1; }

    write_guard(hbuf);

    /* provenance banner: the generated C is a build product, not a source file */
    fprintf(g_out, "/* Generated by ctc v%s from %s -- do not edit; "
                   "change the .ct and re-run ctc. */\n"
                   "/* Generated output is not covered by the GPL and may be "
                   "used without restriction (LICENSE.EXCEPTION). */\n",
            CTC_VERSION, g_path);

    if (multi) {
        int i;
        base = strrchr(hbuf, '/');
        base = base ? base + 1 : hbuf;
        fprintf(g_out, "#include \"%s\"\n", base);
        for (i = 0; i < g_nimp_h; i++)
            fprintf(g_out, "#include \"%s\"\n", g_imp_h[i]);
        fputc('\n', g_out);
    }

    /* Buffer the body so the lazily-generated drop functions can be emitted
       before it: a drop function must be defined before the delete that calls it. */
    body = tmpfile();
    if (!body) {
        fprintf(stderr, "ctc: cannot create a temporary file\n");
        fclose(g_out);
        fclose(g_hout);
        return 1;
    }
    buf_init(&g_unit_init);
    g_has_unit_init = 0;
    {
        FILE *real = g_out;
        g_out = body;
        compile_range(0, g_len);
        g_out = real;
        line_break();
        emit_drop_prototypes(real);
        rewind(body);
        for (;;) {
            char chunk[8192];
            size_t got = fread(chunk, 1, sizeof chunk, body);
            if (!got) break;
            fwrite(chunk, 1, got, g_out);
        }
        emit_drop_bodies(real);
        /* file-scope objects/arrays: their vptr writes were collected while
           scanning and are emitted here, after the types and vtables they
           reference, as a constructor that runs before main (D5 = A). */
        if (g_has_unit_init) {
            fprintf(g_out,
                    "static void __ct_init(void) __attribute__((constructor));\n"
                    "static void __ct_init(void) {\n%s}\n",
                    g_unit_init.p);
        }
        free(g_unit_init.p);
    }
    fclose(body);

    fprintf(g_hout, "\n#endif /* %s */\n", g_guard);

    fclose(g_out);
    fclose(g_hout);
    return 0;
}

/* output path for `in` in build mode: `<outdir>/<base>.c`, or beside the input */
static int build_output(const char *in, const char *outdir, char *out, size_t cap)
{
    char base[MAX_NAME];
    const char *b = strrchr(in, '/');
    size_t l;

    b = b ? b + 1 : in;
    snprintf(base, sizeof base, "%s", b);
    l = strlen(base);
    if (l > 3 && strcmp(base + l - 3, ".ct") == 0) base[l - 3] = 0;

    if (outdir)
        return snprintf(out, cap, "%s/%s.c", outdir, base) >= (int)cap ? -1 : 0;
    return snprintf(out, cap, "%.*s%s.c", (int)(b - in), in, base) >= (int)cap ? -1 : 0;
}

/* does the file exist? (used to probe import candidates) */
static int file_exists(const char *p)
{
    FILE *f = fopen(p, "rb");
    if (!f) return 0;
    fclose(f);
    return 1;
}

/* Collect every `import A::B;` module in `path`, each as "A/B". Returns the count. */
static int collect_imports(const char *path, char mods[][MAX_NAME], int max)
{
    size_t len = 0, pos = 0;
    char *src = read_file(path, &len);
    int n = 0;

    while (pos < len && n < max) {
        size_t ls = pos, q = ls, e;
        while (q < len && (src[q] == ' ' || src[q] == '\t')) q++;
        if (q + 6 <= len && memcmp(src + q, "import", 6) == 0 &&
            (q + 6 == len || !is_ident_char((unsigned char)src[q + 6]))) {
            size_t t = q + 6, k = 0;
            char mod[MAX_NAME];
            int ok = 1;
            while (t < len && (src[t] == ' ' || src[t] == '\t')) t++;
            mod[0] = 0;
            for (;;) {
                size_t s = t;
                while (t < len && is_ident_char((unsigned char)src[t])) t++;
                if (t == s) { ok = 0; break; }
                if (k && k + 1 < sizeof mod) mod[k++] = '/';
                if (k + (t - s) + 1 >= sizeof mod) { ok = 0; break; }
                memcpy(mod + k, src + s, t - s);
                k += t - s;
                mod[k] = 0;
                while (t < len && (src[t] == ' ' || src[t] == '\t')) t++;
                if (t + 1 < len && src[t] == ':' && src[t + 1] == ':') {
                    t += 2;
                    while (t < len && (src[t] == ' ' || src[t] == '\t')) t++;
                    continue;
                }
                break;
            }
            if (ok && k && t < len && src[t] == ';') {
                snprintf(mods[n], MAX_NAME, "%s", mod);
                n++;
            }
        }
        e = ls;
        while (e < len && src[e] != '\n') e++;
        pos = (e < len) ? e + 1 : len;
    }
    free(src);
    return n;
}

/* Resolve `mod` ("A/B") against the importing file's directory -> `<dir>/A/B.ct`
   or `<dir>/A/B.h.ct`. Returns 0 on success. */
static int resolve_import(const char *importer, const char *mod, char *out, size_t cap)
{
    char dir[MAX_NAME * 2];
    const char *slash = strrchr(importer, '/');

    if (slash) {
        size_t n = (size_t)(slash - importer);
        if (n >= sizeof dir) n = sizeof dir - 1;
        memcpy(dir, importer, n);
        dir[n] = 0;
    } else {
        snprintf(dir, sizeof dir, ".");
    }

    if (snprintf(out, cap, "%s/%s.ct", dir, mod) >= (int)cap) return -1;
    if (file_exists(out)) return 0;
    if (snprintf(out, cap, "%s/%s.h.ct", dir, mod) >= (int)cap) return -1;
    if (file_exists(out)) return 0;
    return -1;
}

/* ------------------------------------------------------------------ units */

static char g_unit_path[MAX_UNITS][MAX_NAME * 4];
static char g_unit_out[MAX_UNITS][MAX_NAME * 4];
static char g_unit_imp[MAX_UNITS][MAX_IMPORTS][MAX_NAME];
static int  g_unit_nimp[MAX_UNITS];
static int  g_unit_n = 0;
static int  g_order[MAX_UNITS];
static int  g_order_n = 0;

static int unit_find(const char *path)
{
    int i;
    for (i = 0; i < g_unit_n; i++)
        if (strcmp(g_unit_path[i], path) == 0) return i;
    return -1;
}

/* Add `path` and its imports (post-order: dependencies land in g_order first). */
static int unit_visit(const char *path)
{
    int idx = unit_find(path), k;
    char mods[MAX_IMPORTS][MAX_NAME];
    int n;

    if (idx >= 0) return idx;                      /* already scheduled */

    if (g_unit_n >= MAX_UNITS) {
        fprintf(stderr, "ctc: too many units (max %d)\n", MAX_UNITS);
        return -1;
    }
    idx = g_unit_n++;
    snprintf(g_unit_path[idx], sizeof g_unit_path[0], "%s", path);
    g_unit_nimp[idx] = 0;

    n = collect_imports(path, mods, MAX_IMPORTS);
    for (k = 0; k < n; k++) {
        char dep[MAX_NAME * 4];
        const char *seg;
        char hname[MAX_NAME];
        if (resolve_import(path, mods[k], dep, sizeof dep) != 0) {
            fprintf(stderr, "ctc: cannot resolve import '%s' from '%s'\n", mods[k], path);
            return -1;
        }
        if (unit_visit(dep) < 0) return -1;
        seg = strrchr(mods[k], '/');
        seg = seg ? seg + 1 : mods[k];
        snprintf(hname, sizeof hname, "%s.h", seg);
        if (g_unit_nimp[idx] < MAX_IMPORTS)
            snprintf(g_unit_imp[idx][g_unit_nimp[idx]++], MAX_NAME, "%s", hname);
    }

    g_order[g_order_n++] = idx;
    return idx;
}

/* `ct build`: resolve imports, compile every unit in dependency order in
   multi-file mode, and print the suggested cc command. ctc never invokes a C
   compiler itself (it stays dependency-free). */
static int build_main(int argc, char **argv, const char *prog)
{
    const char *in[MAX_BUILD];
    const char *outdir = NULL;
    int n = 0, i, o;
    Buf cc;

    for (i = 0; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) { usage(prog); return 0; }
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            printf("ctc v%s\n", CTC_VERSION);
            return 0;
        }
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "ctc: -o needs an argument\n"); return 1; }
            outdir = argv[++i];
            continue;
        }
        if (strcmp(argv[i], "--line") == 0) { g_line_force = 1; continue; }
        if (strcmp(argv[i], "--no-line") == 0) { g_line_force = 0; continue; }
        if (argv[i][0] == '-' && argv[i][1]) {
            fprintf(stderr, "ctc: unknown option '%s'\n", argv[i]);
            usage(prog);
            return 1;
        }
        if (n >= MAX_BUILD) {
            fprintf(stderr, "ctc: too many inputs (max %d)\n", MAX_BUILD);
            return 1;
        }
        in[n++] = argv[i];
    }

    if (!n) { usage(prog); return 1; }

    for (i = 0; i < n; i++)
        if (unit_visit(in[i]) < 0) return 1;

    for (o = 0; o < g_order_n; o++) {
        int u = g_order[o];
        int k;
        if (build_output(g_unit_path[u], outdir, g_unit_out[u], sizeof g_unit_out[0]) != 0) {
            fprintf(stderr, "ctc: output path too long for '%s'\n", g_unit_path[u]);
            return 1;
        }
        g_nimp_h = g_unit_nimp[u];
        for (k = 0; k < g_nimp_h; k++)
            snprintf(g_imp_h[k], MAX_NAME, "%s", g_unit_imp[u][k]);
        if (compile_file(g_unit_path[u], g_unit_out[u], 1) != 0) return 1;
    }

    buf_init(&cc);
    buf_puts(&cc, "cc");
    for (o = 0; o < g_order_n; o++) { buf_putc(&cc, ' '); buf_puts(&cc, g_unit_out[g_order[o]]); }
    buf_puts(&cc, " -o a.out");
    printf("%s\n", cc.p);
    free(cc.p);
    return 0;
}

/* Compile one .ct file to .c + .h (single-file mode). argv[0..argc-1] are the
   compile arguments (argv[0] is not the program name); prog is for diagnostics. */
static int compile_main(int argc, char **argv, const char *prog)
{
    const char *in = NULL, *outc = NULL;
    char outbuf[MAX_NAME * 4];
    int i;

    for (i = 0; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(prog);
            return 0;
        }
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            printf("ctc v%s\n", CTC_VERSION);
            return 0;
        }
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "ctc: -o needs an argument\n"); return 1; }
            outc = argv[++i];
            continue;
        }
        if (strcmp(argv[i], "--line") == 0) { g_line_force = 1; continue; }
        if (strcmp(argv[i], "--no-line") == 0) { g_line_force = 0; continue; }
        if (argv[i][0] == '-' && argv[i][1]) {
            fprintf(stderr, "ctc: unknown option '%s'\n", argv[i]);
            usage(prog);
            return 1;
        }
        in = argv[i];
    }

    if (!in) { usage(prog); return 1; }
    if (!outc) { default_output(in, outbuf, sizeof outbuf); outc = outbuf; }
    return compile_file(in, outc, 0);
}

int main(int argc, char **argv)
{
    int first = 1;

    /* Single-entry `ct` with `ctc` kept as a compatibility alias. `compile` is
       the default subcommand (`ct X` == `ct compile X`); `build` compiles
       several units in multi-file mode. */
    if (first < argc && strcmp(argv[first], "build") == 0)
        return build_main(argc - first - 1, argv + first + 1, argv[0]);

    if (first < argc && strcmp(argv[first], "compile") == 0)
        first++;

    return compile_main(argc - first, argv + first, argv[0]);
}
