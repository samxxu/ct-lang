/*
 * TEST-25: white-box unit tests for the Expr slice functions.
 *
 * The parser's `ctype_*` slices are `pub` in the emitted `ExprStaticType.c`
 * after the SH-94 split, so this file includes that translation unit (the L0
 * test/unit recipe). The four helpers exercised here are the pure ones: they read one arena node's text
 * and write a C spelling, with no symbol table or lexer behind them.
 *
 * Run via test/ast/test25_unit.sh (which passes the generated source tree).
 */

#include <stdio.h>
#include <string.h>

#include "ExprStaticType.c"

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
    struct frontend_parse_Expr ex;
    char out[256];
    int depth = 0;

    memset(&arena, 0, sizeof arena);
    memset(nodes, 0, sizeof nodes);
    arena.nodes = nodes;
    arena.nnode = 8;

    /* S1a-0 C2n-2: a Node row is an intern pool pointer now. The harness
       builds nodes by hand, so every row starts on the empty text (the
       zero-filled array used to spell that; a NULL pointer would crash a
       read). */
    {
        int init_i;
        for (init_i = 0; init_i < 8; init_i++) {
            nodes[init_i].text = "";
            nodes[init_i].text2 = "";
            nodes[init_i].text3 = "";
            nodes[init_i].text4 = "";
        }
    }
    memset(&ex, 0, sizeof ex);
    ex.arena = &arena;

    /* ---- ctype_adtctor: an ADT constructor spells the struct tag ---- */
    nodes[0].text = "Shape";
    eq_int("ctype_adtctor returns 1", frontend_parse_ctype_adtctor(&ex, 0, out, sizeof out, &depth, 0), 1);
    eq_str("ctype_adtctor spelling", out, "struct Shape");

    /* ---- ctype_opt: the parse-time optional result is copied through ---- */
    nodes[1].text2 = "int";
    eq_int("ctype_opt returns 1", frontend_parse_ctype_opt(&ex, 1, out, sizeof out, &depth, 0), 1);
    eq_str("ctype_opt spelling", out, "int");
    eq_int("ctype_opt absent", frontend_parse_ctype_opt(&ex, 2, out, sizeof out, &depth, 0), 0);

    /* ---- ctype_slice_get: the element spelling plus a pointer star ---- */
    nodes[3].text = "char";
    eq_int("ctype_slice_get returns 1", frontend_parse_ctype_slice_get(&ex, 3, out, sizeof out, &depth, 0), 1);
    eq_str("ctype_slice_get spelling", out, "char *");
    eq_int("ctype_slice_get absent", frontend_parse_ctype_slice_get(&ex, 4, out, sizeof out, &depth, 0), 0);

    /* ---- ctype_slice_range: every subslice erases to the slice struct ---- */
    eq_int("ctype_slice_range returns 1", frontend_parse_ctype_slice_range(&ex, 5, out, sizeof out, &depth, 0), 1);
    eq_str("ctype_slice_range spelling", out, "struct __ct_slice");

    printf("unit-expr: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
