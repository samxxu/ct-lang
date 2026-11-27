#!/bin/sh
# v1-PH-2 S9 M4: put test/c-boundary-wrap.sh in front of a freshly built
# ct-ast so every harness invocation honours the explicit allow registry.
# Usage: make-ct-ast-wrapper.sh <ct-ast> <repo-root>
set -u
real=$1
root=$2
mv "$real" "$real.real" || exit 1
{
    printf '#!/bin/sh\n'
    printf 'CT_ARGV0=$0\nexport CT_ARGV0\n'
    printf 'exec bash "%s/test/c-boundary-wrap.sh" "%s.real" "$@"\n' "$root" "$real"
} > "$real" || exit 1
chmod +x "$real" || exit 1
