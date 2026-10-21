#!/bin/sh
# ct installer — download a ct source archive from GitHub, bootstrap the
# compiler chain (L0 -> L1 -> L2 -> ct-ast) and install the `ct` entry.
#
#   curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh
#   ./install.sh --prefix "$HOME/bin" --version v0.12.0
#
# Requirements: a C compiler (`cc` or `$CC`) and `tar`; `curl` or `wget` for the
# download. Building from a local checkout (no download) works with:
#
#   CT_SOURCE_DIR=. ./install.sh
#
# License: GPL-3.0-or-later (this script); see LICENSE and LICENSE.EXCEPTION.

set -eu

repo=${CT_REPO:-samxxu/ct-lang}
ref=${CT_REF:-main}
prefix=${CT_PREFIX:-$HOME/.local/bin}
CC=${CC:-cc}

usage() {
    cat <<EOF
usage: install.sh [-p DIR] [-V REF] [-h]

  -p, --prefix DIR    install directory for the ct binary (default: $prefix)
  -V, --version REF   branch, tag or commit to build (default: $ref)
  -h, --help          show this message

environment:
  CC              C compiler to use (default: cc)
  CT_REPO         GitHub repository (default: $repo)
  CT_REF          same as --version
  CT_PREFIX       same as --prefix
  CT_SOURCE_DIR   build from this local checkout instead of downloading
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        -p|--prefix)  [ $# -ge 2 ] || { echo "install.sh: error: '$1' needs an argument" >&2; exit 1; }
                      prefix=$2; shift 2 ;;
        -V|--version) [ $# -ge 2 ] || { echo "install.sh: error: '$1' needs an argument" >&2; exit 1; }
                      ref=$2; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "install.sh: error: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'install.sh: warning: %s\n' "$*" >&2; }
die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/ct-install.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# --- 1. locate the source tree -------------------------------------------------

if [ -n "${CT_SOURCE_DIR:-}" ]; then
    src=$(cd "$CT_SOURCE_DIR" && pwd) || die "cannot enter '$CT_SOURCE_DIR'"
    say "using local source tree $src"
else
    command -v tar >/dev/null 2>&1 || die "'tar' is required"
    if command -v curl >/dev/null 2>&1; then
        fetch() { curl -fsSL --retry 2 --max-time 300 -o "$1" "$2"; }
    elif command -v wget >/dev/null 2>&1; then
        fetch() { wget -q -O "$1" "$2"; }
    else
        die "need 'curl' or 'wget' to download the source archive (or set CT_SOURCE_DIR)"
    fi

    url="https://github.com/$repo/archive/$ref.tar.gz"
    say "downloading $url"
    fetch "$work/src.tar.gz" "$url" || die "download failed: $url"
    mkdir -p "$work/src"
    tar -xzf "$work/src.tar.gz" -C "$work/src" || die "cannot unpack the archive"
    src=$(ls -d "$work/src"/*/ 2>/dev/null | head -1)
    [ -n "$src" ] || die "the archive has no top-level directory"
    src=${src%/}
    say "extracted to $src"
fi

# Two tree layouts exist: releases up to v0.12.0 keep the seed at the root and
# the later stages under selfhost/{ctc.ct,src,ast}; main moved them to
# selfhost/{l0,l1,l2,ct-ast} and needs -I for ct-ast's grouped imports.
if [ -f "$src/selfhost/l0/ctc.c" ]; then
    seed=selfhost/l0/ctc.c
    l1_src=selfhost/l1/ctc.ct
    l2_src=selfhost/l2/driver.ct
    ast_src=selfhost/ct-ast/main.ct
    ast_inc="-I selfhost/ct-ast"
elif [ -f "$src/ctc.c" ]; then
    seed=ctc.c
    l1_src=selfhost/ctc.ct
    l2_src=selfhost/src/driver.ct
    ast_src=selfhost/ast/main.ct
    ast_inc=""
else
    die "'$src' does not look like a ct source tree (no ctc.c)"
fi
[ -f "$l1_src" ] || die "this ref has no $l1_src"
[ -f "$l2_src" ] || die "this ref has no $l2_src (it predates the L2 split; install a newer tag)"

# --- 2. pick the C compiler flags ----------------------------------------------

command -v "$CC" >/dev/null 2>&1 || die "'$CC' not found; install a C compiler or set CC"

# GCC >= 8 warns about snprintf truncation in the frozen seeds; those reports are
# false positives, so silence that one class when the compiler accepts the flag.
cflags="-Wall -Wextra -std=c99"
printf 'int main(void) { return 0; }\n' > "$work/probe.c"
# shellcheck disable=SC2086
if "$CC" $cflags -Wno-format-truncation -c "$work/probe.c" -o "$work/probe.o" 2>/dev/null; then
    cflags="$cflags -Wno-format-truncation"
fi

say "compiler: $CC ($cflags)"

# --- 3. bootstrap L0 -> L1 -> L2 -> ct-ast -------------------------------------

cd "$src"

say "building L0 (the C seed)"
# shellcheck disable=SC2086
"$CC" $cflags "$seed" -o "$work/ctc" || die "L0 did not build"

say "building L1"
"$work/ctc" "$l1_src" -o "$work/l1.c" || die "L0 could not compile L1"
# shellcheck disable=SC2086
"$CC" $cflags "$work/l1.c" -o "$work/l1" || die "L1 did not build"

say "building L2 (the regression oracle)"
mkdir -p "$work/l2src"
"$work/l1" build "$l2_src" -o "$work/l2src" >"$work/l2.log" 2>&1 ||
    { cat "$work/l2.log" >&2; die "L1 could not build L2"; }
# shellcheck disable=SC2086
"$CC" $cflags "$work/l2src"/*.c -o "$work/l2" || die "L2 did not build"

if [ -f "$ast_src" ]; then
    say "building ct-ast (the installed entry)"
    mkdir -p "$work/astsrc"
    # shellcheck disable=SC2086
    "$work/l2" build $ast_inc "$ast_src" -o "$work/astsrc" >"$work/ast.log" 2>&1 ||
        { cat "$work/ast.log" >&2; die "L2 could not build ct-ast"; }
    # shellcheck disable=SC2086
    "$CC" $cflags "$work/astsrc"/*.c -o "$work/ct" || die "ct-ast did not build"
else
    warn "'$ast_src' is absent in this ref; installing L2 as the entry"
    cp "$work/l2" "$work/ct"
fi

# --- 4. install ----------------------------------------------------------------

mkdir -p "$prefix" || die "cannot create '$prefix'"
cp "$work/ct" "$prefix/ct" || die "cannot install into '$prefix'"
chmod 755 "$prefix/ct"
if [ -e "$prefix/ctc" ] && [ ! -L "$prefix/ctc" ]; then
    cp "$work/ct" "$prefix/ctc"
else
    ln -sf ct "$prefix/ctc"
fi

version=$("$prefix/ct" -v 2>&1) || die "the installed binary does not run"
say "installed $prefix/ct ($version) and $prefix/ctc"

case ":$PATH:" in
    *":$prefix:"*) ;;
    *) warn "'$prefix' is not on your PATH; add it with: export PATH=\"$prefix:\$PATH\"" ;;
esac

cat <<EOF

Next steps:
  ct -h                                  # usage
  ct examples/01_greeter/greeter.ct -o /tmp/greeter.c
  cc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter

Tutorial: https://github.com/$repo/blob/main/docs/tutorial.md
EOF
