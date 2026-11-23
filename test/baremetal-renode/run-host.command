#!/bin/sh
# macOS convenience launcher for the STM32F4 Renode smoke (TEST-21).
#
# Double-click in Finder, or run from a normal terminal:
#     test/baremetal-renode/run-host.command
#
# It builds ct-ast from the frozen seed into /tmp/ct-host-renode, then runs the
# probe against the host `renode`. This needs to run OUTSIDE the agent sandbox:
# Renode writes ~/Library/Application Support/renode, which the agent cannot.
set -eu
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
W=/tmp/ct-host-renode
echo "== building ct-ast from the frozen seed into $W =="
# v1-PH-0 S2b / D-022: the L0 -> L1 -> L2 walk can no longer build ct-ast.
cc -Wall -Wextra -std=c99 -I "$root/bootstrap/ct-ast" \
    "$root/bootstrap/ct-ast"/*.c -o "$W/ct-ast"

echo "== Renode STM32F4 smoke =="
cd "$root"
RENODE_MODE=host sh test/baremetal-renode/run.sh "$W/ct-ast"
