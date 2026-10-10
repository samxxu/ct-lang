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
#define MAX_VARS   512

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
} Struct;

typedef struct {
    char name[MAX_NAME];
    int  s;                            /* index into g_structs */
} Var;

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
}

static void emit_struct_def(FILE *f, const Struct *S, size_t bstart, size_t blen)
{
    int i;
    fprintf(f, "struct %s {", S->name);
    if (blen && g_src[bstart] != '\n') fputc('\n', f);
    if (blen) fwrite(g_src + bstart, 1, blen, f);
    if (blen == 0 || g_src[bstart + blen - 1] != '\n') fputc('\n', f);
    for (i = 0; i < S->nu; i++) {
        char low[MAX_NAME];
        to_lower(S->use_t[i], low);
        fprintf(f, "    struct %s_vtbl *__%s_vptr;\n", S->use_t[i], low);
    }
    fprintf(f, "};\n");
}

/* replace the `self` identifier by `_self`, skipping strings/comments */
static void replace_self(size_t bstart, size_t blen, Buf *out)
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
            if (j - i == 4 && memcmp(g_src + i, "self", 4) == 0) buf_puts(out, "_self");
            else buf_putn(out, g_src + i, j - i);
            i = j;
            continue;
        }
        buf_putc(out, c);
        i++;
    }
}

/* re-indent a method body: drop the shared indentation, use 4 spaces */
static void emit_body(FILE *f, size_t bstart, size_t blen)
{
    Buf r;
    size_t i, j, n;
    int minind = 1 << 30;
    size_t *ls, *le;
    int nlines = 0, first = -1, last = -1, k;

    buf_init(&r);
    replace_self(bstart, blen, &r);
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

    emit_struct_def(g_out, S, bstart, bend - bstart);
    emit_struct_def(g_hout, S, bstart, bend - bstart);
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
        emit_body(g_out, impl[idx].bstart, impl[idx].blen);
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

/* is the brace list `inner` made only of ".field = ..." elements? */
static int is_designated_list(const char *inner, int *has_elem)
{
    size_t i = 0, n = strlen(inner), start = 0;
    int depth = 0;
    *has_elem = 0;

    for (i = 0; i <= n; i++) {
        char c = (i < n) ? inner[i] : ',';
        if (i < n) {
            if (c == '"' || c == '\'') { i = line_literal_end(inner, i, n) - 1; continue; }
            if (c == '{' || c == '(' || c == '[') depth++;
            else if (c == '}' || c == ')' || c == ']') depth--;
        }
        if (c == ',' && depth == 0) {
            size_t a = start, b = i;
            while (a < b && isspace((unsigned char)inner[a])) a++;
            while (b > a && isspace((unsigned char)inner[b - 1])) b--;
            if (b > a) {
                if (inner[a] != '.') return 0;
                *has_elem = 1;
            }
            start = i + 1;
        }
    }
    return 1;
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
            char tok[MAX_NAME], mem[MAX_NAME];
            size_t tl, ms, ml;
            int vi;

            while (j < n && is_ident_char((unsigned char)s[j])) j++;
            tl = j - i;
            if (tl >= sizeof tok) tl = sizeof tok - 1;
            memcpy(tok, s + i, tl);
            tok[tl] = 0;

            vi = find_var(tok);
            if (vi >= 0 && j < n && s[j] == '.') {
                size_t k = j + 1;
                ms = k;
                while (k < n && is_ident_char((unsigned char)s[k])) k++;
                ml = k - ms;
                if (ml >= sizeof mem) ml = sizeof mem - 1;
                memcpy(mem, s + ms, ml);
                mem[ml] = 0;

                if (ml > 0 && k < n && s[k] == '(') {
                    const char *tr = resolve_method(&g_structs[g_vars[vi].s], mem);
                    if (tr) {
                        size_t cp = line_match_paren(s, k, n);
                        if (cp != (size_t)-1) {
                            int empty = 1;
                            size_t z;
                            for (z = k + 1; z < cp; z++)
                                if (!isspace((unsigned char)s[z])) { empty = 0; break; }

                            char low[MAX_NAME];
                            to_lower(tr, low);
                            buf_puts(out, tok);
                            buf_puts(out, ".__");
                            buf_puts(out, low);
                            buf_puts(out, "_vptr->");
                            buf_puts(out, mem);
                            buf_puts(out, "(&");
                            buf_puts(out, tok);
                            if (empty) {
                                buf_putc(out, ')');
                                i = cp + 1;
                            } else {
                                buf_puts(out, ", ");
                                i = k + 1;
                            }
                            continue;
                        }
                    }
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

/* "<Struct> x = {...};" / "struct <Struct> x = {...};" -> add struct + vptr */
static char *try_var_decl(const char *line)
{
    size_t i = 0, ws, k, vk;
    const char *p;
    char name[MAX_NAME], var[MAX_NAME];
    Struct *S;
    int had_struct = 0;
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
    if (!S) return NULL;
    p += k;
    while (*p == ' ' || *p == '\t') p++;

    if (*p == '*') {                              /* pointer decl: qualify only */
        if (had_struct) return NULL;
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

    if (g_nvars < MAX_VARS) {
        snprintf(g_vars[g_nvars].name, MAX_NAME, "%s", var);
        g_vars[g_nvars].s = (int)(S - g_structs);
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
                    int has_elem = 0, ok = is_designated_list(inner, &has_elem);
                    if (ok) {
                        size_t it = trim_right_len(inner, strlen(inner));
                        size_t h;
                        buf_putn(&b, rest, (size_t)(e - rest) + 1);     /* " = {" */
                        buf_putn(&b, inner, it);
                        buf_puts(&b, has_elem ? ", " : " ");
                        for (h = 0; h < (size_t)S->nu; h++) {
                            char low[MAX_NAME];
                            to_lower(S->use_t[h], low);
                            if (h) buf_puts(&b, ", ");
                            buf_puts(&b, ".__");
                            buf_puts(&b, low);
                            buf_puts(&b, "_vptr = &");
                            buf_puts(&b, S->name);
                            buf_putc(&b, '_');
                            buf_puts(&b, S->use_t[h]);
                            buf_puts(&b, "_vtable");
                        }
                        buf_putc(&b, ' ');
                        buf_puts(&b, close);                            /* "}...;" */
                        free(inner);
                        return b.p;
                    }
                    free(inner);
                }
            }
        }
    }

    buf_puts(&b, rest);
    return b.p;
}

static char *transform_line(const char *line)
{
    char *decl = try_var_decl(line);
    const char *base = decl ? decl : line;
    Buf out;
    char *res;

    buf_init(&out);
    transform_calls(base, &out);
    free(decl);
    res = out.p;
    return res;
}

static void emit_raw_line(size_t ls, size_t le)
{
    size_t len = le - ls, t = 0;
    char *line, *out;

    line = xstrndup(g_src + ls, len);
    while (t < len && (line[t] == ' ' || line[t] == '\t')) t++;
    if (t < len && line[t] == '#') {                 /* preprocessor: verbatim */
        fputs(line, g_out);
        free(line);
        return;
    }
    out = transform_line(line);
    fputs(out, g_out);
    free(out);
    free(line);
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

        if (word_at(q, "trait")) { pos = parse_trait(q); continue; }
        if (word_at(q, "impl"))  { pos = parse_impl(q);  continue; }
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
