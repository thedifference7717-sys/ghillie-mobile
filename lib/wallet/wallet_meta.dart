// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// What Ghillie notes about a wallet for its recovery sheet: the date it was made and a safe restore height.
// Stored encrypted on this phone with the other per-wallet data. Nothing here is secret or needed to spend.
import 'dart:convert';
import 'subscriptions.dart' show SubscriptionStore, subscriptionStore;
import 'wallet_service.dart';

class WalletMeta {
  final DateTime? created;
  final int? restoreHeight;
  const WalletMeta({this.created, this.restoreHeight});

  /// Blocks subtracted from the chain height seen at creation: a lower restore height is always safe (just slower);
  /// a higher one could skip coins. 720 blocks = 12 hours of 1-minute blocks.
  static const margin = 720;

  static String _key(String wallet) => 'meta/$wallet';

  static Future<WalletMeta> load(String wallet, {SubscriptionStore? store}) async {
    final raw = await (store ?? subscriptionStore).read(_key(wallet));
    try {
      final j = jsonDecode(raw ?? '{}') as Map;
      return WalletMeta(
        created: j['created'] is String ? DateTime.tryParse(j['created'] as String) : null,
        restoreHeight: j['height'] is int ? j['height'] as int : null,
      );
    } catch (_) {
      return const WalletMeta();
    }
  }

  static Future<void> _save(String wallet, WalletMeta m, SubscriptionStore? store) =>
      (store ?? subscriptionStore).write(
        _key(wallet),
        jsonEncode({
          if (m.created != null) 'created': m.created!.toIso8601String(),
          if (m.restoreHeight != null) 'height': m.restoreHeight,
        }),
      );

  /// A brand-new wallet: today's date, and the chain height (minus a margin) as soon as the node reports it.
  static Future<void> recordCreated(WalletService w, {SubscriptionStore? store, DateTime? now}) async {
    final created = now ?? DateTime.now();
    int? height(int chain) {
      if (chain <= 0) return null;
      final waited = DateTime.now().difference(created).inMinutes; // blocks that may have passed since creation
      final h = chain - margin - (waited > 0 ? waited : 0);
      return h < 0 ? 0 : h;
    }

    final h = height(w.sync.chainHeight);
    await _save(w.walletName, WalletMeta(created: created, restoreHeight: h), store);
    if (h != null) return;
    void listener() {
      final h = height(w.sync.chainHeight);
      if (h == null) return;
      w.removeListener(listener);
      _save(w.walletName, WalletMeta(created: created, restoreHeight: h), store);
    }

    w.addListener(listener);
  }

  /// Filled in by hand on Settings > Recovery words (wallets made before Ghillie recorded this).
  static Future<void> set(String wallet, WalletMeta m, {SubscriptionStore? store}) => _save(wallet, m, store);

  /// A restored wallet: its original date is unknown; the restore height typed in still works.
  static Future<void> recordRestored(WalletService w, int restoreHeight, {SubscriptionStore? store}) =>
      _save(w.walletName, WalletMeta(restoreHeight: restoreHeight), store);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String sheetDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
