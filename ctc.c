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
    Method m[MAX_METHOD];
    int    nm;
} Trait;

typedef struct {
    char name[MAX_NAME];
    char use_t[MAX_TRAITS][MAX_NAME];
    int  nu;
    char fname[MAX_FIELDS][MAX_NAME];  /* value fields whose type is a known struct */
    int  ftype[MAX_FIELDS];            /* ... and their index into g_structs */
    int  nf;
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
        if (i + 1 < n) buf[i++] = g_src[p];
        p++;
    }
    buf[i] = 0;
    return p;
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
        if (strcmp(g_traits[i].name, name) == 0) return &g_traits[i];
    return NULL;
}

static Struct *find_struct(const char *name)
{
    int i;
    for (i = 0; i < g_nstructs; i++)
        if (strcmp(g_structs[i].name, name) == 0) return &g_structs[i];
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
        Trait *t = find_trait(s->use_t[i]);
        if (!t) continue;
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
   type is an interface value (`*tr`, or -1), where "struct " must be inserted
   (`*ins`) and where "_iface" must be appended (`*ins2`), the declared name
   ("" when unnamed) and whether it is a pointer. Arrays are qualified but carry
   no name. */
static int analyse_param(const char *s, size_t n, int *ins, int *ins2,
                         char *name, int *isptr, int *tr)
{
    size_t a, b, lim = 0, tn, ea, eb;
    char tok[MAX_NAME], type[MAX_NAME * 2], base[MAX_NAME];
    int idx = -1;

    *ins = -1;
    *ins2 = -1;
    *tr = -1;
    name[0] = 0;
    *isptr = 0;

    while (lim < n && s[lim] != '[') lim++;
    if (!last_ident(s, lim, &a, &b)) return -1;

    {
        size_t tl = b - a;
        if (tl >= sizeof tok) tl = sizeof tok - 1;
        memcpy(tok, s + a, tl);
        tok[tl] = 0;
        if (is_type_keyword(tok) || find_struct(tok) || find_trait(tok)) {
            snprintf(type, sizeof type, "%.*s", (int)n, s);   /* the type itself */
        } else {
            snprintf(name, MAX_NAME, "%s", tok);
            snprintf(type, sizeof type, "%.*s", (int)a, s);
        }
    }
    if (lim < n) name[0] = 0;                                 /* array: no object to bind */

    /* the base type name: drop trailing '*'/space, then take the last identifier */
    tn = strlen(type);
    while (tn > 0 && (type[tn - 1] == '*' || isspace((unsigned char)type[tn - 1]))) tn--;
    if (tn == 0 || !last_ident(type, tn, &ea, &eb)) return -1;

    {
        size_t bl = eb - ea;
        if (bl >= sizeof base) bl = sizeof base - 1;
        memcpy(base, type + ea, bl);
        base[bl] = 0;
    }
    if (find_struct(base)) {
        idx = (int)(find_struct(base) - g_structs);
        if (!already_qualified(type, ea)) *ins = (int)ea;
    } else if (find_trait(base)) {
        *tr = (int)(find_trait(base) - g_traits);
        if (!already_qualified(type, ea)) { *ins = (int)ea; *ins2 = (int)eb; }
    } else if (strlen(base) > 6 && strcmp(base + strlen(base) - 6, "_iface") == 0) {
        /* the already-expanded spelling "struct X_iface" */
        char pre[MAX_NAME];
        size_t pl = strlen(base) - 6;
        if (pl < sizeof pre) {
            memcpy(pre, base, pl);
            pre[pl] = 0;
            if (find_trait(pre)) *tr = (int)(find_trait(pre) - g_traits);
        }
    }

    *isptr = (strchr(type, '*') != NULL);
    return idx;
}

/* emit a declaration piece, inserting "struct " (and "_iface" for a trait) */
static void emit_qualified_type(Buf *b, const char *piece, size_t len, int ins, int ins2)
{
    if (ins < 0) { buf_putn(b, piece, len); return; }
    buf_putn(b, piece, (size_t)ins);
    buf_puts(b, "struct ");
    if (ins2 >= 0) {
        buf_putn(b, piece + ins, (size_t)ins2 - (size_t)ins);
        buf_puts(b, "_iface");
        buf_putn(b, piece + ins2, len - (size_t)ins2);
    } else {
        buf_putn(b, piece + ins, len - (size_t)ins);
    }
}

/* ------------------------------------------------------------ emitters */

static void emit_trait_def(FILE *f, const Trait *T)
{
    int i, k;
    fprintf(f, "struct %s_vtbl {\n", T->name);
    for (i = 0; i < T->nm; i++) {
        const Method *m = &T->m[i];
        fprintf(f, "    %s (*%s)(void *", m->ret, m->name);
        for (k = 0; k < m->nparams; k++) fprintf(f, ", %s", m->ptypes[k]);
        fprintf(f, ");\n");
    }
    fprintf(f, "};\n");
    /* the interface value type: a fat pointer to an object plus its vtable */
    fprintf(f, "struct %s_iface {\n    void *self;\n    struct %s_vtbl *vt;\n};\n",
            T->name, T->name);
}

static void emit_struct_def(FILE *f, const Struct *S, const char *body)
{
    int i;
    size_t blen = strlen(body);

    fprintf(f, "struct %s {", S->name);
    if (blen && body[0] != '\n') fputc('\n', f);
    if (blen) fputs(body, f);
    if (blen == 0 || body[blen - 1] != '\n') fputc('\n', f);
    for (i = 0; i < S->nu; i++) {
        char low[MAX_NAME];
        to_lower(S->use_t[i], low);
        fprintf(f, "    struct %s_vtbl *__%s_vptr;\n", S->use_t[i], low);
    }
    fprintf(f, "};\n");
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

    for (k = first; k <= last; k++) {
        size_t t = ls[k];
        while (t < le[k] && (r.p[t] == ' ' || r.p[t] == '\t')) t++;
        if (t >= le[k]) { fputc('\n', f); continue; }
        fputs("    ", f);
        fwrite(r.p + ls[k] + minind, 1, le[k] - ls[k] - minind, f);
        fputc('\n', f);
    }

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
    buf_init(&out);

    while (i < n) {
        size_t j = i, depth = 0;
        int ins = -1, ins2 = -1, ptr = 0, idx, tr;
        char fname[MAX_NAME];

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

        idx = analyse_param(body + i, j - i, &ins, &ins2, fname, &ptr, &tr);
        emit_qualified_type(&out, body + i, j - i, ins, ins2);
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

    for (i = 0; i < S->nu; i++)
        if (!find_trait(S->use_t[i]))
            die(p, "struct '%s' uses undefined trait '%s'", S->name, S->use_t[i]);

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
            if (blen >= MAX_PARAM) blen = MAX_PARAM - 1;
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
        if (needs_vtable)
            fprintf(g_out, "static struct %s_vtbl %s_%s_vtable;\n\n",
                    T->name, S->name, T->name);
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

        fprintf(g_out, "static %s %s_%s_%s(void *self", tm->ret, S->name, T->name, tm->name);
        if (tm->nparams > 0) fprintf(g_out, ", %s", impl[idx].params);
        fprintf(g_out, ") {\n");
        fprintf(g_out, "    struct %s *_self = (struct %s *)self;\n", S->name, S->name);
        emit_body(g_out, impl[idx].bstart, impl[idx].blen, S);
        fprintf(g_out, "}\n\n");
    }

    fprintf(g_out, "static struct %s_vtbl %s_%s_vtable = {\n",
            T->name, S->name, T->name);
    for (k = 0; k < (size_t)T->nm; k++)
        fprintf(g_out, "    .%s = %s_%s_%s%s\n",
                T->m[k].name, S->name, T->name, T->m[k].name,
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
        buf_puts(b, S->name);
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
        buf_puts(b, S->name);
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
    buf_puts(out, g_traits[tr].name);
    buf_puts(out, "_iface){ (void *)");
    if (g_vars[vi].ptr) buf_puts(out, id);
    else { buf_putc(out, '&'); buf_puts(out, id); }
    buf_puts(out, ", &");
    buf_puts(out, S->name);
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

/* "Greeter g;" / "Greeter g = p;" / "Greeter *g;" — an interface-value declaration */
static char *try_iface_decl(const char *line, const char *tname, int tr, size_t ws,
                            const char *after)
{
    char var[MAX_NAME];
    size_t vk = 0;
    const char *p = after;
    const char *rest, *r;
    Buf b;
    int ptr = 0;

    while (*p == ' ' || *p == '\t') p++;
    if (*p == '*') { ptr = 1; p++; while (*p == ' ' || *p == '\t') p++; }
    while (is_ident_char((unsigned char)p[vk]) && vk < MAX_NAME - 1) { var[vk] = p[vk]; vk++; }
    var[vk] = 0;
    if (!vk) return NULL;
    rest = p + vk;
    r = rest;
    while (*r == ' ' || *r == '\t') r++;

    buf_init(&b);
    buf_putn(&b, line, ws);
    buf_puts(&b, "struct ");
    buf_puts(&b, tname);
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
        die(0, "unsupported declaration of interface type '%s'", tname);
    }

    if (g_nvars < MAX_VARS) {
        snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", var);
        g_vars[g_nvars].s = -1;
        g_vars[g_nvars].ptr = 0;
        g_vars[g_nvars].arr = 0;
        g_vars[g_nvars].iface = 1;
        g_vars[g_nvars].tr = tr;
        g_nvars++;
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
    while (is_ident_char((unsigned char)p[k]) && k < MAX_NAME - 1) { id[k] = p[k]; k++; }
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
    size_t i = 0, ws, k, vk;
    const char *p;
    char name[MAX_NAME], var[MAX_NAME];
    Struct *S;
    int had_struct = 0, done = 0;
    const char *rest;
    Buf b;

    while (line[i] == ' ' || line[i] == '\t') i++;
    ws = i;
    p = line + i;

    if (strncmp(p, "struct", 6) == 0 && !is_ident_char((unsigned char)p[6])) {
        had_struct = 1;
        p += 6;
        while (*p == ' ' || *p == '\t') p++;
    }

    k = 0;
    while (is_ident_char((unsigned char)p[k]) && k < MAX_NAME - 1) { name[k] = p[k]; k++; }
    name[k] = 0;
    if (!k) return NULL;
    S = find_struct(name);
    if (!S) {
        Trait *TR = find_trait(name);
        if (!TR) return NULL;
        return try_iface_decl(line, name, (int)(TR - g_traits), ws, p + k);
    }
    p += k;
    while (*p == ' ' || *p == '\t') p++;

    if (*p == '*') {                              /* pointer decl: qualify + register */
        const char *q = p;
        char pv[MAX_NAME];
        int pk = 0;
        while (*q == '*' || *q == ' ' || *q == '\t') q++;
        while (is_ident_char((unsigned char)q[pk]) && pk < MAX_NAME - 1) { pv[pk] = q[pk]; pk++; }
        pv[pk] = 0;
        if (pk && g_nvars < MAX_VARS) {
            snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", pv);
            g_vars[g_nvars].s = (int)(S - g_structs);
            g_vars[g_nvars].ptr = 1;
            g_vars[g_nvars].arr = 0;
            g_vars[g_nvars].iface = 0;
            g_vars[g_nvars].tr = -1;
            g_nvars++;
        }
        if (had_struct) return NULL;              /* already carries "struct" */
        buf_init(&b);
        buf_putn(&b, line, ws);
        buf_puts(&b, "struct ");
        buf_puts(&b, name);
        buf_putc(&b, ' ');
        buf_puts(&b, p);
        return b.p;
    }

    vk = 0;
    while (is_ident_char((unsigned char)p[vk]) && vk < MAX_NAME - 1) { var[vk] = p[vk]; vk++; }
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
            needs = (S->nu > 0 || needs_nested_init(S, 0));
            while (*d >= '0' && *d <= '9') d++;
            cl = d;
            if (needs && (cl == q + 1 || *cl != ']' || !decl_end_is_bare(cl + 1)))
                die(0, "struct '%s': only 'Type name[<n>];' arrays are supported", S->name);
            if (needs && g_nscope == 0)
                die(0, "struct '%s': an array of objects must be declared inside a function",
                    S->name);

            buf_init(&b);
            if (!had_struct) { buf_putn(&b, line, ws); buf_puts(&b, "struct "); }
            buf_puts(&b, line + ws);

            if (needs) {
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
                for (k2 = 0; k2 < ws && k2 < sizeof ind - 1; k2++) ind[k2] = line[k2];
                ind[k2] = 0;
                if (dl >= sizeof cnt) dl = sizeof cnt - 1;
                memcpy(cnt, q + 1, dl);
                cnt[dl] = 0;
                snprintf(ind2, sizeof ind2, "%s        ", ind);
                snprintf(recv, sizeof recv, "%s[__ct_i]", var);

                buf_putc(&b, '\n');
                buf_puts(&b, ind);  buf_puts(&b, "{\n");
                buf_puts(&b, ind);  buf_puts(&b, "    for (unsigned long __ct_i = 0; __ct_i < ");
                buf_puts(&b, cnt);
                buf_puts(&b, "; __ct_i++) {\n");
                put_nested_assignments(&b, S, recv, ind2, 1, 0);
                buf_puts(&b, ind);  buf_puts(&b, "    }\n");
                buf_puts(&b, ind);  buf_puts(&b, "}\n");
                if (b.n > 0 && b.p[b.n - 1] == '\n') { b.n--; b.p[b.n] = 0; }
            }
            return b.p;
        }
    }

    if (g_nvars < MAX_VARS) {
        snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", var);
        g_vars[g_nvars].s = (int)(S - g_structs);
        g_vars[g_nvars].ptr = 0;
        g_vars[g_nvars].arr = 0;
        g_vars[g_nvars].iface = 0;
        g_vars[g_nvars].tr = -1;
        g_nvars++;
    }

    buf_init(&b);
    buf_putn(&b, line, ws);
    buf_puts(&b, "struct ");
    buf_puts(&b, name);
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
        /* vptr writes need statements, so they must live inside a function */
        char ind[MAX_NAME];
        size_t k;
        if (g_nscope == 0)
            die(0, "struct '%s' has nested objects: declare it inside a function", S->name);
        for (k = 0; k < ws && k < sizeof ind - 1; k++) ind[k] = line[k];
        ind[k] = 0;
        buf_putc(&b, '\n');
        put_nested_assignments(&b, S, var, ind, !done, 0);
        if (b.n > 0 && b.p[b.n - 1] == '\n') { b.n--; b.p[b.n] = 0; }
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
    while (is_ident_char((unsigned char)p[k]) && k < MAX_NAME - 1) { id[k] = p[k]; k++; }
    id[k] = 0;
    if (!k || !decl_end_is_bare(p + k)) return NULL;
    {
        int vi = find_var(id);
        if (vi < 0 || !g_vars[vi].ptr) return NULL;
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
    int isdef = 0, ret_tr = -1, ret_ins = -1, ret_ins2 = -1;

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
        analyse_param(line, rt, &ret_ins, &ret_ins2, rname, &rptr, &ret_tr);
    }

    buf_init(&b);
    emit_qualified_type(&b, line, lpo, ret_ins, ret_ins2);
    buf_putc(&b, '(');

    {
        int npar = 0, ptrait[MAX_PARAMS];
        for (i = lpo + 1, end = rp; i < end; ) {
            size_t j = i;
            int depth = 0, pins = -1, pins2 = -1, ptr = 0, sidx, ptrtr = -1;
            char pname[MAX_NAME];

            while (j < end) {
                char c = line[j];
                if (c == '"' || c == '\'') { j = line_literal_end(line, j, end); continue; }
                if (c == '(' || c == '[' || c == '{') depth++;
                else if (c == ')' || c == ']' || c == '}') depth--;
                else if (c == ',' && depth == 0) break;
                j++;
            }
            sidx = analyse_param(line + i, j - i, &pins, &pins2, pname, &ptr, &ptrtr);
            emit_qualified_type(&b, line + i, j - i, pins, pins2);

            if (isdef && pname[0] && g_nvars < MAX_VARS) {
                if (sidx >= 0) {                     /* concrete object parameter */
                    snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", pname);
                    g_vars[g_nvars].s = sidx;
                    g_vars[g_nvars].ptr = ptr;
                    g_vars[g_nvars].arr = 0;
                    g_vars[g_nvars].iface = 0;
                    g_vars[g_nvars].tr = -1;
                    g_nvars++;
                } else if (ptrtr >= 0) {             /* interface value parameter */
                    snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", pname);
                    g_vars[g_nvars].s = -1;
                    g_vars[g_nvars].ptr = 0;
                    g_vars[g_nvars].arr = 0;
                    g_vars[g_nvars].iface = 1;
                    g_vars[g_nvars].tr = ptrtr;
                    g_nvars++;
                }
            }
            {
                char pbuf[MAX_NAME * 2];
                size_t pl = j - i;
                if (pl >= sizeof pbuf) pl = sizeof pbuf - 1;
                memcpy(pbuf, line + i, pl);
                pbuf[pl] = 0;
                trim(pbuf);
                if (pbuf[0] && strcmp(pbuf, "void") != 0 && npar < MAX_PARAMS)
                    ptrait[npar++] = ptrtr;
            }
            if (j < end) { buf_putc(&b, ','); j++; }
            i = j;
        }
        /* record the signature so call sites can box interface arguments */
        if (g_nfuncs < MAX_FUNCS) {
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
            "usage: %s <input.ct> [-o <output.c>]\n\n"
            "Compiles a C-with-traits (.ct) file into plain C.\n"
            "Writes <output.c> and a matching header <output.h>.\n"
            "If -o is omitted the output is <input>.c next to the input.\n\n"
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

int main(int argc, char **argv)
{
    const char *in = NULL, *outc = NULL;
    char outbuf[MAX_NAME * 4], hbuf[MAX_NAME * 4];
    size_t pos = 0;
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
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
            usage(argv[0]);
            return 1;
        }
        in = argv[i];
    }

    if (!in) { usage(argv[0]); return 1; }
    if (!outc) { default_output(in, outbuf, sizeof outbuf); outc = outbuf; }
    header_path(outc, hbuf, sizeof hbuf);

    g_path = in;
    g_src = read_file(in, &g_len);

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

    while (pos < g_len) {
        size_t ls = pos, q, le;

        q = ls;
        while (q < g_len && (g_src[q] == ' ' || g_src[q] == '\t')) q++;

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

        le = ls;
        while (le < g_len && g_src[le] != '\n') le++;
        emit_raw_line(ls, le);
        if (le < g_len) { fputc('\n', g_out); le++; }
        pos = le;
    }

    fprintf(g_hout, "\n#endif /* %s */\n", g_guard);

    fclose(g_out);
    fclose(g_hout);
    return 0;
}
