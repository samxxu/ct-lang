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

#define CTC_VERSION "0.9.0"

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
    char   cname[MAX_NAME];            /* the spelling used in the generated C */
    Method m[MAX_METHOD];
    int    nm;
} Trait;

typedef struct {
    char name[MAX_NAME];
    char cname[MAX_NAME];              /* the spelling used in the generated C */
    char use_t[MAX_TRAITS][MAX_NAME];  /* used trait short names (vptr field, messages) */
    int  use_i[MAX_TRAITS];            /* their index into g_traits (for the C name) */
    int  nu;
    char fname[MAX_FIELDS][MAX_NAME];  /* value fields whose type is a known struct */
    int  ftype[MAX_FIELDS];            /* ... and their index into g_structs */
    int  nf;
    /* pointer fields live in their own table: nested construction must never
       treat a borrowed pointer as an owned nested value */
    char pfname[MAX_FIELDS][MAX_NAME];
    int  pftype[MAX_FIELDS];
    int  npf;
    /* interface fields (a trait used as a field type, `T x;` / `struct T *x;`)
       live in their own tables: they hold a fat pointer, so a call on them is
       dispatched through the field's own vt, not the enclosing struct's vptr */
    char ifname[MAX_FIELDS][MAX_NAME];
    int  iftype[MAX_FIELDS];           /* ... and their index into g_traits */
    int  nif;
    char pifname[MAX_FIELDS][MAX_NAME];
    int  piftype[MAX_FIELDS];
    int  npif;
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
    int  retstruct;                    /* >=0 when the return type is a known struct */
    int  retptr;                       /* 1 when that struct is returned through a pointer */
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

/* dynamic string buffer */
typedef struct { char *p; size_t n, cap; } Buf;

/* File-scope ct objects/arrays (Phase 1.6): their vptr writes are statements,
   which C cannot hold at file scope. They are accumulated here and emitted in a
   per-unit constructor (`__attribute__((constructor))`, decision D5 = A) that
   runs before main. `static`, so each translation unit has its own. */
static Buf g_unit_init;
static int g_has_unit_init = 0;

static size_t g_line_off = 0;        /* g_src offset where the line being rewritten starts */

/* Phase 1.9b rvalue receivers: `f().m()` needs its receiver evaluated once, in
   order. The temp declaration is accumulated here and emitted just before the
   rewritten line (see emit_hoisted); `g_ntmp` keeps the names unique. */
static Buf    g_hoist;
static int    g_ntmp = 0;

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

/* ------------------------------------------------ tables / lookups */

static Trait *find_trait(const char *name)
{
    int i;

    for (i = 0; i < g_ntraits; i++)
        if (strcmp(g_traits[i].cname, name) == 0) return &g_traits[i];
    return NULL;
}

static Struct *find_struct(const char *name)
{
    int i;

    for (i = 0; i < g_nstructs; i++)
        if (strcmp(g_structs[i].cname, name) == 0) return &g_structs[i];
    return NULL;
}

static int struct_uses(const Struct *s, const char *trait)
{
    int i;
    for (i = 0; i < s->nu; i++)
        if (strcmp(s->use_t[i], trait) == 0) return 1;
    return 0;
}

/* struct index of the field named `name`, or -1; *isptr tells whether the field
   is a pointer, so the following hop must use '->' */
static int find_field_ex(const Struct *s, const char *name, int *isptr)
{
    int i;
    for (i = 0; i < s->nf; i++)
        if (strcmp(s->fname[i], name) == 0) { *isptr = 0; return s->ftype[i]; }
    for (i = 0; i < s->npf; i++)
        if (strcmp(s->pfname[i], name) == 0) { *isptr = 1; return s->pftype[i]; }
    return -1;
}

/* trait index of the interface field named `name`, or -1; *isptr tells whether
   the field is a `struct T *` pointer, so the following hop must use '->' */
static int find_iface_field(const Struct *s, const char *name, int *isptr)
{
    int i;
    for (i = 0; i < s->nif; i++)
        if (strcmp(s->ifname[i], name) == 0) { *isptr = 0; return s->iftype[i]; }
    for (i = 0; i < s->npif; i++)
        if (strcmp(s->pifname[i], name) == 0) { *isptr = 1; return s->piftype[i]; }
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
    int i;
    if (g_nvars >= MAX_VARS) die(0, "too many variables (max %d)", MAX_VARS);
    i = g_nvars++;
    return i;
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
   the base type name and its spelling in the generated C (`cbase`), whether the
   "struct " keyword must be inserted (`*need_struct`), the declared name ("" when
   unnamed) and whether it is a pointer. Arrays are expanded but carry no name. */
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
    if (!last_ident(s, lim, &a, &b)) return -1;

    {
        size_t lsx = b;
        char last[MAX_NAME];
        while (lsx > a && is_ident_char((unsigned char)s[lsx - 1])) lsx--;
        snprintf(last, sizeof last, "%.*s", (int)(b - lsx), s + lsx);
        if (!is_type_keyword(last) && !find_struct(last) && !find_trait(last)) {
            snprintf(name, MAX_NAME, "%s", last);
            snprintf(type, sizeof type, "%.*s", (int)a, s);
        } else {
            snprintf(type, sizeof type, "%.*s", (int)n, s);   /* the type itself */
        }
    }
    if (lim < n) name[0] = 0;                                 /* array: no object to bind */

    /* the base type name: drop trailing '*'/space, then take the last name */
    tn = strlen(type);
    while (tn > 0 && (type[tn - 1] == '*' || isspace((unsigned char)type[tn - 1]))) tn--;
    if (tn == 0 || !last_ident(type, tn, &ea, &eb)) return -1;

    {
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

/* If the line just rewritten hoisted a temp receiver (Phase 1.9b), write that
   declaration first: it must run before the rewritten line. */
static void emit_hoisted(void)
{
    if (g_hoist.n == 0) return;
    fputs(g_hoist.p, g_out);
    fputc('\n', g_out);
}

static void emit_trait_def(FILE *f, const Trait *T)
{
    int i, k;
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
}

static void emit_struct_def(FILE *f, const Struct *S, const char *body)
{
    int i;
    size_t blen = strlen(body);

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
}

/* does any declared trait have a method named `m`? */
static int is_any_trait_method(const char *m)
{
    int i;
    for (i = 0; i < g_ntraits; i++)
        if (trait_has_method(&g_traits[i], m)) return 1;
    return 0;
}

/* Does the body contain a call that will become a vtable dispatch? Any `.m(` /
   `->m(` whose `m` names a declared trait method counts. When it does, the
   impl's vtable variable must be declared before the method bodies, because
   the bodies now reference it (a tentative definition, defined again below).
   Another struct's vtable is visible as long as its impl comes earlier, which
   is the ordinary C definition-before-use rule. */
static int body_needs_vtable(size_t bstart, size_t blen)
{
    size_t i = bstart, end = bstart + blen;

    while (i < end) {
        char c = g_src[i];
        if (c == '"' || c == '\'') {
            size_t j = skip_literal(i);
            i = (j > end) ? end : j;
            continue;
        }
        if (c == '/' && i + 1 < end &&
            (g_src[i + 1] == '/' || g_src[i + 1] == '*')) {
            size_t j = skip_comment(i);
            i = (j > end) ? end : j;
            continue;
        }
        if (c == '.' || c == '-') {
            size_t ms = (c == '.') ? i + 1 : i + 2;
            size_t e, ml;
            char mem[MAX_NAME];
            if (c == '-') {
                if (i + 1 >= end || g_src[i + 1] != '>') { i++; continue; }
            }
            e = ms;
            while (e < end && is_ident_char((unsigned char)g_src[e])) e++;
            ml = e - ms;
            if (ml > 0 && ml < MAX_NAME && e < end && g_src[e] == '(') {
                memcpy(mem, g_src + ms, ml);
                mem[ml] = 0;
                if (is_any_trait_method(mem)) return 1;
            }
            i = (e > i) ? e : i + 1;
            continue;
        }
        i++;
    }
    return 0;
}

/* Entry points of the shared rewriting pipeline, defined further down but used
   by emit_body (impl method bodies go through the very same passes). */
static size_t line_literal_end(const char *s, size_t i, size_t n);
static char *transform_line(const char *line);
static void scope_track(size_t ls, size_t le);
static void emit_hoisted(void);

/* `self` -> `_self` for one line. Method dispatch (`self->m(...)`,
   `self->field->m(...)`, local and parameter receivers) is no longer special
   here: the body runs through transform_calls first, with `self` registered as
   a pointer to the current struct, so every call dispatches exactly as it
   would at file scope. This pass only renames the identifier. Strings and
   comments are copied verbatim. */
static void replace_self(const char *s, size_t n, Buf *out)
{
    size_t i = 0;
    while (i < n) {
        char c = s[i];
        if (c == '"' || c == '\'') {
            size_t j = line_literal_end(s, i, n);
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        if (c == '/' && i + 1 < n && (s[i + 1] == '/' || s[i + 1] == '*')) {
            size_t j;
            if (s[i + 1] == '/') {
                j = n;
            } else {
                j = i + 2;
                while (j + 1 < n && !(s[j] == '*' && s[j + 1] == '/')) j++;
                j = (j + 1 < n) ? j + 2 : n;
            }
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        if (is_ident_char((unsigned char)c) && !isdigit((unsigned char)c)) {
            size_t j = i;
            while (j < n && is_ident_char((unsigned char)s[j])) j++;
            /* a member named `self` (e.g. `g.self`, the iface dispatcher's
               field) is not the implicit receiver and must not be renamed */
            if (j - i == 4 && memcmp(s + i, "self", 4) == 0 &&
                !(i > 0 && (s[i - 1] == '.' ||
                            (s[i - 1] == '>' && i > 1 && s[i - 2] == '-'))))
                buf_puts(out, "_self");
            else
                buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        buf_putc(out, c);
        i++;
    }
}

/* Register the impl method's parameters so that calls on them dispatch inside
   the body, exactly like a top-level function's parameters do. Only parameters
   declared with a known struct type (by value or by pointer) are registered. */
static void register_body_params(const char *params)
{
    const char *p = params;
    while (p && *p) {
        const char *c = strchr(p, ',');
        const char *end = c ? c : p + strlen(p);
        char piece[MAX_PARAM];
        char name[MAX_NAME];
        const char *q;
        Struct *ST;
        size_t plen = (size_t)(end - p), nk;

        if (plen >= sizeof piece) plen = sizeof piece - 1;
        memcpy(piece, p, plen);
        piece[plen] = 0;
        trim(piece);

        q = piece;
        while (*q == ' ' || *q == '\t') q++;
        if (strncmp(q, "struct", 6) == 0 && !is_ident_char((unsigned char)q[6])) {
            q += 6;
            while (*q == ' ' || *q == '\t') q++;
        }
        nk = copy_ident(q, name, 0);
        name[nk] = 0;
        q += nk;
        ST = nk ? find_struct(name) : NULL;
        if (ST) {
            int isptr = 0;
            while (*q == ' ' || *q == '\t') q++;
            if (*q == '*') {
                isptr = 1;
                while (*q == '*' || *q == ' ' || *q == '\t') q++;
            }
            if (is_ident_char((unsigned char)*q) && !isdigit((unsigned char)*q)) {
                char pv[MAX_NAME];
                int pk = copy_ident(q, pv, 0);
                pv[pk] = 0;
                if (pk) {
                    int vi = new_var();
                    snprintf(g_vars[vi].name, MAX_NAME, "%s", pv);
                    g_vars[vi].s = (int)(ST - g_structs);
                    g_vars[vi].ptr = isptr;
                    g_vars[vi].arr = 0;
                    g_vars[vi].iface = 0;
                    g_vars[vi].tr = -1;
                }
            }
        }
        p = c ? c + 1 : end;
    }
}

/* Emit an impl method body. The body runs through the same rewriting pipeline
   as top-level code: `self` is registered as a pointer to `S` and the method's
   parameters are registered, so local receivers, parameter receivers, field
   chains and rvalue receivers all dispatch. Only the identifier naming differs:
   calls are rewritten first (`self->m()` becomes `self->__<trait>_vptr->m(self)`),
   then `self` is renamed to `_self`. */
static void emit_body(FILE *f, size_t bstart, size_t blen, const Struct *S, const char *params)
{
    size_t i, j, n = blen;
    int minind = 1 << 30;
    size_t *ls, *le;
    int nlines = 0, first = -1, last = -1, k;
    int saved_nvars = g_nvars, saved_nscope = g_nscope;
    /* the body reuses the shared var table from index 0, so snapshot the
       enclosing file-scope entries and put them back on the way out; restoring
       only the count would leave the outer registrations clobbered */
    Var *saved_vars = xmalloc(sizeof(Var) * (saved_nvars ? (size_t)saved_nvars : 1));
    memcpy(saved_vars, g_vars, sizeof(Var) * (size_t)saved_nvars);
    size_t saved_body_abs = g_body_abs;
    int saved_body_pre = g_body_pre;
    size_t saved_line_off = g_line_off;
    int vi;

    ls = xmalloc(sizeof(size_t) * (n + 2));
    le = xmalloc(sizeof(size_t) * (n + 2));

    i = 0;
    while (i < n) {
        j = i;
        while (j < n && g_src[bstart + j] != '\n') j++;
        ls[nlines] = bstart + i;
        le[nlines] = bstart + j;
        nlines++;
        i = j + 1;
        if (j >= n) break;
    }

    for (k = 0; k < nlines; k++) {
        size_t t = ls[k];
        while (t < le[k] && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
        if (t < le[k]) {
            int ind = (int)(t - ls[k]);
            if (ind < minind) minind = ind;
            if (first < 0) first = k;
            last = k;
        }
    }

    if (first < 0) { free(ls); free(le); return; }
    if (minind == 1 << 30) minind = 0;

    /* the body sees only its own locals, never the surrounding file scope */
    g_nvars = 0;
    g_nscope = 0;
    g_body_abs = 0;
    vi = new_var();
    snprintf(g_vars[vi].name, MAX_NAME, "self");
    g_vars[vi].s = (int)(S - g_structs);
    g_vars[vi].ptr = 1;
    g_vars[vi].arr = 0;
    g_vars[vi].iface = 0;
    g_vars[vi].tr = -1;
    register_body_params(params);
    if (!g_hoist.cap) buf_init(&g_hoist);

    for (k = first; k <= last; k++) {
        size_t t = ls[k], content;
        char *line, *out;
        Buf sb;

        g_line_off = ls[k];
        g_hoist.n = 0;
        g_hoist.p[0] = 0;

        while (t < le[k] && (g_src[t] == ' ' || g_src[t] == '\t')) t++;
        if (t >= le[k]) { fputc('\n', f); scope_track(ls[k], le[k]); continue; }

        content = ls[k] + (size_t)minind;
        line = xstrndup(g_src + content, le[k] - content);
        out = transform_line(line);
        emit_hoisted();
        buf_init(&sb);
        replace_self(out, strlen(out), &sb);
        {
            size_t p2 = 0;
            while (p2 < sb.n) {
                size_t q2 = p2;
                while (q2 < sb.n && sb.p[q2] != '\n') q2++;
                fputs("    ", f);
                fwrite(sb.p + p2, 1, q2 - p2, f);
                fputc('\n', f);
                p2 = (q2 < sb.n) ? q2 + 1 : q2;
            }
        }
        free(line);
        free(out);
        free(sb.p);
        scope_track(ls[k], le[k]);
    }

    memcpy(g_vars, saved_vars, sizeof(Var) * (size_t)saved_nvars);
    free(saved_vars);
    g_nvars = saved_nvars;
    g_nscope = saved_nscope;
    g_body_abs = saved_body_abs;
    g_body_pre = saved_body_pre;
    g_line_off = saved_line_off;
    free(ls);
    free(le);
}

/* ------------------------------------------------------- construct parsers */

static size_t parse_trait(size_t p)
{
    char name[MAX_NAME];
    Trait *T;
    size_t close, bstart, bend, i;
    Buf raw, clean;

    p += 5;                                     /* "trait" */
    p = skip_ws_comments(p);
    p = read_ident(p, name, sizeof name);
    if (!name[0]) die(p, "expected trait name");
    p = skip_ws_comments(p);
    if (p >= g_len || g_src[p] != '{') die(p, "expected '{' after trait '%s'", name);

    close = match_delim(p, '{', '}');
    bstart = p + 1;
    bend = close;

    if (g_ntraits >= MAX_TRAITS) die(p, "too many traits (max %d)", MAX_TRAITS);
    T = &g_traits[g_ntraits++];
    snprintf(T->name, sizeof T->name, "%s", name);
    snprintf(T->cname, sizeof T->cname, "%s", name);
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

    emit_trait_def(g_out, T);
    emit_trait_def(g_hout, T);
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
    S->npf = 0;
    S->nif = 0;
    S->npif = 0;
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
        if (idx >= 0 && fname[0] && ptr) {           /* pointer field to a known struct */
            if (S->npf >= MAX_FIELDS) die(pos, "too many struct fields in '%s'", S->name);
            snprintf(S->pfname[S->npf], MAX_NAME, "%s", fname);
            S->pftype[S->npf] = idx;
            S->npf++;
        } else if (tr >= 0 && fname[0] && ptr) {     /* pointer interface field: `struct T *x` */
            if (S->npif >= MAX_FIELDS) die(pos, "too many struct fields in '%s'", S->name);
            snprintf(S->pifname[S->npif], MAX_NAME, "%s", fname);
            S->piftype[S->npif] = tr;
            S->npif++;
        } else if (tr >= 0 && fname[0]) {            /* interface-value field: `T x` */
            if (S->nif >= MAX_FIELDS) die(pos, "too many struct fields in '%s'", S->name);
            snprintf(S->ifname[S->nif], MAX_NAME, "%s", fname);
            S->iftype[S->nif] = tr;
            S->nif++;
        } else if (idx >= 0 && fname[0]) {           /* value field of a known struct */
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
    snprintf(S->cname, sizeof S->cname, "%s", name);
    S->nu = 0;

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
            if (S->nu >= MAX_TRAITS) die(u, "too many traits used by '%s'", S->name);
            snprintf(S->use_t[S->nu], MAX_NAME, "%s", tn);
            S->nu++;
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

    {
        char *raw = xstrndup(g_src + bstart, bend - bstart);
        char *qbody = parse_fields(raw, S, p);
        free(raw);
        emit_struct_def(g_out, S, qbody);
        emit_struct_def(g_hout, S, qbody);
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
            if (body_needs_vtable(impl[k].bstart, impl[k].blen)) { needs_vtable = 1; break; }
        if (needs_vtable)
            fprintf(g_out, "static struct %s_vtbl %s_%s_vtable;\n\n",
                    T->cname, S->cname, T->name);
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

        fprintf(g_out, "static %s %s_%s_%s(void *self", tm->ret, S->cname, T->name, tm->name);
        if (tm->nparams > 0) fprintf(g_out, ", %s", impl[idx].params);
        fprintf(g_out, ") {\n");
        fprintf(g_out, "    struct %s *_self = (struct %s *)self;\n", S->cname, S->cname);
        emit_body(g_out, impl[idx].bstart, impl[idx].blen, S, impl[idx].params);
        fprintf(g_out, "}\n\n");
    }

    fprintf(g_out, "static struct %s_vtbl %s_%s_vtable = {\n",
            T->cname, S->cname, T->name);
    for (k = 0; k < (size_t)T->nm; k++)
        fprintf(g_out, "    .%s = %s_%s_%s%s\n",
                T->m[k].name, S->cname, T->name, T->m[k].name,
                (k + 1 < (size_t)T->nm) ? "," : "");
    fprintf(g_out, "};\n\n");

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

static size_t line_assign_eq(const char *line);   /* defined below, after the calls */

/* Follow `.field` / `->field` hops from the object of struct `cur` at offset
   `pos` (a pointer when `isptr`), stopping at the first method of a used trait.
   On success returns 1 and fills *out_cur (the receiver's struct), *out_rend
   (offset of the final '.' / '->', i.e. where the receiver text ends), *mp (the
   method's '('), *memb, *out_need_amp (pass '&self') and *out_tr (trait name). */
static int walk_method(const char *s, size_t n, size_t pos, int cur, int isptr,
                       int *out_cur, int *out_need_amp, const char **out_tr,
                       size_t *out_rend, size_t *mp, char *memb)
{
    char mem[MAX_NAME];

    for (;;) {
        size_t ms, k, ml;
        int fi;

        if (isptr) {
            if (!(pos + 1 < n && s[pos] == '-' && s[pos + 1] == '>')) return 0;
            k = pos + 2;
        } else {
            if (!(pos < n && s[pos] == '.')) return 0;
            k = pos + 1;
        }
        ms = k;
        while (k < n && is_ident_char((unsigned char)s[k])) k++;
        ml = k - ms;
        if (ml == 0) return 0;
        if (ml >= sizeof mem) ml = sizeof mem - 1;
        memcpy(mem, s + ms, ml);
        mem[ml] = 0;

        *out_tr = resolve_method(&g_structs[cur], mem);
        if (*out_tr && k < n && s[k] == '(') {
            *out_cur = cur;
            *out_need_amp = !isptr;
            *out_rend = pos;
            *mp = k;
            snprintf(memb, MAX_NAME, "%s", mem);
            return 1;
        }
        *out_tr = NULL;
        fi = find_field_ex(&g_structs[cur], mem, &isptr);
        if (fi < 0) return 0;
        cur = fi;
        pos = k;
    }
}

/* Follow `.field` / `->field` hops from the object of struct `cur` at offset
   `pos` (a pointer when `isptr`), stopping at an interface field. On success
   returns 1 and fills *out_tr (trait index), *out_end (offset just past the
   field name, i.e. where the receiver text ends) and *out_ifptr (whether the
   interface field is a `struct T *` pointer, so the hop uses '->'). */
static int walk_to_iface_field(const char *s, size_t n, size_t pos, int cur,
                               int isptr, int *out_tr, size_t *out_end,
                               int *out_ifptr)
{
    for (;;) {
        size_t ms, k, ml;
        int fi, tr, ifptr = 0;
        char mem[MAX_NAME];

        if (isptr) {
            if (!(pos + 1 < n && s[pos] == '-' && s[pos + 1] == '>')) return 0;
            k = pos + 2;
        } else {
            if (!(pos < n && s[pos] == '.')) return 0;
            k = pos + 1;
        }
        ms = k;
        while (k < n && is_ident_char((unsigned char)s[k])) k++;
        ml = k - ms;
        if (ml == 0) return 0;
        if (ml >= sizeof mem) ml = sizeof mem - 1;
        memcpy(mem, s + ms, ml);
        mem[ml] = 0;

        tr = find_iface_field(&g_structs[cur], mem, &ifptr);
        if (tr >= 0) {
            *out_tr = tr;
            *out_end = k;
            *out_ifptr = ifptr;
            return 1;
        }
        fi = find_field_ex(&g_structs[cur], mem, &isptr);
        if (fi < 0) return 0;
        cur = fi;
        pos = k;
    }
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
            /* an rvalue receiver: `f().m()` / `f()->m()` / `f().a.b.m()` where
               f returns a known struct. Its receiver is hoisted into a temp so
               it is evaluated once and in order; only a statement head or an
               initialiser (Q2-A) allows that without reordering evaluation, so
               any other position is a hard error (Q3-A). */
            if (vi < 0 && !g_no_box && j < n && s[j] == '(') {
                FuncSig *FS = find_func(tok);
                if (FS && FS->retstruct >= 0) {
                    size_t cp = line_match_paren(s, j, n);
                    if (cp != (size_t)-1) {
                        char mem[MAX_NAME];
                        const char *tr = NULL;
                        int cur = FS->retstruct, need_amp = 0;
                        size_t rend = 0, mp = 0;
                        if (walk_method(s, n, cp + 1, cur, FS->retptr, &cur,
                                        &need_amp, &tr, &rend, &mp, mem)) {
                            size_t fs = 0, eq, saved_off;
                            char tmp[MAX_NAME], low[MAX_NAME], *recv;
                            Buf ini;

                            while (fs < n && (s[fs] == ' ' || s[fs] == '\t')) fs++;
                            eq = line_assign_eq(s);
                            if (i != fs) {
                                int ok = 0;
                                if (eq != (size_t)-1) {
                                    size_t rs = eq + 1;
                                    while (rs < n && (s[rs] == ' ' || s[rs] == '\t')) rs++;
                                    if (i == rs) ok = 1;
                                }
                                if (!ok)
                                    die(g_line_off + i, "an rvalue receiver must start the statement or an initialiser");
                            }

                            snprintf(tmp, sizeof tmp, "__ct_tmp%d", g_ntmp++);
                            /* the initialiser is the receiver text, itself run
                               through the rewriter so nested calls are handled */
                            recv = xstrndup(s + i, rend - i);
                            buf_init(&ini);
                            saved_off = g_line_off;
                            g_line_off += i;
                            transform_calls(recv, &ini);
                            g_line_off = saved_off;
                            free(recv);

                            buf_putn(&g_hoist, s, fs);    /* keep the line's indent */
                            buf_puts(&g_hoist, "struct ");
                            buf_puts(&g_hoist, g_structs[cur].cname);
                            buf_puts(&g_hoist, need_amp ? " " : " *");
                            buf_puts(&g_hoist, tmp);
                            buf_puts(&g_hoist, " = ");
                            buf_puts(&g_hoist, ini.p);
                            buf_putc(&g_hoist, ';');
                            free(ini.p);

                            to_lower(tr, low);
                            buf_puts(out, tmp);
                            buf_puts(out, need_amp ? ".__" : "->__");
                            buf_puts(out, low);
                            buf_puts(out, "_vptr->");
                            buf_puts(out, mem);
                            buf_putc(out, '(');
                            if (need_amp) buf_putc(out, '&');
                            buf_puts(out, tmp);
                            {
                                size_t z = mp + 1;
                                int empty;
                                while (z < n && isspace((unsigned char)s[z])) z++;
                                empty = (z < n && s[z] == ')');
                                if (!empty) buf_puts(out, ", ");
                            }
                            i = mp + 1;
                            continue;
                        }
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
                size_t pos = j, rend = 0, mp = 0;
                int cur = g_vars[vi].s, need_amp = 1, hit = 0, unclosed = 0;
                int isptr = g_vars[vi].ptr;   /* is the current hop reached via a pointer? */

                if ((g_vars[vi].arr || g_vars[vi].ptr) && pos < n && s[pos] == '[') {
                    /* the receiver is an element: consume "[<expr>]", whose
                       expression may be anything (balanced brackets, skipping
                       literals) — e.g. ps[i], ps[i + 1], ps[f()] */
                    int d = 0;
                    size_t k = pos;
                    while (k < n) {
                        char e = s[k];
                        if (e == '"' || e == '\'') { k = line_literal_end(s, k, n); continue; }
                        if (e == '[') d++;
                        else if (e == ']') { d--; if (d == 0) { k++; break; } }
                        k++;
                    }
                    if (d != 0) unclosed = 1;
                    else {
                        pos = k;
                        /* an element of `T *ps[n]` is itself a pointer (uses '->'),
                           while `p[i]` on a plain `T *p` is a value */
                        isptr = g_vars[vi].arr && g_vars[vi].ptr;
                    }
                }
                if (!unclosed)
                    hit = walk_method(s, n, pos, cur, isptr, &cur, &need_amp,
                                      &tr, &rend, &mp, mem);

                if (hit) {
                    size_t z = mp + 1;
                    int empty;
                    while (z < n && isspace((unsigned char)s[z])) z++;
                    empty = (z < n && s[z] == ')');

                    to_lower(tr, low);
                    buf_putn(out, s + i, rend - i);           /* receiver */
                    buf_puts(out, need_amp ? ".__" : "->__");
                    buf_puts(out, low);
                    buf_puts(out, "_vptr->");
                    buf_puts(out, mem);
                    buf_putc(out, '(');
                    if (need_amp) buf_putc(out, '&');
                    buf_putn(out, s + i, rend - i);           /* receiver again */
                    if (!empty) buf_puts(out, ", ");
                    i = mp + 1;
                    continue;
                }

                /* an interface field as the receiver: `s.l.m()` ->
                   `s.l.vt->m(s.l.self)` (or `->` when the field is a pointer) */
                if (!unclosed && cur >= 0) {
                    int ftr, ifptr;
                    size_t fend;
                    if (walk_to_iface_field(s, n, pos, cur, isptr, &ftr, &fend, &ifptr)) {
                        size_t ms2, k2, ml2, z;
                        int empty;
                        char meth[MAX_NAME];
                        if (ifptr) {
                            if (!(fend + 1 < n && s[fend] == '-' && s[fend + 1] == '>')) goto no_iface_hit;
                            k2 = fend + 2;
                        } else {
                            if (!(fend < n && s[fend] == '.')) goto no_iface_hit;
                            k2 = fend + 1;
                        }
                        ms2 = k2;
                        while (k2 < n && is_ident_char((unsigned char)s[k2])) k2++;
                        ml2 = k2 - ms2;
                        if (ml2 == 0) goto no_iface_hit;
                        if (ml2 >= sizeof meth) ml2 = sizeof meth - 1;
                        memcpy(meth, s + ms2, ml2);
                        meth[ml2] = 0;
                        if (!(k2 < n && s[k2] == '(' &&
                              trait_has_method(&g_traits[ftr], meth)))
                            goto no_iface_hit;
                        z = k2 + 1;
                        while (z < n && isspace((unsigned char)s[z])) z++;
                        empty = (z < n && s[z] == ')');
                        buf_putn(out, s + i, fend - i);       /* receiver incl. field */
                        buf_puts(out, ifptr ? "->vt->" : ".vt->");
                        buf_puts(out, meth);
                        buf_putc(out, '(');
                        buf_putn(out, s + i, fend - i);
                        buf_puts(out, ifptr ? "->self" : ".self");
                        if (!empty) buf_puts(out, ", ");
                        i = k2 + 1;
                        continue;
                    }
                }
            no_iface_hit: ;
            }
            buf_putn(out, s + i, j - i);
            i = j;
            continue;
        }
        buf_putc(out, c);
        i++;
    }
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

/* "g = p;" — assigning into an interface value (the target type is the variable),
   or into an interface-value field ("s.l = p;", boxed through the field's trait) */
static char *try_iface_assign(const char *line)
{
    const char *p = line, *r;
    char id[MAX_NAME];
    size_t k = 0, el = 0, fend = 0;
    int vi, ftr = -1, ifptr = 0;
    Buf b;

    while (*p == ' ' || *p == '\t') p++;
    k = copy_ident(p, id, 0);
    id[k] = 0;
    if (!k) return NULL;
    vi = find_var(id);
    if (vi < 0) return NULL;

    if (!g_vars[vi].iface) {
        /* an assignment into an interface-value field: `s.l = v;` becomes a
           boxed fat pointer. Only value interface fields are boxed this way;
           a pointer interface field (`struct T *l`) needs an existing address,
           which box_to_iface cannot synthesise, so it is left verbatim. */
        if (g_vars[vi].s < 0) return NULL;
        if (!walk_to_iface_field(line, strlen(line), (size_t)(p + k - line),
                                 g_vars[vi].s, g_vars[vi].ptr, &ftr, &fend, &ifptr))
            return NULL;
        if (ifptr) return NULL;
        r = line + fend;
    } else {
        ftr = g_vars[vi].tr;
        r = p + k;
    }

    while (*r == ' ' || *r == '\t') r++;
    if (*r != '=' || r[1] == '=') return NULL;
    r++;
    while (*r == ' ' || *r == '\t') r++;
    if (!*r || *r == '{' || strncmp(r, "(struct ", 8) == 0) return NULL;
    while (r[el] && r[el] != ';') el++;
    if (!el) return NULL;

    buf_init(&b);
    buf_putn(&b, line, (size_t)(r - line));
    box_to_iface(&b, r, el, ftr, 0);
    buf_puts(&b, r + el);
    return b.p;
}

/* "<Struct> x = {...};" / "struct <Struct> x = {...};" -> add struct + vptr */
static char *try_var_decl(const char *line)
{
    size_t i = 0, ws, vk, nk;
    const char *p;
    char name[MAX_NAME], var[MAX_NAME];
    Struct *S;
    int done = 0, static_kw = 0;
    const char *rest;
    Buf b;

    while (line[i] == ' ' || line[i] == '\t') i++;
    ws = i;
    p = line + i;

    /* a leading `static` is re-emitted verbatim: the declaration underneath is
       still a ct struct object and must get its vptr written like any other */
    if (strncmp(p, "static", 6) == 0 && !is_ident_char((unsigned char)p[6])) {
        const char *z = p + 6;
        while (*z == ' ' || *z == '\t') z++;
        static_kw = 1;
        p = z;
    }

    if (strncmp(p, "struct", 6) == 0 && !is_ident_char((unsigned char)p[6])) {
        p += 6;
        while (*p == ' ' || *p == '\t') p++;
    }

    nk = copy_ident(p, name, 0);
    name[nk] = 0;
    if (!nk) return NULL;
    p += nk;
    S = find_struct(name);
    if (!S) {
        Trait *TR = find_trait(name);
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
            {
                /* `T *ps[<n>]` is an array of pointers — its elements are reached
                   with '->', unlike `T *p`, where p[i] is a value */
                const char *aft = q + pk;
                while (*aft == ' ' || *aft == '\t') aft++;
                g_vars[vi].arr = (*aft == '[');
            }
            g_vars[vi].iface = 0;
            g_vars[vi].tr = -1;
        }
        buf_init(&b);
        buf_putn(&b, line, ws);
        if (static_kw) buf_puts(&b, "static ");
        buf_puts(&b, "struct ");
        buf_puts(&b, S->cname);
        buf_putc(&b, ' ');
        buf_puts(&b, p);
        /* heap creation (Phase 1, D1=A): `T *x = malloc(...)` / calloc gets its
           vptrs written, so a heap object is usable without a hand-written vptr */
        {
            const char *eq = strchr(p, '=');
            const char *rhs = eq ? eq + 1 : NULL;
            int isheap = 0;
            if (rhs) {
                while (*rhs == ' ' || *rhs == '\t') rhs++;
                isheap = (strncmp(rhs, "malloc", 6) == 0 && !is_ident_char((unsigned char)rhs[6])) ||
                         (strncmp(rhs, "calloc", 6) == 0 && !is_ident_char((unsigned char)rhs[6]));
            }
            if (isheap && (S->nu > 0 || needs_nested_init(S, 0))) {
                char ind[MAX_NAME];
                size_t t;
                for (t = 0; t < ws && t + 1 < sizeof ind; t++) ind[t] = ' ';
                ind[t] = 0;
                buf_putc(&b, '\n');
                put_heap_vpts(&b, S, pv, ind);
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
            if (static_kw) buf_puts(&b, "static ");
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
    if (static_kw) buf_puts(&b, "static ");
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
    int ret_struct = -1, ret_rptr = 0;
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
        ret_struct = analyse_param(line, rt, &ret_ia, &ret_ib, ret_cbase,
                                   &ret_ns, rname, &ret_rptr, &ret_tr);
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
            FS->retstruct = (ret_tr >= 0) ? -1 : ret_struct;
            FS->retptr = (ret_tr >= 0) ? 0 : ret_rptr;
            for (q = 0; q < npar; q++) FS->ptrait[q] = ptrait[q];
        }
        if (isdef) g_cur_rettr = ret_tr;
    }

    buf_putc(&b, ')');
    buf_puts(&b, line + rp + 1);
    return b.p;
}

/* -------------------------------------------- line helpers / block scopes */

/* offset of a top-level assignment '=' in `line`, or (size_t)-1 when there is
   none; skips ==, !=, <=, >=, compound op= and text in literals/comments */
static size_t line_assign_eq(const char *line)
{
    size_t len = strlen(line), i = 0;
    while (i < len) {
        char c = line[i];
        if (c == '"' || c == '\'') { i = line_literal_end(line, i, len); continue; }
        if (c == '/' && (line[i + 1] == '/' || line[i + 1] == '*')) break;
        if (c == '=') {
            char next = line[i + 1];
            char prev = (i > 0) ? line[i - 1] : 0;
            if (next == '=') { i += 2; continue; }
            if (prev && strchr("=!<>+-*/%&|^", prev)) { i++; continue; }
            return i;
        }
        i++;
    }
    return (size_t)-1;
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
            if (g_nscope > 0)
                g_nvars = g_scope[--g_nscope];
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
    if (!g_hoist.cap) buf_init(&g_hoist);            /* Phase 1.9b: per-line hoist */
    g_hoist.n = 0;
    g_hoist.p[0] = 0;
    while (t < len && (line[t] == ' ' || line[t] == '\t')) t++;
    if (t < len && line[t] == '#') {                 /* preprocessor: verbatim */
        fputs(line, g_out);
        free(line);
        return;
    }

    g_line_off = ls;                                /* base offset for diagnostics */
    sig = parse_func_sig(line, ls, &has_body, &body_abs);
    if (sig) {
        Buf b;
        if (has_body) { g_body_abs = body_abs; g_body_pre = pre; }
        buf_init(&b);
        g_no_box = 1;                        /* the parameter list is not a call */
        transform_calls(sig, &b);
        g_no_box = 0;
        fputs(b.p, g_out);
        free(b.p);
        free(sig);
    } else {
        char *out = transform_line(line);
        emit_hoisted();                      /* Phase 1.9b: decl before the line */
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
            "usage: %s [compile] <input.ct> [-o <output.c>]\n\n"
            "Compiles C-with-traits (.ct) files into plain C.\n"
            "`compile` (default) writes <output.c> and a matching header <output.h>;\n"
            "if -o is omitted the output is <input>.c next to the input.\n\n"
            "  -o <file>       write the generated C to <file>\n"
            "  -v, --version   print the compiler version and exit\n"
            "  -h, --help      print this help and exit\n",
            prog);
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
    fprintf(g_hout, "/* Generated by ct v%s from %s (Phase 0: types only, the\n"
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

/* Scan [start,end): expand traits/structs/impls, pass the rest through. */
static void compile_range(size_t start, size_t end)
{
    size_t pos = start;

    while (pos < end) {
        size_t ls = pos, q, le;

        q = ls;
        while (q < end && (g_src[q] == ' ' || g_src[q] == '\t')) q++;

        /* namespace / import / pub belong to the module system, which lives in
           the CT layer since Phase 0.3 (it was implemented in C during the
           over-reach). Passing them through would silently emit C that cannot
           compile, so fail loudly instead (AGENTS §4). A following identifier
           marks a construct attempt, so ordinary C identifiers of the same
           spelling still pass through. */
        {
            static const char *const gone[] = { "namespace", "import", "pub" };
            int gi;
            for (gi = 0; gi < 3; gi++) {
                char nm[MAX_NAME];
                size_t t;
                if (!word_at(q, gone[gi])) continue;
                t = read_ident(skip_ws_comments(q + strlen(gone[gi])), nm, sizeof nm);
                if (nm[0] || (t < g_len && g_src[t] == '{'))
                    die(q, "'%s' is not supported by this compiler", gone[gi]);
            }
        }

        /* 'trait' / 'impl' are ct-only keywords: a line that starts with one and
           is followed by an identifier or '{' is an attempted construct, so a
           malformed header must die (AGENTS §4). Plain C may still use them as
           identifiers in expressions (e.g. 'impl[n] = 0;') — those are followed
           by neither and pass through. */
        if (word_at(q, "trait")) {
            char nm[MAX_NAME];
            size_t t = read_ident(skip_ws_comments(q + 5), nm, sizeof nm);
            if (nm[0] || (t < g_len && g_src[t] == '{')) { pos = parse_trait(q); continue; }
        }
        if (word_at(q, "impl")) {
            char nm[MAX_NAME];
            size_t t = read_ident(skip_ws_comments(q + 4), nm, sizeof nm);
            if (nm[0] || (t < g_len && g_src[t] == '{')) { pos = parse_impl(q); continue; }
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

        le = ls;
        while (le < end && g_src[le] != '\n') le++;
        emit_raw_line(ls, le);
        if (le < end) { fputc('\n', g_out); le++; }
        pos = le;
    }
}

/* Compile one input to `outc` and a matching header. Returns 0 on success. */
static int compile_file(const char *in, const char *outc)
{
    char hbuf[MAX_NAME * 4];
    FILE *body;

    g_nvars = 0;
    g_nscope = 0;
    g_cur_rettr = -1;
    g_body_abs = 0;
    g_body_pre = 0;
    g_no_box = 0;
    g_ntraits = 0;
    g_nstructs = 0;
    g_nfuncs = 0;

    header_path(outc, hbuf, sizeof hbuf);
    g_path = in;
    g_src = read_file(in, &g_len);

    g_out = fopen(outc, "w");
    if (!g_out) { fprintf(stderr, "ctc: cannot write '%s'\n", outc); return 1; }
    g_hout = fopen(hbuf, "w");
    if (!g_hout) { fprintf(stderr, "ctc: cannot write '%s'\n", hbuf); fclose(g_out); return 1; }

    write_guard(hbuf);

    /* provenance banner: the generated C is a build product, not a source file */
    fprintf(g_out, "/* Generated by ct v%s from %s -- do not edit; "
                   "change the .ct and re-run ct. */\n"
                   "/* Generated output is not covered by the GPL and may be "
                   "used without restriction (LICENSE.EXCEPTION). */\n",
            CTC_VERSION, g_path);

    /* Buffer the body so the file-scope objects/arrays (whose vptr writes are
       statements, not declarators) can be emitted afterwards as a constructor. */
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
        rewind(body);
        for (;;) {
            char chunk[8192];
            size_t got = fread(chunk, 1, sizeof chunk, body);
            if (!got) break;
            fwrite(chunk, 1, got, g_out);
        }
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

/* ---------------------------------------------------------- compile driver */

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
        if (argv[i][0] == '-' && argv[i][1]) {
            fprintf(stderr, "ctc: unknown option '%s'\n", argv[i]);
            usage(prog);
            return 1;
        }
        in = argv[i];
    }

    if (!in) { usage(prog); return 1; }
    if (!outc) { default_output(in, outbuf, sizeof outbuf); outc = outbuf; }
    return compile_file(in, outc);
}

int main(int argc, char **argv)
{
    int first = 1;

    /* Single-entry `ct` with `ctc` kept as a compatibility alias. `compile` is
       the default subcommand (`ct X` == `ct compile X`). */
    if (first < argc && strcmp(argv[first], "compile") == 0)
        first++;

    /* multi-file mode lives in the CT layer since Phase 0.3; report it instead
       of falling through and failing with a confusing "cannot open" (AGENTS §4). */
    if (first < argc && strcmp(argv[first], "build") == 0) {
        fprintf(stderr, "ctc: 'build' (multi-file) is not supported by this compiler\n");
        return 1;
    }

    return compile_main(argc - first, argv + first, argv[0]);
}
