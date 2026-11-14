// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'demo_wallet.dart';
import 'wallet_service.dart';

/// The one wallet file on this device: create, restore from the 25 seed words, or unlock.
/// Seed words exist in app memory only while the setup screens show them; Ghillie never sends or stores them.
abstract class WalletVault {
  bool get hasWallet;

  /// The CAMO node to sync from (host:port). Phones use a remote node; the wallet library treats it as untrusted.
  String get node;
  set node(String value);

  /// True when the setup/unlock screens should show the node field.
  bool get askNode => false;

  /// New wallet; returns it with its 25 seed words (shown once, for the user to write down).
  Future<(WalletService, List<String>)> create(String password);
  Future<WalletService> restore(List<String> words, String password, int restoreHeight);

  /// Throws [WrongPassword] if the password does not open the wallet.
  Future<WalletService> open(String password);
}

class WrongPassword implements Exception {
  const WrongPassword();
}

/// Demo vault: sample wallet, fixed sample words (never a real wallet).
class DemoVault extends WalletVault {
  bool _has;
  String _pw = '';
  DemoVault({bool hasWallet = false}) : _has = hasWallet;
  @override
  String node = 'demo';
  static const sampleWords = ['demo', 'words', 'only', 'never', 'use', 'these', 'for', 'real', 'coins', 'sample', 'sample', 'sample',
      'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'demo'];
  @override
  bool get hasWallet => _has;
  @override
  Future<(WalletService, List<String>)> create(String password) async {
    _has = true;
    _pw = password;
    return (DemoWallet() as WalletService, sampleWords);
  }

  @override
  Future<WalletService> restore(List<String> words, String password, int restoreHeight) async {
    _has = true;
    _pw = password;
    return DemoWallet();
  }

  @override
  Future<WalletService> open(String password) async {
    if (password != _pw) throw const WrongPassword();
    return DemoWallet();
  }
}

/// "host:port" with a port of 1-65535 (IPv6 in brackets).
bool looksLikeNode(String s) {
  final m = RegExp(r'^(\[[0-9a-fA-F:]+\]|[A-Za-z0-9.-]+):(\d{1,5})$').firstMatch(s.trim());
  if (m == null) return false;
  final port = int.parse(m.group(2)!);
  return port >= 1 && port <= 65535;
}
