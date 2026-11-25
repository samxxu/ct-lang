#!/bin/sh
# S1a-0 C2m: the whole path chain over the old 1024-byte MAX_PATH on a host
# where such a real path can exist.
#
# Darwin caps a path at 1024 bytes (PATH_MAX), so this case is skipped there
# and runs on Linux CI, whose PATH_MAX is 4096. `CAP_PATH_MIN` overrides the
# depth so the same body can be exercised on a small path locally.
#
# It covers, with real files:
#   - a >1024-byte source path: `Diag.file` / the build's warning line names it
#     whole (a `char file[1024]` cut it);
#   - the cache key under a >1024-byte output directory (`Cache.paths` used two
#     `char[MAX_PATH]` buffers and silently disabled the cache);
#   - a >1024-byte import candidate (`resolve_import` / `ct_root_find`);
#   - a >1024-byte `-o` in compile mode, through `Emitter.write_header`;
#   - `ct check` on an import-bearing unit under a long `-I` root (the whole
#     Unit / Module / Driver path).
#
# Usage: sh test/ast/cap_path_real.sh <ct-ast>
set -u
ct=${1:?usage: cap_path_real.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
min=${CAP_PATH_MIN:-1100}
if [ "$(uname -s)" = "Darwin" ] && [ -z "${CAP_PATH_MIN:-}" ]; then
    echo "skip cap_path_real: Darwin PATH_MAX is 1024 (Linux CI runs the real path)"
    exit 0
fi
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/cappathreal.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}
fail=0
comp=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd

# A nested real directory whose own path is over `min` bytes; each component
# stays under NAME_MAX.
d="$w/deep"
mkdir -p "$d" || exit 1
while [ ${#d} -lt "$((min + 40))" ]; do
    d="$d/$comp"
    mkdir -p "$d" || exit 1
done

src="$d/prog.ct"
printf 'int f(int a[]) { return a[0]; }\nint main(void) { return 0; }\n' >"$src"
out="$d/out"
mkdir -p "$out" || exit 1

# 1) A warning line names the >min-byte source path whole.
if ! "$ct" build --emit-c --check-level=warn "$src" -o "$out" >"$w/b.log" 2>&1; then
    echo "FAIL real: the build rejected a ${#src}-byte source path: $(tail -1 "$w/b.log")"
    fail=1
elif grep -Fq "$src" "$w/b.log"; then
    echo "ok   real source path (${#src} bytes named whole in a warning)"
else
    echo "FAIL real: the warning truncated the ${#src}-byte source path"
    fail=1
fi

# 2) The cache key path is composed under the >min-byte output directory.
kf="$out/.ctcache/prog.c.key"
if [ ! -f "$kf" ]; then
    echo "FAIL real: no cache key under a ${#out}-byte output directory"
    fail=1
else
    klen=$(wc -c <"$kf" | tr -d ' ')
    if [ "$klen" -gt "$min" ]; then
        echo "ok   real cache key ($klen bytes under a ${#out}-byte outdir)"
    else
        echo "FAIL real: the cache key is $klen bytes (want > $min)"
        fail=1
    fi
fi

# 3) A >min-byte import candidate resolves through a long `-I` root.
printf 'pub int u(void) { return 7; }\n' >"$d/u.h.ct"
mkdir -p "$w/top" || exit 1
printf 'import u;\nint main(void) { return u() == 7 ? 0 : 1; }\n' >"$w/top/main.ct"
out2="$d/out2"
mkdir -p "$out2" || exit 1
if "$ct" build --emit-c -I "$d" "$w/top/main.ct" -o "$out2" >"$w/i.log" 2>&1; then
    echo "ok   real import candidate (${#d}/u.h.ct)"
else
    echo "FAIL real: a ${#d}-byte import root did not resolve: $(tail -1 "$w/i.log")"
    fail=1
fi

# 4) Compile mode writes the `.h` next to a >min-byte `-o` (Emitter.write_header).
hp="$d/deep.h.ct"
printf 'pub int g(void);\n' >"$hp"
if "$ct" "$hp" -o "$out/compiled.c" >"$w/c.log" 2>&1 && [ -f "$out/compiled.h" ]; then
    echo "ok   real compile -o (header beside a ${#out}-byte output path)"
else
    echo "FAIL real: compile mode did not write the header: $(tail -1 "$w/c.log")"
    fail=1
fi

# 5) `ct check` on an import-bearing unit under the long root takes the build
#    branch and its `-I <dir>` is the full >min-byte path.
printf 'import u;\nint main(void) { return 0; }\n' >"$d/chk.ct"
if "$ct" check "$d/chk.ct" >"$w/k.log" 2>&1; then
    echo "ok   real ct check (import-bearing unit under a ${#d}-byte path)"
else
    echo "FAIL real: ct check failed on a ${#d}-byte unit: $(tail -1 "$w/k.log")"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "cap_path_real: OK (${#src}-byte source, ${#out}-byte output)"
    exit 0
fi
echo "cap_path_real: FAIL"
exit 1
