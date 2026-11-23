/*
 * TEST-25: white-box unit tests for the Emitter slice functions.
 *
 * `em_expr_num` is one of the PH-88 per-kind emitter slices; `map_clean_type`
 * and `map_recipe_callee` are the pure string helpers the static-map path
 * uses. All three are `static` in the emitted `Emitter.c`, so this file
 * includes that translation unit (the L0 test/unit recipe). The harness only
 * touches the two fields each helper reads (`arena`, `out`), never the build
 * driver.
 *
 * Run via test/ast/test25_unit.sh (which passes the generated source tree).
 */

#include <stdio.h>
#include <string.h>

#include "Emitter.c"

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

int main(void)
{
    struct runtime_arena_Arena arena;
    struct runtime_arena_Node nodes[4];
    struct backend_emit_Emitter em;
    char out[256];
    char line[256];

    memset(&arena, 0, sizeof arena);
    memset(nodes, 0, sizeof nodes);
    arena.nodes = nodes;
    arena.nnode = 4;
    em = g_emit;
    em.arena = &arena;
    em.out = tmpfile();
    if (!em.out) {
        printf("  FAIL could not open a temporary sink\n");
        return 1;
    }

    /* ---- em_expr_num: value followed by the normalised suffix ---- */
    nodes[0].num = 42;
    snprintf(nodes[0].text, sizeof nodes[0].text, "UL");
    if (em_expr_num(&em, 0, 0) != 0) {
        printf("  FAIL em_expr_num returned non-zero\n");
        g_failed++;
    } else {
        g_checks++;
        rewind(em.out);
        if (!fgets(line, sizeof line, em.out)) line[0] = 0;
        eq_str("em_expr_num", line, "42UL");
    }

    /* ---- map_clean_type: drop the array dimensions and trailing blanks ---- */
    map_clean_type("char a[32]", out);
    eq_str("map_clean_type array", out, "char a");
    map_clean_type("int  [3]", out);
    eq_str("map_clean_type trailing blanks", out, "int");
    map_clean_type("struct Point", out);
    eq_str("map_clean_type plain", out, "struct Point");

    /* ---- map_recipe_callee: the leading identifier of a recipe ---- */
    map_recipe_callee("  atoi(s)", out);
    eq_str("map_recipe_callee leading space", out, "atoi");
    map_recipe_callee("snprintf(dst, n)", out);
    eq_str("map_recipe_callee underscores", out, "snprintf");
    map_recipe_callee("(nan)", out);
    eq_str("map_recipe_callee non-identifier", out, "");

    fclose(em.out);
    printf("unit-emitter: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
