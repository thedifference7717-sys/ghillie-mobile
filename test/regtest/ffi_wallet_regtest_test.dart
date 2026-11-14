// Real-library test of FfiWallet; skipped unless native/test/run-regtest-dart.sh sets the environment.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/wallet/amount.dart';
import 'package:ghillie/wallet/ffi_wallet.dart';
import 'package:ghillie/wallet/network.dart';
import 'package:ghillie/wallet/wallet_service.dart';

void main() {
  final env = Platform.environment;
  final lib = env['CAMO_WALLET_LIB'], dir = env['CAMO_TEST_DIR'], node = env['CAMO_NODE'];
  final skip = lib == null || dir == null || node == null;

  Future<void> until(bool Function() ok, String what) async {
    for (var i = 0; i < 120; i++) {
      if (ok()) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    fail('timed out waiting for $what');
  }

  test('FfiWallet sends 5 CAMO on regtest', () async {
    final stage = env['CAMO_STAGE']!;
    final a = FfiWallet.openOrCreate(libPath: lib!, path: '$dir/a', network: CamoNetwork.mainnet, node: node!);
    final b = FfiWallet.openOrCreate(libPath: lib, path: '$dir/b', network: CamoNetwork.mainnet, node: node);
    await until(() => a.sync.connected && a.sync.chainHeight > 0 && a.sync.walletHeight >= a.sync.chainHeight, 'sync');
    await until(() => b.sync.connected && b.sync.chainHeight > 0 && b.sync.walletHeight >= b.sync.chainHeight, 'sync B');
    if (stage == 'create') {
      File('$dir/a.addr').writeAsStringSync(a.receiveAddresses.first.address);
      final r = await b.newReceiveAddress('From Alice');
      File('$dir/b.addr').writeAsStringSync(r.address);
    } else if (stage == 'send') {
      await until(() => a.unlockedBalance > CamoAmount.tryParse('10')!, 'unlocked funds');
      final to = File('$dir/b.addr').readAsStringSync();
      expect(a.isValidAddress(to), isTrue);
      final draft = await a.prepareSend(address: to, amount: CamoAmount.tryParse('5')!, sweepAll: false, priority: Priority.normal);
      stdout.writeln('fee ${draft.fee.toPlain()}');
      final txid = await a.commitSend(draft);
      expect(txid.length, 64);
      stdout.writeln('txid $txid');
    } else if (stage == 'check') {
      await until(() => b.balance == CamoAmount.tryParse('5')!, 'B balance 5');
      final t = b.transactions.first;
      expect(t.direction, TxDirection.incoming);
      expect(t.amount, CamoAmount.tryParse('5')!);
      expect(b.receiveAddresses.last.label, 'From Alice');
      stdout.writeln('B balance ${b.balance.toPlain()}');
    }
    a.dispose();
    b.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
