#!/bin/sh
# ct installer — download a ct source archive from GitHub, build the bundled
# bootstrap seed (bootstrap/ct-ast, the C that ct-ast emits for itself) and
# install the `ct` entry.
#
#   curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh
#   ./install.sh --prefix "$HOME/bin" --version v1.0.0
#
# Requirements: a C compiler (`cc` or `$CC`) and `tar`; `curl` or `wget` for the
# download. Building from a local checkout (no download) works with:
#
#   CT_SOURCE_DIR=. ./install.sh
#
# The old L0 -> L1 -> L2 -> ct-ast walk is not part of installing any more
# (D-022): the seed is compiled directly, so an install needs no ct binary and
# no previous generation. L1/L2 stay in the tree as the regression oracle of
# gates 2/3/4/5, not as a build step here.
#
# License: GPL-3.0-or-later (this script); see LICENSE and LICENSE.EXCEPTION.
# The generated seed under bootstrap/ is not covered by the GPL (LICENSE.EXCEPTION).

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

seed="$src/bootstrap/ct-ast"
[ -d "$seed" ] || die "'$src' carries no bootstrap/ct-ast seed; this ref predates the v1.0 seed cutover (use its own install.sh)"
set -- "$seed"/*.c
[ -f "$1" ] || die "the seed directory has no C files: $seed"

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

# --- 3. build ct from the bundled seed ----------------------------------------

cd "$src"

say "building ct from the bundled seed (bootstrap/ct-ast)"
# shellcheck disable=SC2086
"$CC" $cflags -I "$seed" "$seed"/*.c -o "$work/ct" || die "the seed did not build"

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

# --- 5. standard library -------------------------------------------------------
# `std` is a normal ct-pkg package, not part of this repository or of the binary,
# so there is nothing to copy here. `ct get` writes it into the shared store and
# `ct build` reads the v2 lock, so the consumer passes no manual include root.
say "the standard library is a package; in your project run: ct get ct/std && ct build main.ct -o main"

case ":$PATH:" in
    *":$prefix:"*) ;;
    *) warn "'$prefix' is not on your PATH; add it with: export PATH=\"$prefix:\$PATH\"" ;;
esac

cat <<EOF

Next steps:
  ct -h                                  # usage
  ct build examples/01_greeter/greeter.ct -o /tmp/greeter
  /tmp/greeter

Standard library (a ct-pkg package, per project):
  ct get ct/std
  ct build main.ct -o main               # reads ct.lock and adds the store include root

Tutorial: https://github.com/$repo/blob/main/docs/tutorial.md
EOF
