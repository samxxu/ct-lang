#ifndef UNITS_SHIM_H
#define UNITS_SHIM_H

// 纯头文件 shim：全部 static inline，不产生外部符号，
// 所以这个样例不需要任何 .shim.c，也不会在链接期引入额外文件。
static inline int units_f(int c) { return c * 9 / 5 + 32; }

static inline int units_ft(int m) { return m * 3281 / 1000; }

static inline int units_words(char *s) {
    int n = 0;
    int in_word = 0;

    while (*s != '\0') {
        if (*s == ' ') {
            in_word = 0;
        } else if (in_word == 0) {
            in_word = 1;
            n = n + 1;
        }
        s = s + 1;
    }
    return n;
}

#endif
