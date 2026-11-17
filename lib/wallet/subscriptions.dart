// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Saved monthly payments ("subscriptions"). Ghillie never sends on its own: on the day, a payment shows as due
// and the user pays it with one tap (Send opens filled in, the normal review + confirm follows).
// Why not automatic: a wallet that pays by itself must keep its keys unlocked in the background, and phones do not
// run apps on a schedule anyway.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'amount.dart';

class Subscription {
  final String id;
  final String name;
  final String address;
  final CamoAmount amount;
  final int day; // 1..31; in shorter months a 29/30/31 payment falls on the last day
  final String? paidMonth; // 'yyyy-mm' of the last payment made from Ghillie
  final DateTime? start; // first payment date; never due before it
  const Subscription(
      {required this.id, required this.name, required this.address, required this.amount, required this.day, this.paidMonth, this.start});

  static String monthOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  /// This payment's day in the given month (the 31st is the 30th in April, the 28th or 29th in February).
  int dayIn(int year, int month) => day > _daysIn(year, month) ? _daysIn(year, month) : day;

  bool _beforeStart(DateTime d) => start != null && DateTime(d.year, d.month, d.day).isBefore(start!);

  bool isDue(DateTime now) => !_beforeStart(now) && now.day >= dayIn(now.year, now.month) && paidMonth != monthOf(now);

  /// The next date this payment is (or was) due, today included when it is still unpaid.
  DateTime nextDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_beforeStart(now)) return start!;
    if (isDue(now)) return today;
    final thisMonth = DateTime(now.year, now.month, dayIn(now.year, now.month));
    if (paidMonth != monthOf(now) && !thisMonth.isBefore(today)) return thisMonth;
    final next = DateTime(now.year, now.month + 1, 1);
    return DateTime(next.year, next.month, dayIn(next.year, next.month));
  }

  Subscription copyWith({String? name, String? address, CamoAmount? amount, int? day, String? paidMonth}) => Subscription(
      id: id, name: name ?? this.name, address: address ?? this.address, amount: amount ?? this.amount,
      day: day ?? this.day, paidMonth: paidMonth ?? this.paidMonth, start: start);

  static String _ymd(DateTime d) => '${monthOf(d)}-${d.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'address': address, 'amount': amount.toPlain(), 'day': day, 'paid': paidMonth,
        if (start != null) 'start': _ymd(start!),
      };

  static Subscription? fromJson(Object? j) {
    if (j is! Map) return null;
    final amount = CamoAmount.tryParse('${j['amount']}');
    final day = j['day'];
    if (amount == null || day is! int || day < 1 || day > 31) return null;
    return Subscription(
        id: '${j['id']}', name: '${j['name']}', address: '${j['address']}', amount: amount, day: day,
        paidMonth: j['paid'] as String?,
        start: j['start'] is String ? DateTime.tryParse(j['start'] as String) : null);
  }
}

/// Where the list is kept. Phones: the Keychain / Keystore (encrypted, this device only), one list per wallet.
abstract class SubscriptionStore {
  Future<String?> read(String wallet);
  Future<void> write(String wallet, String data);
}

class MemorySubscriptionStore implements SubscriptionStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String wallet) async => _m[wallet];
  @override
  Future<void> write(String wallet, String data) async => _m[wallet] = data;
}

class DeviceSubscriptionStore implements SubscriptionStore {
  static const _storage = FlutterSecureStorage();
  static const _ios = IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device, synchronizable: false);
  String _key(String wallet) => 'ghillie.subscriptions.$wallet';
  @override
  Future<String?> read(String wallet) async {
    try {
      return await _storage.read(key: _key(wallet), iOptions: _ios);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(String wallet, String data) => _storage.write(key: _key(wallet), value: data, iOptions: _ios);
}

SubscriptionStore subscriptionStore = MemorySubscriptionStore();

/// The open wallet's saved payments.
class SubscriptionBook extends ChangeNotifier {
  final String wallet;
  final SubscriptionStore store;
  SubscriptionBook(this.wallet, {SubscriptionStore? store}) : store = store ?? subscriptionStore;

  List<Subscription> _items = [];
  List<Subscription> get items => List.unmodifiable(_items);
  bool loaded = false;

  Future<void> load() async {
    final raw = await store.read(wallet);
    try {
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _items = [for (final j in list) ?Subscription.fromJson(j)];
    } catch (_) {
      _items = [];
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await store.write(wallet, jsonEncode([for (final s in _items) s.toJson()]));
    notifyListeners();
  }

  List<Subscription> due(DateTime now) => [for (final s in _items) if (s.isDue(now)) s];

  Future<void> put(Subscription s) async {
    final i = _items.indexWhere((x) => x.id == s.id);
    if (i < 0) {
      _items.add(s);
    } else {
      _items[i] = s;
    }
    _items.sort((a, b) => a.day.compareTo(b.day));
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((x) => x.id == id);
    await _save();
  }

  Future<void> markPaid(String id, DateTime now) async {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(paidMonth: Subscription.monthOf(now));
    await _save();
  }
}
