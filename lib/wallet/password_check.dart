// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Re-checks the wallet password before showing the 25 words from Settings. Only a salted hash is kept, in memory,
// for as long as the wallet is unlocked; nothing is written anywhere.
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class PasswordCheck {
  static List<int>? _salt, _hash;

  static List<int> _h(List<int> salt, String pw) => sha256.convert([...salt, ...utf8.encode(pw)]).bytes;

  static void remember(String password) {
    final r = Random.secure();
    _salt = List.generate(16, (_) => r.nextInt(256));
    _hash = _h(_salt!, password);
  }

  static void forget() => _salt = _hash = null;

  static bool get known => _hash != null;

  static bool matches(String password) {
    final s = _salt, h = _hash;
    if (s == null || h == null) return false;
    final g = _h(s, password);
    var diff = 0;
    for (var i = 0; i < h.length; i++) {
      diff |= h[i] ^ g[i];
    }
    return diff == 0;
  }
}
