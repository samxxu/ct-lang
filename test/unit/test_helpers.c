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

    /* ---- decl_end_is_bare ---- */
    eq_int("bare end ';'", decl_end_is_bare(";"), 1);
    eq_int("bare end ';   '", decl_end_is_bare(";   "), 1);
    eq_int("bare end '; // c'", decl_end_is_bare("; // c"), 1);
    eq_int("bare end '; /* c */'", decl_end_is_bare("; /* c */  "), 1);
    eq_int("bare end with init", decl_end_is_bare("= { 1 };"), 0);
    eq_int("bare end empty", decl_end_is_bare(""), 0);

    /* ---- put_own_vptr: one per used trait, in use order ---- */
    {
        Struct s;
        Buf b;
        int first = 1;
        snprintf(s.name, sizeof s.name, "Person");
        snprintf(s.cname, sizeof s.cname, "Person");
        snprintf(s.use_t[0], MAX_NAME, "Greeter");
        snprintf(s.use_t[1], MAX_NAME, "Counter");
        s.nu = 2;
        s.nf = 0;
        buf_init(&b);
        put_own_vptr(&b, &s, &first);
        eq_str("vptr designators", b.p,
               ".__greeter_vptr = &Person_Greeter_vtable, "
               ".__counter_vptr = &Person_Counter_vtable");
        free(b.p);
    }

    /* ---- nested construction: a struct-typed field gets its own statement ---- */
    {
        Buf b;
        g_nstructs = 2;
        snprintf(g_structs[0].name, MAX_NAME, "Person");
        snprintf(g_structs[0].cname, MAX_NAME, "Person");
        g_structs[0].nu = 1;
        snprintf(g_structs[0].use_t[0], MAX_NAME, "Greeter");
        g_structs[0].nf = 0;
        snprintf(g_structs[1].name, MAX_NAME, "Shop");
        snprintf(g_structs[1].cname, MAX_NAME, "Shop");
        g_structs[1].nu = 0;
        snprintf(g_structs[1].fname[0], MAX_NAME, "owner");
        g_structs[1].ftype[0] = 0;
        g_structs[1].nf = 1;
        eq_int("nested needs init", needs_nested_init(&g_structs[1], 0), 1);
        buf_init(&b);
        put_nested_assignments(&b, &g_structs[1], "s", "", 1, 0);
        eq_str("nested assignments", b.p,
               "s.owner.__greeter_vptr = &Person_Greeter_vtable;\n");
        free(b.p);
        g_nstructs = 0;
    }

    /* ---- is_stmt_keyword ---- */
    eq_int("stmt keyword if", is_stmt_keyword("if"), 1);
    eq_int("stmt keyword return", is_stmt_keyword("return"), 1);
    eq_int("stmt keyword void", is_stmt_keyword("void"), 0);

    /* ---- last_ident ---- */
    {
        size_t a, b;
        eq_int("last_ident found", last_ident("Person *q;", 10, &a, &b), 1);
        eq_int("last_ident start", (long)a, 8);
        eq_int("last_ident end", (long)b, 9);
        eq_int("last_ident none", last_ident("  * ", 4, &a, &b), 0);
    }

    /* ---- already_qualified ---- */
    eq_int("qualified struct", already_qualified("struct Person *", 7), 1);
    eq_int("qualified after prefix", already_qualified("static struct Person", 14), 1);
    eq_int("not qualified", already_qualified("static Person", 7), 0);

    /* ---- analyse_param (needs one known struct) ---- */
    g_nstructs = 1;
    snprintf(g_structs[0].name, MAX_NAME, "Person");
    snprintf(g_structs[0].cname, MAX_NAME, "Person");
    {
        char nm[MAX_NAME], cbase[MAX_NAME];
        int ia, ib, need_struct, ptr, tr;
        eq_int("param ptr idx", analyse_param("Person *q", 9, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr), 0);
        eq_int("param ptr insert", need_struct, 1);
        eq_int("param ptr ident start", ia, 0);
        eq_str("param ptr cbase", cbase, "Person");
        eq_str("param ptr name", nm, "q");
        eq_int("param ptr flag", ptr, 1);

        eq_int("param val idx", analyse_param("Person p", 8, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr), 0);
        eq_int("param val flag", ptr, 0);

        eq_int("param qualified idx", analyse_param("struct Person *q", 16, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr), 0);
        eq_int("param qualified no insert", need_struct, 0);

        eq_int("param scalar idx", analyse_param("int a", 5, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr), -1);
        eq_str("param scalar name", nm, "a");
        analyse_param("void", 4, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr);
        eq_int("param void unnamed", (long)strlen(nm), 0);

        /* a trait name in type position expands to "struct X_iface" */
        g_ntraits = 1;
        snprintf(g_traits[0].name, MAX_NAME, "Greeter");
        snprintf(g_traits[0].cname, MAX_NAME, "Greeter");
        g_traits[0].nm = 1;
        snprintf(g_traits[0].m[0].name, MAX_NAME, "greet");
        eq_int("param iface idx", analyse_param("Greeter g", 9, &ia, &ib, cbase, &need_struct, nm, &ptr, &tr), -1);
        eq_int("param iface trait", tr, 0);
        eq_int("param iface insert", need_struct, 1);
        eq_int("param iface ident end", ib, 7);
        {
            Buf b2;
            buf_init(&b2);
            emit_qualified_type(&b2, "Greeter g", 9, ia, ib, cbase, need_struct, tr >= 0);
            eq_str("param iface expansion", b2.p, "struct Greeter_iface g");
            free(b2.p);
        }
        g_ntraits = 0;
    }
    g_nstructs = 0;

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

    /* ---- read_ident copies the whole name; overflow is a hard error, not a
       silent truncation (see test/errors/ident_too_long.ct) ---- */
    {
        char big[64], nb[64];
        size_t z;
        for (z = 0; z < 50; z++) big[z] = 'a';
        big[50] = 0;
        g_src = big;
        g_len = strlen(g_src);
        eq_int("read_ident consumes the whole name", (long)read_ident(0, nb, sizeof nb), 50);
        eq_int("read_ident copies the whole name", (long)strlen(nb), 50);
    }

    /* ---- trim / trim_right_len edges ---- */
    snprintf(buf, sizeof buf, "");
    trim(buf);
    eq_str("trim empty", buf, "");
    snprintf(buf, sizeof buf, "   \t\n ");
    trim(buf);
    eq_str("trim all whitespace", buf, "");
    eq_int("trim_right_len none", (long)trim_right_len("abc", 3), 3);
    eq_int("trim_right_len all", (long)trim_right_len("   ", 3), 0);

    /* ---- to_lower: folds letters, keeps non-letters ---- */
    to_lower("ABC-1_x", buf);
    eq_str("to_lower mixed", buf, "abc-1_x");

    /* ---- is_type_keyword: more members and a negative ---- */
    eq_int("is_type_keyword unsigned", is_type_keyword("unsigned"), 1);
    eq_int("is_type_keyword const", is_type_keyword("const"), 1);
    eq_int("is_type_keyword uint8_t", is_type_keyword("uint8_t"), 1);
    eq_int("is_type_keyword Person", is_type_keyword("Person"), 0);

    /* ---- param_type_only: pointers and qualified types ---- */
    param_type_only("int*", buf);
    eq_str("ptype int* (no name)", buf, "int*");
    param_type_only("struct Person *p", buf);
    eq_str("ptype struct Person *p", buf, "struct Person *");
    param_type_only("int", buf);
    eq_str("ptype bare keyword", buf, "int");

    /* ---- decl_end_is_bare: more shapes ---- */
    eq_int("bare end '= 0;'", decl_end_is_bare("= 0;"), 0);
    eq_int("bare end '; // c\\n'", decl_end_is_bare("; // c\n"), 1);
    eq_int("bare end ';/*c*/'", decl_end_is_bare(";/*c*/"), 1);
    eq_int("bare end '; x'", decl_end_is_bare("; x"), 0);
    eq_int("bare end spaces", decl_end_is_bare("   "), 0);

    /* ---- last_ident: name at offset 0 / trailing punctuation ---- */
    {
        size_t a, b;
        eq_int("last_ident at start", last_ident("foo", 3, &a, &b), 1);
        eq_int("last_ident at start a", (long)a, 0);
        eq_int("last_ident at start b", (long)b, 3);
        eq_int("last_ident trailing ')'", last_ident("call(x)", 7, &a, &b), 1);
        eq_int("last_ident trailing ')' a", (long)a, 5);
        eq_int("last_ident trailing ')' b", (long)b, 6);
        eq_int("last_ident only punctuation", last_ident("(*)", 3, &a, &b), 0);
    }

    /* ---- copy_ident: copies the whole name and reports its length ---- */
    {
        char nb[MAX_NAME];
        eq_int("copy_ident len", (long)copy_ident("abc ", nb, 0), 3);
        eq_str("copy_ident text", nb, "abc");
        eq_int("copy_ident empty", (long)copy_ident(" x", nb, 0), 0);
    }

    /* ---- read_qual_ref: plain, qualified and namespace-prefixed names ---- */
    {
        char cname[MAX_NAME], shortname[MAX_NAME];
        const char *rest;
        int qual;

        snprintf(g_ns, sizeof g_ns, "");
        rest = read_qual_ref("Person x", cname, shortname, &qual);
        eq_str("rqr plain cname", cname, "Person");
        eq_str("rqr plain short", shortname, "Person");
        eq_int("rqr plain qual", qual, 0);
        eq_str("rqr plain rest", rest, " x");

        rest = read_qual_ref("A::B::Person x", cname, shortname, &qual);
        eq_str("rqr qualified cname", cname, "A_B_Person");
        eq_str("rqr qualified short", shortname, "Person");
        eq_int("rqr qualified qual", qual, 1);
        eq_str("rqr qualified rest", rest, " x");

        snprintf(g_ns, sizeof g_ns, "NS_");
        read_qual_ref("Person", cname, shortname, &qual);
        eq_str("rqr namespace prefix", cname, "NS_Person");
        snprintf(g_ns, sizeof g_ns, "");

        eq_int("rqr no name", read_qual_ref("  x", cname, shortname, &qual) == NULL, 1);
    }

    /* ---- skip_literal: escapes and the closing quote ---- */
    g_src = "\"ab\" x";
    g_len = strlen(g_src);
    eq_int("skip_literal plain", (long)skip_literal(0), 4);
    g_src = "\"a\\\"b\"";
    g_len = strlen(g_src);
    eq_int("skip_literal escaped quote", (long)skip_literal(0), 6);

    /* ---- line_match_paren / line_literal_end ---- */
    eq_int("line_match_paren plain", (long)line_match_paren("f(a, b)", 1, 7), 6);
    eq_int("line_match_paren skips literal", (long)line_match_paren("f(\")\")", 1, 6), 5);
    eq_int("line_match_paren nested", (long)line_match_paren("f(g(x))", 1, 7), 6);
    eq_int("line_literal_end", (long)line_literal_end("\"ab\"", 0, 4), 4);

    /* ---- trait_has_method / struct_uses ---- */
    {
        Trait t;
        Struct s;
        snprintf(t.name, MAX_NAME, "Greeter");
        snprintf(t.cname, MAX_NAME, "Greeter");
        t.nm = 2;
        snprintf(t.m[0].name, MAX_NAME, "greet");
        snprintf(t.m[1].name, MAX_NAME, "add");
        eq_int("trait_has_method yes", trait_has_method(&t, "greet"), 1);
        eq_int("trait_has_method no", trait_has_method(&t, "nope"), 0);

        snprintf(s.name, MAX_NAME, "Person");
        snprintf(s.cname, MAX_NAME, "Person");
        s.nu = 1;
        snprintf(s.use_t[0], MAX_NAME, "Greeter");
        eq_int("struct_uses yes", struct_uses(&s, "Greeter"), 1);
        eq_int("struct_uses no", struct_uses(&s, "Counter"), 0);
    }

    /* ---- new_var / find_var ---- */
    {
        int i0, i1;
        g_nvars = 0;
        i0 = new_var();
        snprintf(g_vars[i0].name, MAX_NAME, "alpha");
        i1 = new_var();
        snprintf(g_vars[i1].name, MAX_NAME, "beta");
        eq_int("new_var increments", i1, i0 + 1);
        eq_int("find_var hit", find_var("beta"), i1);
        eq_int("find_var miss", find_var("gamma"), -1);
        g_nvars = 0;
    }

    printf("unit: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
