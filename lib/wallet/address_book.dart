// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Saved addresses (exchanges, people, shops). Stored encrypted on this device, one list per wallet, through the same
// store as Subscriptions. No exchange is pre-loaded: none lists CAMO yet; listed ones get added in an update.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'subscriptions.dart' show SubscriptionStore, subscriptionStore;

enum ContactKind { exchange, person, shop, other }

extension ContactKindLabel on ContactKind {
  String get label => switch (this) {
        ContactKind.exchange => 'Exchange',
        ContactKind.person => 'Person',
        ContactKind.shop => 'Shop',
        ContactKind.other => 'Other',
      };
}

class SavedAddress {
  final String id;
  final ContactKind kind;
  final String name;
  final String address;
  const SavedAddress({required this.id, required this.kind, required this.name, required this.address});

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'name': name, 'address': address};

  static SavedAddress? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = ContactKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (kind == null || j['address'] is! String || j['name'] is! String) return null;
    return SavedAddress(id: '${j['id']}', kind: kind, name: j['name'] as String, address: j['address'] as String);
  }
}

class AddressBook extends ChangeNotifier {
  final String wallet;
  final SubscriptionStore store;
  AddressBook(this.wallet, {SubscriptionStore? store}) : store = store ?? subscriptionStore;

  String get _key => 'contacts/$wallet';
  List<SavedAddress> _items = [];
  List<SavedAddress> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final raw = await store.read(_key);
    try {
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      _items = [for (final j in list) ?SavedAddress.fromJson(j)];
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    _items.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    await store.write(_key, jsonEncode([for (final s in _items) s.toJson()]));
    notifyListeners();
  }

  Future<void> put(SavedAddress a) async {
    final i = _items.indexWhere((x) => x.id == a.id);
    i < 0 ? _items.add(a) : _items[i] = a;
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((x) => x.id == id);
    await _save();
  }
}
