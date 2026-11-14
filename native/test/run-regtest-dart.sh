#!/usr/bin/env bash
# End-to-end test of the Dart wallet (lib/wallet/ffi_wallet.dart) on a private regtest chain:
#   bash native/test/run-regtest-dart.sh <path to libcamo_wallet.so> <dir with camod>
set -euo pipefail
LIB=$(realpath "${1:?libcamo_wallet.so}"); CAMOD=${2:?dir with camod}/camod
cd "$(dirname "$0")/../.."; W=$(mktemp -d); mkdir -p "$W/node"
"$CAMOD" --regtest --offline --fixed-difficulty 1 --data-dir "$W/node" --rpc-bind-port 19741 --p2p-bind-port 19740 --non-interactive >/dev/null 2>&1 &
NODE=$!; trap 'kill $NODE 2>/dev/null; rm -rf "$W"' EXIT; sleep 8
mine(){ curl -s http://127.0.0.1:19741/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"generateblocks\",\"params\":{\"amount_of_blocks\":$1,\"wallet_address\":\"$2\"}}" >/dev/null; }
run(){ CAMO_WALLET_LIB=$LIB CAMO_TEST_DIR=$W CAMO_NODE=127.0.0.1:19741 CAMO_STAGE=$1 flutter test test/regtest/ffi_wallet_regtest_test.dart --reporter expanded; }
run create; A=$(cat "$W/a.addr")
mine 10 "$A"; run sync   # a chain 1 block tall makes the library treat each open as new; real chains never are
mine 80 "$A"; run send
mine 2 "$A"; run check
echo "PASS: Dart wallet sent 5 CAMO; B received exactly 5"
