/*
 * White-box unit tests for ctc's pure helpers.
 *
 * ctc.c is a single translation unit whose internals are all static, so the
 * only way to reach them is to include the source itself. Its main() is
 * renamed so that it does not collide with the test runner's own main().
 *
 * Run via test/run.sh, or directly:
 *   cc -Wall -Wextra -std=c99 test/unit/test_helpers.c -o /tmp/unit && /tmp/unit
 */

#define main ctc_main_unused_in_tests
#include "../../ctc.c"
#undef main

static int g_checks;
static int g_failed;

static void eq_int(const char *what, long got, long want)
{
    g_checks++;
    if (got != want) {
        g_failed++;
        printf("  FAIL %s: got %ld, want %ld\n", what, got, want);
    }
}

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
    char buf[256];
    Method m;
    int has;

    /* ---- trim / trim_right_len / to_lower ---- */
    snprintf(buf, sizeof buf, "  a b\t ");
    trim(buf);
    eq_str("trim strips both ends", buf, "a b");
    eq_int("trim_right_len", (long)trim_right_len("abc   ", 6), 3);
    to_lower("Greeter", buf);
    eq_str("to_lower", buf, "greeter");

    /* ---- is_type_keyword ---- */
    eq_int("is_type_keyword int", is_type_keyword("int"), 1);
    eq_int("is_type_keyword size_t", is_type_keyword("size_t"), 1);
    eq_int("is_type_keyword name", is_type_keyword("name"), 0);

    /* ---- param_type_only: drop the name, keep the type ---- */
    param_type_only("int a", buf);
    eq_str("ptype int a", buf, "int");
    param_type_only("char *name", buf);
    eq_str("ptype char *name", buf, "char *");
    param_type_only("const char *s", buf);
    eq_str("ptype const char *s", buf, "const char *");
    param_type_only("unsigned int", buf);
    eq_str("ptype unsigned int (keyword kept)", buf, "unsigned int");
    param_type_only("size_t", buf);
    eq_str("ptype size_t (keyword kept)", buf, "size_t");

    /* ---- parse_params ---- */
    parse_params(&m, "");
    eq_int("parse_params empty", m.nparams, 0);
    parse_params(&m, "void");
    eq_int("parse_params void", m.nparams, 0);
    parse_params(&m, "int a, char *b");
    eq_int("parse_params count", m.nparams, 2);
    eq_str("parse_params verbatim", m.params, "int a, char *b");
    eq_str("parse_params type 0", m.ptypes[0], "int");
    eq_str("parse_params type 1", m.ptypes[1], "char *");

    /* ---- split_decl ---- */
    split_decl("int add(int a, int b)", 0, &m);
    eq_str("split_decl ret", m.ret, "int");
    eq_str("split_decl name", m.name, "add");
    eq_int("split_decl nparams", m.nparams, 2);
    split_decl("char *dup(void)", 0, &m);
    eq_str("split_decl ret ptr", m.ret, "char *");
    eq_str("split_decl name ptr", m.name, "dup");
    eq_int("split_decl nparams void", m.nparams, 0);

    /* ---- is_designated_list ---- */
    eq_int("designated empty", is_designated_list("   ", &has), 1);
    eq_int("designated empty flag", has, 0);
    eq_int("designated all", is_designated_list(" .a = 1, .b = 2 ", &has), 1);
    eq_int("designated all flag", has, 1);
    eq_int("designated comma inside string", is_designated_list(" .a = \"x,y\", .b = 2 ", &has), 1);
    eq_int("designated positional", is_designated_list(" 1, 2 ", &has), 0);
    eq_int("designated mixed", is_designated_list(" .a = 1, 2 ", &has), 0);

    /* ---- word_at: word boundaries, not bare substring matching ---- */
    g_src = "struct Person {";
    g_len = strlen(g_src);
    eq_int("word_at struct", word_at(0, "struct"), 1);
    eq_int("word_at structx", word_at(0, "structx"), 0);
    eq_int("word_at Person", word_at(7, "Person"), 1);
    eq_int("word_at absent", word_at(0, "trait"), 0);

    /* ---- match_delim: braces inside literals/comments must not count ---- */
    g_src = "{\n  a;\n}";
    g_len = strlen(g_src);
    eq_int("match_delim plain", (long)match_delim(0, '{', '}'), (long)(g_len - 1));

    g_src = "{ \"}\" }";
    g_len = strlen(g_src);
    eq_int("match_delim skips literal", (long)match_delim(0, '{', '}'), 6);

    g_src = "{ /* } */ }";
    g_len = strlen(g_src);
    eq_int("match_delim skips comment", (long)match_delim(0, '{', '}'), (long)(g_len - 1));

    /* ---- skip_ws_comments / read_ident ---- */
    g_src = "  /* x */ abc";
    g_len = strlen(g_src);
    eq_int("skip_ws_comments", (long)skip_ws_comments(0), 10);
    eq_int("read_ident end", (long)read_ident(10, buf, sizeof buf), 13);
    eq_str("read_ident text", buf, "abc");

    printf("unit: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
