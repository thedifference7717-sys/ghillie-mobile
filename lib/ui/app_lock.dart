// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
/// Lets screens deep in the app lock the wallet (back to the password / Face ID screen). Set by GhillieApp when the
/// app runs a real wallet with a vault; null in demo mode.
class AppLock {
  /// [turnOnQuickUnlock]: the unlock screen opens with "Unlock with Face ID next time" already ticked, so typing the
  /// password once (which proves it) switches Face ID / fingerprint unlock on.
  static void Function({bool turnOnQuickUnlock})? lock;
}
