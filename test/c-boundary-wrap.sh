#!/usr/bin/env bash
# v1-PH-2 S9 M4: add the explicit C-boundary allow for registered C-interop
# fixtures only. The default stays strict; `test/c-boundary-allow.tsv` is the
# one registry and every row carries the reason it is a C-interop exception.
#
# The harnesses build the compiler in a temp dir; `make-ct-ast-wrapper.sh`
# puts this script in front of it, so a fixture keeps its explicit CLI allow
# even when a probe invokes the compiler indirectly. `CT_C_BOUNDARY` and an
# explicit `--c-boundary` always win (the p65 probes rely on that).
#
# Usage: c-boundary-wrap.sh <real-ct-ast> [ct-ast args...]
set -u

real=${1:?usage: c-boundary-wrap.sh <real-ct-ast> [args...]}
shift

root=$(cd -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
list="$root/test/c-boundary-allow.tsv"

listed() {
    local arg=$1 path rel
    case "$arg" in
        *.ct|*.h.ct) ;;
        *) return 1 ;;
    esac
    case "$arg" in
        /*) path=$arg ;;
        *) path=$PWD/$arg ;;
    esac
    path=$(cd -- "$(dirname -- "$path")" 2>/dev/null && pwd -P)/$(basename -- "$path") || return 1
    case "$path" in
        "$root"/*) rel=${path#"$root"/} ;;
        *) return 1 ;;
    esac
    awk -F'\t' -v k="$rel" '
        /^#/ { next }
        $1 == k { found = 1; exit }
        END { exit !found }
    ' "$list"
}

allow=0
if [ -z "${CT_C_BOUNDARY:-}" ]; then
    for a in "$@"; do
        if listed "$a"; then allow=1; break; fi
        # The public gates copy pre-PH-65 probe fixtures into a temp dir; those
        # temporary copies are not repo corpus and keep their historical allow.
        # The p65/p66 strict probes set CT_STRICT_BOUNDARY=1 so this branch
        # cannot hide the default they test.
        if [ "${CT_HARNESS_TEMP_ALLOW:-0}" = 1 ] && [ -z "${CT_STRICT_BOUNDARY:-}" ]; then
            case "$a" in
                *.ct|*.h.ct)
                    case "$a" in
                        /*) tp=$a ;;
                        *) tp=$PWD/$a ;;
                    esac
                    case "$tp" in
                        "$root"/*) ;;
                        *) allow=1; break ;;
                    esac
                    ;;
            esac
        fi
    done
fi
for a in "$@"; do
    case "$a" in
        --c-boundary|--c-boundary=*|--allow-c-boundary) allow=0 ;;
    esac
done

if [ "$allow" -eq 0 ]; then
    exec -a "${CT_ARGV0:-$0}" "$real" "$@"
fi
# `ct check` has no --c-boundary option, so the wrapper uses the environment
# (c_boundary_for reads CLI, then env, then manifest) for every registered row.
CT_C_BOUNDARY=allow
export CT_C_BOUNDARY
exec -a "${CT_ARGV0:-$0}" "$real" "$@"
