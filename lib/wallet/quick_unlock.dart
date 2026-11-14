// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Optional Face ID / fingerprint unlock. Off by default; the user turns it on with a checkbox when typing the password.
// The wallet password is then kept in the phone's hardware-protected store, readable only after a biometric check:
//  * iOS: Keychain item with access control biometryCurrentSet (re-enrolling a face/finger invalidates it), this
//    device only, only while a passcode is set, never synced or backed up.
//  * Android: Keystore-backed AES key that requires strong biometrics for every read.
// Face and fingerprint data never reach Ghillie; the OS only says yes or no.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class QuickUnlock {
  bool get supported;
  /// "Face ID" on iPhone, "fingerprint" elsewhere (for labels).
  String get name;
  Future<bool> isSet();
  Future<void> save(String password);
  /// Asks for Face ID / fingerprint; null if the user cancels or it fails.
  Future<String?> read();
  Future<void> clear();
}

/// The app-wide instance: real on phones with the wallet engine, off elsewhere (desktop, demo, tests).
QuickUnlock quickUnlock = NoQuickUnlock();

class NoQuickUnlock implements QuickUnlock {
  @override
  bool get supported => false;
  @override
  String get name => 'biometrics';
  @override
  Future<bool> isSet() async => false;
  @override
  Future<void> save(String password) async {}
  @override
  Future<String?> read() async => null;
  @override
  Future<void> clear() async {}
}

/// In-memory stand-in for tests.
class MemoryQuickUnlock implements QuickUnlock {
  String? _pw;
  bool approve = true; // what the "biometric check" answers
  @override
  bool get supported => true;
  @override
  String get name => 'Face ID';
  @override
  Future<bool> isSet() async => _pw != null;
  @override
  Future<void> save(String password) async => _pw = password;
  @override
  Future<String?> read() async => approve ? _pw : null;
  @override
  Future<void> clear() async => _pw = null;
}

class DeviceQuickUnlock implements QuickUnlock {
  final bool isIOS;
  DeviceQuickUnlock({required this.isIOS});

  static const _key = 'ghillie.wallet.password';
  static const _storage = FlutterSecureStorage();
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );
  static const _android = AndroidOptions.biometric(
    enforceBiometrics: true,
    requireBiometricsPerOperation: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
    biometricPromptTitle: 'Unlock Ghillie',
    biometricPromptNegativeButton: 'Use password',
  );

  @override
  bool get supported => true;
  @override
  String get name => isIOS ? 'Face ID' : 'fingerprint';

  @override
  Future<bool> isSet() async {
    try {
      return await _storage.containsKey(key: _key, iOptions: _ios, aOptions: _android);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> save(String password) => _storage.write(key: _key, value: password, iOptions: _ios, aOptions: _android);

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key, iOptions: _ios, aOptions: _android);
    } on PlatformException {
      return null; // cancelled, failed, or the enrolled faces/fingers changed
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key, iOptions: _ios, aOptions: _android);
    } on PlatformException {
      // nothing stored
    }
  }
}
