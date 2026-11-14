#!/usr/bin/env bash
# End-to-end test of the C bridge against CAMO's real wallet library on a private regtest chain:
# create wallets A and B, mine to A, send 5 CAMO from A to a new labelled subaddress of B, check B got exactly 5.
#   bash native/test/run-regtest-smoke.sh <camo source dir> <camo build dir with libs + bin/camod>
# Passed Nov 14, 2026 (Linux, libs from a Ghillie desktop build): fee 0.00123462, txid returned, B = 5.000000000000.
set -euo pipefail
SRC=${1:?camo source}; BLD=${2:?camo build dir}
HERE=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d)
LIBS=$(find "$BLD" -name "*.a" -not -path "*CMakeFiles*" -not -name "libdaemon_rpc_server.a" | tr '\n' ' ')
g++ -std=c++17 -O1 -c -I"$SRC/src" "$HERE/../camo_wallet_ffi.cpp" -o "$W/bridge.o"
gcc -c -I"$HERE/.." "$HERE/smoke.c" -o "$W/smoke.o"
g++ -o "$W/smoke" "$W/smoke.o" "$W/bridge.o" -Wl,--start-group $LIBS -Wl,--end-group -lboost_filesystem -lboost_thread \
  -lboost_serialization -lboost_program_options -lboost_chrono -lboost_locale -lboost_date_time -lssl -lcrypto -lsodium \
  -lunbound -lzmq -lhidapi-libusb -lusb-1.0 -lpthread -lreadline
CAMOD=$(find "$BLD" -name camod -type f -perm -u+x | head -1)
mkdir -p "$W/w" "$W/node"
"$CAMOD" --regtest --offline --fixed-difficulty 1 --data-dir "$W/node" --rpc-bind-port 19741 --p2p-bind-port 19740 --non-interactive --log-file "$W/node/camod.log" >/dev/null 2>&1 &
NODE=$!; trap 'kill $NODE 2>/dev/null; rm -rf "$W"' EXIT; sleep 8
A=$("$W/smoke" create "$W/w" | grep -o 'C[0-9A-Za-z]\{94\}')
mine(){ curl -s http://127.0.0.1:19741/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"generateblocks\",\"params\":{\"amount_of_blocks\":$1,\"wallet_address\":\"$A\"}}" >/dev/null; }
mine 10   # a real chain is never 1 block tall; on one that is, the library treats every wallet as new on each open
"$W/smoke" check "$W/w" 127.0.0.1:19741 >/dev/null 2>&1 || true
"$W/smoke" send "$W/w" 127.0.0.1:19741 >/dev/null 2>&1 || true   # first connect of A (no funds yet)
mine 80
"$W/smoke" send "$W/w" 127.0.0.1:19741
mine 2
OUT=$("$W/smoke" check "$W/w" 127.0.0.1:19741); echo "$OUT"
grep -q 'balance 5000000000000 ' <<<"$OUT" && echo "PASS: B received exactly 5 CAMO" || { echo "FAIL"; exit 1; }
