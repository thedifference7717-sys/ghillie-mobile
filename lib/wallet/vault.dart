// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'demo_wallet.dart';
import 'wallet_service.dart';

/// The one wallet file on this device: create, restore from the 25 seed words, or unlock.
/// Seed words exist in app memory only while the setup screens show them; Ghillie never sends or stores them.
abstract class WalletVault {
  bool get hasWallet;

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
