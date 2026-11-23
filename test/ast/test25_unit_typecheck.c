/*
 * TEST-25: white-box unit tests for the TypeCheck slice functions.
 *
 * ct-ast is Ct source and its slice helpers are `static` inside one emitted
 * unit, so the only way to reach them is the L0 recipe: include the generated
 * translation unit itself. `selfhost/check-ast.sh` builds the C tree first and
 * `test/ast/test25_unit.sh` compiles this file with that tree on `-I`, linking
 * every other unit normally (the included one is omitted from the objects).
 *
 * The three helpers below are the pilot named by TEST-25 (`tc_expr_*` and the
 * shared type key): each is a pure function of one arena node, except
 * `type_key`, which is already `pub` and is here as the spelling oracle the
 * whole type layer compares with.
 *
 * Run directly (from the repo root, after a ct-ast build):
 *   cc -Wall -Wextra -std=c99 -I <generated-src> test/ast/test25_unit_typecheck.c \
 *      the generated-src objects ... (minus TypeCheck.c and main.c)
 *
 * no gtest, no framework: the same `checks / failed` shape as test/unit.
 */

#include <stdio.h>
#include <string.h>

#include "TypeCheck.c"

static int g_checks;
static int g_failed;

static void eq_str(const char *what, const char *got, const char *want)
{
    g_checks++;
    if (strcmp(got, want) != 0) {
        g_failed++;
        printf("  FAIL %s: got \"%s\", want \"%s\"\n", what, got, want);
    }
}

static void eq_int(const char *what, long got, long want)
{
    g_checks++;
    if (got != want) {
        g_failed++;
        printf("  FAIL %s: got %ld, want %ld\n", what, got, want);
    }
}

int main(void)
{
    struct runtime_arena_Arena arena;
    struct runtime_arena_Node nodes[8];
    struct frontend_type_TypeCheck tc;
    char out[256];

    memset(&arena, 0, sizeof arena);
    memset(nodes, 0, sizeof nodes);
    arena.nodes = nodes;
    arena.nnode = 8;
    memset(&tc, 0, sizeof tc);
    tc.arena = &arena;

    /* ---- tc_expr_num: the normalised suffix picks the C type ---- */
    snprintf(nodes[0].text, sizeof nodes[0].text, "");
    tc_expr_num(&tc, 0, out, sizeof out);
    eq_str("tc_expr_num no suffix", out, "int");
    snprintf(nodes[1].text, sizeof nodes[1].text, "U");
    tc_expr_num(&tc, 1, out, sizeof out);
    eq_str("tc_expr_num U", out, "unsigned");
    snprintf(nodes[2].text, sizeof nodes[2].text, "L");
    tc_expr_num(&tc, 2, out, sizeof out);
    eq_str("tc_expr_num L", out, "long");
    snprintf(nodes[3].text, sizeof nodes[3].text, "UL");
    tc_expr_num(&tc, 3, out, sizeof out);
    eq_str("tc_expr_num UL", out, "unsigned long");
    snprintf(nodes[4].text, sizeof nodes[4].text, "LL");
    tc_expr_num(&tc, 4, out, sizeof out);
    eq_str("tc_expr_num LL", out, "long long");
    snprintf(nodes[5].text, sizeof nodes[5].text, "ULL");
    tc_expr_num(&tc, 5, out, sizeof out);
    eq_str("tc_expr_num ULL", out, "unsigned long long");
    /* the buffer is bounded: a cap that cannot hold "unsigned long" refuses */
    eq_int("tc_expr_num cap", tc_expr_num(&tc, 3, out, 4), -1);

    /* ---- tc_expr_fnum: the literal's suffix picks the float type ---- */
    snprintf(nodes[0].text, sizeof nodes[0].text, "1.5");
    tc_expr_fnum(&tc, 0, out, sizeof out);
    eq_str("tc_expr_fnum plain", out, "double");
    snprintf(nodes[1].text, sizeof nodes[1].text, "1.5f");
    tc_expr_fnum(&tc, 1, out, sizeof out);
    eq_str("tc_expr_fnum f", out, "float");
    snprintf(nodes[2].text, sizeof nodes[2].text, "1.5L");
    tc_expr_fnum(&tc, 2, out, sizeof out);
    eq_str("tc_expr_fnum L", out, "long double");

    /* ---- type_key: one canonical spelling for the type-host lookup ---- */
    frontend_type_type_key("const char *", out, sizeof out);
    eq_str("type_key const char *", out, "char*");
    frontend_type_type_key("unsigned int", out, sizeof out);
    eq_str("type_key unsigned int", out, "unsigned");
    frontend_type_type_key("long int", out, sizeof out);
    eq_str("type_key long int", out, "long");
    frontend_type_type_key("const volatile int", out, sizeof out);
    eq_str("type_key const volatile", out, "int");
    frontend_type_type_key("struct  Foo *", out, sizeof out);
    eq_str("type_key collapses whitespace", out, "structFoo*");

    printf("unit-typecheck: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
