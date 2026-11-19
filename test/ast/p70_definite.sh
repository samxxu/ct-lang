#!/bin/sh
# PH-70-R2 aggregator: the two definite-assignment/return probes.
#
# Usage: sh test/ast/p70_definite.sh <ct-ast>
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
sh "$here/p70_return.sh" "$1" || exit 1
sh "$here/p70_uninit.sh" "$1" || exit 1
echo "OK p70/definite"
