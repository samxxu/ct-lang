#ifndef FIELDS_SHIM_H
#define FIELDS_SHIM_H

// 宏与 static inline 混用：宏只在本头里可见，不污染调用方的命名空间。
#define CSV_SEED 7
#define CSV_MOD 1000

static inline int csv_width(char *s) {
    int n = 0;

    while (s[n] != '\0') {
        n = n + 1;
    }
    return n;
}

static inline int csv_hash(char *s) {
    int h = CSV_SEED;

    while (*s != '\0') {
        h = (h * 31 + *s) % CSV_MOD;
        s = s + 1;
    }
    return h;
}

#endif
