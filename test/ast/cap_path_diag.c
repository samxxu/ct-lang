/*
 * cap_path_diag.c - S1a-0 C2l white-box probe: `Warn.file` keeps a 1500-byte
 * logical unit path whole.
 *
 * ct-ast's `struct Warn.file` used to be `char file[MAX_PATH]` (1024): a
 * diagnostic about a unit whose path is longer than 1023 bytes named a
 * truncated file. The probe records one signature warning with a 1500-byte
 * path and emits the text form; the shell test reads the line back. It links
 * the generated Diag.c and only calls its public primitives, so the same
 * source compiles against the old and the new compiler (the old one loses the
 * tail, which is the failure the test records).
 */
#include <stdio.h>
#include <string.h>

#include "Diag.h"

int main(void)
{
    static char path[1501];
    size_t i;

    for (i = 0; i < 1500; i++) path[i] = 'p';
    path[1500] = 0;
    if (tool_diag_ct_sig_warn(1, 1, "m", "t", "s", "msg", path) != 0) {
        fprintf(stderr, "FAIL diag: the record was rejected\n");
        return 1;
    }
    /*
     * A short path too: the probe must show the exact bytes, not a prefix of
     * the long one (the block is per record).
     */
    if (tool_diag_ct_sig_warn(2, 2, "m", "t", "s", "msg", "a/b.ct") != 0) {
        fprintf(stderr, "FAIL diag: the short record was rejected\n");
        return 1;
    }
    if (tool_diag_ct_diag_emit(0, 1) != 0) {
        fprintf(stderr, "FAIL diag: text emit failed\n");
        return 1;
    }
    return 0;
}
