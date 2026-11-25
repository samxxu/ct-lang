/*
 * TEST-25: white-box unit tests for the Emitter slice functions.
 *
 * `em_expr_num` is one of the PH-88 per-kind emitter slices; `backend_emit_map_clean_type`
 * and `backend_emit_map_recipe_callee` are the pure string helpers the static-map
 * path uses (SH-94 S1 moved them to EmitterMapText); `em_expr_num` is still
 * `static` in the emitted `Emitter.c`, so this file
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

    /* S1a-0 C2n-2: a Node row is an intern pool pointer now. The harness
       builds nodes by hand, so every row starts on the empty text (the
       zero-filled array used to spell that; a NULL pointer would crash a
       read). */
    {
        int init_i;
        for (init_i = 0; init_i < 4; init_i++) {
            nodes[init_i].text = "";
            nodes[init_i].text2 = "";
            nodes[init_i].text3 = "";
            nodes[init_i].text4 = "";
        }
    }
    /* The shipped emitter namespaces the global (`backend_emit_g_emit`); the
     * L2-era spelling `g_emit` no longer exists in the frozen seed's C. */
    em = backend_emit_g_emit;
    em.arena = &arena;
    em.out = tmpfile();
    if (!em.out) {
        printf("  FAIL could not open a temporary sink\n");
        return 1;
    }

    /* ---- em_expr_num: value followed by the normalised suffix ---- */
    nodes[0].num = 42;
    nodes[0].text = "UL";
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
    backend_emit_map_clean_type("char a[32]", out);
    eq_str("map_clean_type array", out, "char a");
    backend_emit_map_clean_type("int  [3]", out);
    eq_str("map_clean_type trailing blanks", out, "int");
    backend_emit_map_clean_type("struct Point", out);
    eq_str("map_clean_type plain", out, "struct Point");

    /* ---- map_recipe_callee: the leading identifier of a recipe ---- */
    backend_emit_map_recipe_callee("  atoi(s)", out);
    eq_str("map_recipe_callee leading space", out, "atoi");
    backend_emit_map_recipe_callee("snprintf(dst, n)", out);
    eq_str("map_recipe_callee underscores", out, "snprintf");
    backend_emit_map_recipe_callee("(nan)", out);
    eq_str("map_recipe_callee non-identifier", out, "");

    fclose(em.out);
    printf("unit-emitter: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
