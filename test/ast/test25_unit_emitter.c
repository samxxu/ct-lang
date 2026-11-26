/*
 * TEST-25: white-box unit tests for the Emitter slice functions.
 *
 * `em_expr_num` is one of the PH-88 per-kind emitter slices;
 * `backend_emit_map_clean_type_text` and `backend_emit_map_recipe_callee_text`
 * are the pool-text helpers the static-map path uses (SH-94 S1 moved them to
 * EmitterMapText; S1a-0 C2p-8 removed their fixed 160-byte output rows);
 * `em_expr_num` is still
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
    /* S1a-0 C2p-8: the helper answers a pool text instead of filling a row. */
    eq_str("map_clean_type array", backend_emit_map_clean_type_text("char a[32]"), "char a");
    eq_str("map_clean_type trailing blanks", backend_emit_map_clean_type_text("int  [3]"), "int");
    eq_str("map_clean_type plain", backend_emit_map_clean_type_text("struct Point"), "struct Point");

    /* ---- map_recipe_callee: the leading identifier of a recipe ---- */
    eq_str("map_recipe_callee leading space", backend_emit_map_recipe_callee_text("  atoi(s)"), "atoi");
    eq_str("map_recipe_callee underscores", backend_emit_map_recipe_callee_text("snprintf(dst, n)"), "snprintf");
    eq_str("map_recipe_callee non-identifier", backend_emit_map_recipe_callee_text("(nan)"), "");

    fclose(em.out);
    printf("unit-emitter: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
