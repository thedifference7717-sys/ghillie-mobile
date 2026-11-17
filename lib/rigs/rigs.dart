// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Rigs: control mining on your OWN computers from the phone. The computer runs the Ghillie rig helper
// (camo repo: contrib/camo/tools/ghillie-rig-agent.py) next to camod. Pairing gives the phone the helper's address,
// the SHA-256 fingerprint of its TLS certificate and a 256-bit secret.
//
// Security: the phone trusts NO certificate authority for rigs. Every connection must present exactly the paired
// certificate or nothing is sent, so the secret never leaves the phone towards anything else. A paired phone can
// only read status, start (threads capped on the computer) and stop. The payout address is fixed on the computer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../wallet/subscriptions.dart' show SubscriptionStore, subscriptionStore;

class RigPairing {
  final String id, name, network, host, fingerprint, secret;
  final int port;
  const RigPairing({
    required this.id,
    required this.name,
    required this.network,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.secret,
  });

  static const prefix = 'ghillie-rig:';

  /// Parses a pairing code from the rig helper (`ghillie-rig:<base64url JSON>`); null if it isn't one.
  static RigPairing? parse(String code) {
    final t = code.trim();
    if (!t.startsWith(prefix)) return null;
    try {
      final b64 = t.substring(prefix.length);
      final j = jsonDecode(utf8.decode(base64Url.decode(b64.padRight((b64.length + 3) ~/ 4 * 4, '='))));
      if (j is! Map || j['v'] != 1) return null;
      final fp = '${j['fp']}'.toLowerCase(), secret = '${j['secret']}', host = '${j['host']}';
      final port = j['port'];
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fp) || secret.length < 43 || port is! int || port < 1 || port > 65535) {
        return null;
      }
      if (InternetAddress.tryParse(host) == null) return null;
      final net = '${j['net']}';
      if (!const ['mainnet', 'stagenet', 'testnet'].contains(net)) return null;
      final name = '${j['name'] ?? 'Computer'}'.trim();
      return RigPairing(
        id: '$host:$port/${fp.substring(0, 16)}',
        name: name.isEmpty ? 'Computer' : name,
        network: net,
        host: host,
        port: port,
        fingerprint: fp,
        secret: secret,
      );
    } catch (_) {
      return null;
    }
  }

  RigPairing renamed(String n) =>
      RigPairing(id: id, name: n, network: network, host: host, port: port, fingerprint: fingerprint, secret: secret);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'net': network,
    'host': host,
    'port': port,
    'fp': fingerprint,
    'secret': secret,
  };

  static RigPairing? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return RigPairing(
        id: j['id'] as String,
        name: j['name'] as String,
        network: j['net'] as String,
        host: j['host'] as String,
        port: j['port'] as int,
        fingerprint: j['fp'] as String,
        secret: j['secret'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

enum RigState { checking, mining, stopped, noCamod, unreachable, refused, wrongCertificate, helperError }

class RigStatus {
  final RigState state;
  final int hashrate, threads, maxThreads, height, cpus;
  final String payout;
  const RigStatus(
    this.state, {
    this.hashrate = 0,
    this.threads = 0,
    this.maxThreads = 1,
    this.height = 0,
    this.cpus = 0,
    this.payout = '',
  });

  static RigStatus fromJson(Map j) {
    if (j['camod'] != true) return const RigStatus(RigState.noCamod);
    return RigStatus(
      j['mining'] == true ? RigState.mining : RigState.stopped,
      hashrate: (j['hashrate'] as num?)?.toInt() ?? 0,
      threads: (j['threads'] as num?)?.toInt() ?? 0,
      maxThreads: (j['max_threads'] as num?)?.toInt() ?? 1,
      cpus: (j['cpus'] as num?)?.toInt() ?? 0,
      height: (j['height'] as num?)?.toInt() ?? 0,
      payout: '${j['payout'] ?? ''}',
    );
  }
}

abstract class RigClient {
  Future<RigStatus> status(RigPairing r);
  Future<RigStatus> start(RigPairing r, int threads);
  Future<RigStatus> stop(RigPairing r);
}

/// Talks to the rig helper over TLS, accepting only the paired certificate.
class HttpRigClient implements RigClient {
  static bool pinned(X509Certificate cert, String fingerprint) => sha256.convert(cert.der).toString() == fingerprint;

  Future<RigStatus> _call(RigPairing r, String method, String path, [Map<String, Object?>? body]) async {
    var badCert = false;
    // No trusted roots: every certificate goes through the pin check below, including CA-signed ones.
    final http = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 6)
      ..badCertificateCallback = (cert, host, port) {
        final ok = pinned(cert, r.fingerprint);
        badCert = !ok;
        return ok;
      };
    try {
      final req = await http.openUrl(method, Uri(scheme: 'https', host: r.host, port: r.port, path: path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${r.secret}');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.contentLength = bytes.length; // plain Content-Length, not chunked
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) return const RigStatus(RigState.refused);
      if (res.statusCode == 503) return const RigStatus(RigState.noCamod);
      if (res.statusCode != 200) return const RigStatus(RigState.helperError);
      final j = jsonDecode(text);
      return j is Map ? RigStatus.fromJson(j) : const RigStatus(RigState.unreachable);
    } on HandshakeException {
      return RigStatus(badCert ? RigState.wrongCertificate : RigState.unreachable);
    } catch (_) {
      return RigStatus(badCert ? RigState.wrongCertificate : RigState.unreachable);
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<RigStatus> status(RigPairing r) => _call(r, 'GET', '/v1/status');
  @override
  Future<RigStatus> start(RigPairing r, int threads) => _call(r, 'POST', '/v1/start', {'threads': threads});
  @override
  Future<RigStatus> stop(RigPairing r) => _call(r, 'POST', '/v1/stop', {});
}

/// Paired rigs, stored encrypted on this phone (one list for the phone, not per wallet).
class RigList extends ChangeNotifier {
  final SubscriptionStore store;
  RigList({SubscriptionStore? store}) : store = store ?? subscriptionStore;
  static const _key = 'rigs';
  List<RigPairing> _items = [];
  List<RigPairing> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final raw = await store.read(_key);
    try {
      _items = [for (final j in (raw == null ? const [] : jsonDecode(raw) as List)) ?RigPairing.fromJson(j)];
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await store.write(_key, jsonEncode([for (final r in _items) r.toJson()]));
    notifyListeners();
  }

  Future<void> put(RigPairing r) async {
    final i = _items.indexWhere((x) => x.id == r.id || (x.host == r.host && x.port == r.port));
    i < 0 ? _items.add(r) : _items[i] = r;
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((x) => x.id == id);
    await _save();
  }
}

RigClient rigClient = HttpRigClient();
