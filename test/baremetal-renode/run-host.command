#!/bin/sh
# macOS convenience launcher for the STM32F4 Renode smoke (TEST-21).
#
# Double-click in Finder, or run from a normal terminal:
#     test/baremetal-renode/run-host.command
#
# It builds the four-stage bootstrap into /tmp/ct-host-renode, then runs the
# probe against the host `renode`. This needs to run OUTSIDE the agent sandbox:
# Renode writes ~/Library/Application Support/renode, which the agent cannot.
set -eu
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
W=/tmp/ct-host-renode
mkdir -p "$W"/{l2src,astsrc}

echo "== building ct-ast into $W =="
cc -Wall -Wextra -std=c99 "$root/selfhost/l0/ctc.c" -o "$W/ctc"
"$W/ctc" "$root/selfhost/l1/ctc.ct" -o "$W/l1.c"
cc -Wall -Wextra -std=c99 "$W/l1.c" -o "$W/l1"
"$W/l1" build "$root/selfhost/l2/driver.ct" -o "$W/l2src" >/dev/null
cc -Wall -Wextra -std=c99 "$W/l2src"/*.c -o "$W/l2"
"$W/l2" build -I "$root/selfhost/ct-ast" "$root/selfhost/ct-ast/main.ct" -o "$W/astsrc" >/dev/null
cc -Wall -Wextra -std=c99 "$W/astsrc"/*.c -o "$W/ct-ast"

echo "== Renode STM32F4 smoke =="
cd "$root"
RENODE_MODE=host sh test/baremetal-renode/run.sh "$W/ct-ast"
