/* Phase 34 S3a (TEST-18): a hand-written dirty instance body. The module scan
   must report the leaked `T`, otherwise a real leak in a module product would
   pass silently. The shape matches the emitter: `__ctN(` and `{` on one line,
   the closing brace at column zero. */
static int id__ct1(int x) {
    T y = x;
    return y;
}
