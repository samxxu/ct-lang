#!/usr/bin/env bash
# CI-9 probe: `ct get` of an HTTP git URL whose server accepts the connection
# but never sends a byte must fail within a bounded time. Before CI-9 the only
# subprocess was a bare `system("git ...")` -- no wall-clock cap and no prompt
# guard -- so this probe hung forever and the gate hung with it.
#
# The probe uses the OS `timeout` utility to bound ct itself. Where there is no
# `timeout` (stock macOS) the CI-9 fix degrades to git's `http.lowSpeed*`
# configuration, which this probe cannot time portably: it reports skip (77)
# instead of pretending to prove the bound.
#
# Usage: bash test/ast/p77_net_timeout.sh <ct-ast>
set -u
CT=${1:?usage: p77_net_timeout.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac

if ! command -v timeout >/dev/null 2>&1; then
    echo "skip: no 'timeout' on this host; the git low-speed fallback is not timed here" >&2
    exit 77
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "skip: python3 not found" >&2
    exit 77
fi
if ! command -v git >/dev/null 2>&1; then
    echo "skip: git not found" >&2
    exit 77
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/p77net.XXXXXX") || exit 1
srv=
cleanup() {
    if [ -n "$srv" ]; then
        kill "$srv" 2>/dev/null
        wait "$srv" 2>/dev/null
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

# A server that accepts and then says nothing: the stalled-network shape CI-9
# is about (a blackholed IP fails at the TCP layer, this one does not).
python3 - "$tmp/port" <<'PY' &
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(8)
with open(sys.argv[1], "w") as fh:
    fh.write(str(s.getsockname()[1]))
held = []
while True:
    try:
        conn, _ = s.accept()
        held.append(conn)          # accepted, never answered
    except OSError:
        break
PY
srv=$!

port=
i=0
while [ "$i" -lt 100 ]; do
    if [ -s "$tmp/port" ]; then port=$(cat "$tmp/port"); break; fi
    sleep 0.05
    i=$((i + 1))
done
if [ -z "$port" ]; then
    echo "FAIL p77/net-timeout: the stalled server did not start" >&2
    exit 1
fi

mkdir -p "$tmp/home" "$tmp/proj"
start=$(date +%s)
( cd "$tmp/proj" && HOME="$tmp/home" CT_HOME="$tmp/home" \
    CT_GIT_TIMEOUT=5 NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost \
    timeout 40 "$CT" get "http://127.0.0.1:$port/x.git" ) >"$tmp/out" 2>"$tmp/err"
rc=$?
elapsed=$(( $(date +%s) - start ))

if [ "$rc" -eq 124 ]; then
    echo "FAIL p77/net-timeout: ct get hung past the 40s bound (no internal timeout)" >&2
    exit 1
fi
if [ "$rc" -eq 0 ]; then
    echo "FAIL p77/net-timeout: ct get accepted a package from a server that sent nothing" >&2
    exit 1
fi
if [ "$elapsed" -gt 30 ]; then
    echo "FAIL p77/net-timeout: ct get took ${elapsed}s (bound 30s; CT_GIT_TIMEOUT=5)" >&2
    exit 1
fi
if ! grep -q "git clone of" "$tmp/err"; then
    echo "FAIL p77/net-timeout: the failure did not come from the git clone" >&2
    sed -n '1,4p' "$tmp/err" >&2
    exit 1
fi
echo "OK p77/net-timeout (ct get failed in ${elapsed}s, rc=$rc)"
exit 0
