// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// WalletService backed by CAMO's real wallet library through native/camo_wallet_ffi (dart:ffi).
// The library's own background thread keeps the wallet in sync; this class polls it every 2 seconds.
// TODO before release: run prepare/commit on a background isolate so a slow node can't freeze the screen.
import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'amount.dart';
import 'network.dart';
import 'vault.dart';
import 'wallet_service.dart';

typedef _P = Pointer<Void>;
typedef _S = Pointer<Utf8>;

class _Lib {
  final DynamicLibrary d;
  _Lib(this.d);
  late final open = d.lookupFunction<_P Function(_S, _S, Int32), _P Function(_S, _S, int)>('camo_wallet_open');
  late final create = d.lookupFunction<_P Function(_S, _S, _S, Int32), _P Function(_S, _S, _S, int)>('camo_wallet_create');
  late final restoreSeed = d.lookupFunction<_P Function(_S, _S, _S, Int32, Uint64), _P Function(_S, _S, _S, int, int)>('camo_wallet_restore_seed');
  late final seed = d.lookupFunction<_S Function(_P), _S Function(_P)>('camo_wallet_seed');
  late final close = d.lookupFunction<Int32 Function(_P, Int32), int Function(_P, int)>('camo_wallet_close');
  late final exists = d.lookupFunction<Int32 Function(_S), int Function(_S)>('camo_wallet_exists');
  late final lastError = d.lookupFunction<_S Function(), _S Function()>('camo_last_error');
  late final error = d.lookupFunction<_S Function(_P), _S Function(_P)>('camo_wallet_error');
  late final address = d.lookupFunction<_S Function(_P, Uint32), _S Function(_P, int)>('camo_wallet_address');
  late final numSub = d.lookupFunction<Uint32 Function(_P), int Function(_P)>('camo_wallet_num_subaddresses');
  late final addSub = d.lookupFunction<Int32 Function(_P, _S), int Function(_P, _S)>('camo_wallet_add_subaddress');
  late final subLabel = d.lookupFunction<_S Function(_P, Uint32), _S Function(_P, int)>('camo_wallet_subaddress_label');
  late final setSubLabel = d.lookupFunction<Int32 Function(_P, Uint32, _S), int Function(_P, int, _S)>('camo_wallet_set_subaddress_label');
  late final connect = d.lookupFunction<Int32 Function(_P, _S, Int32), int Function(_P, _S, int)>('camo_wallet_connect');
  late final startRefresh = d.lookupFunction<Int32 Function(_P), int Function(_P)>('camo_wallet_start_refresh');
  late final height = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_height');
  late final daemonHeight = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_daemon_height');
  late final connected = d.lookupFunction<Int32 Function(_P), int Function(_P)>('camo_wallet_connected');
  late final balance = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_balance');
  late final unlocked = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_unlocked_balance');
  late final store = d.lookupFunction<Int32 Function(_P), int Function(_P)>('camo_wallet_store');
  late final histRefresh = d.lookupFunction<Int32 Function(_P), int Function(_P)>('camo_wallet_history_refresh');
  late final histCount = d.lookupFunction<Int32 Function(_P), int Function(_P)>('camo_wallet_history_count');
  late final histRow = d.lookupFunction<_S Function(_P, Int32), _S Function(_P, int)>('camo_wallet_history_row');
  late final valid = d.lookupFunction<Int32 Function(_S, Int32), int Function(_S, int)>('camo_address_valid');
  late final prepare = d.lookupFunction<Int32 Function(_P, _S, Uint64, Int32, Int32), int Function(_P, _S, int, int, int)>('camo_wallet_prepare');
  late final prepFee = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_prepared_fee');
  late final prepAmount = d.lookupFunction<Uint64 Function(_P), int Function(_P)>('camo_wallet_prepared_amount');
  late final commit = d.lookupFunction<_S Function(_P), _S Function(_P)>('camo_wallet_commit');
  late final discard = d.lookupFunction<Void Function(_P), void Function(_P)>('camo_wallet_discard');
}

// uint64 arrives as a Dart int (two's complement); convert to an unsigned BigInt
BigInt _u64(int v) => v >= 0 ? BigInt.from(v) : BigInt.from(v) + (BigInt.one << 64);
CamoAmount _amt(int v) => CamoAmount.atomic(_u64(v));
int _netCode(CamoNetwork n) => switch (n) { CamoNetwork.mainnet => 0, CamoNetwork.testnet => 1, CamoNetwork.stagenet => 2 };

class FfiWallet extends WalletService {
  final _Lib _l;
  final _P _w;
  @override
  final CamoNetwork network;
  @override
  final String walletName;
  final String nodeAddress;
  Timer? _timer;
  SyncState _sync;
  CamoAmount _bal = CamoAmount.zero, _unl = CamoAmount.zero;
  List<TxRecord> _txs = const [];
  int _lastHeight = -1;

  FfiWallet._(this._l, this._w, this.network, this.walletName, this.nodeAddress)
      : _sync = SyncState(connected: false, walletHeight: 0, chainHeight: 0, nodeLabel: nodeAddress);

  /// Opens the wallet at [path], or creates it if there is none (empty password: development and tests only).
  static FfiWallet openOrCreate({required String libPath, required String path, required CamoNetwork network, required String node}) {
    final l = _Lib(DynamicLibrary.open(libPath));
    final w = using((a) {
      final p = path.toNativeUtf8(allocator: a), pw = ''.toNativeUtf8(allocator: a);
      return l.exists(p) == 1 ? l.open(p, pw, _netCode(network)) : l.create(p, pw, 'English'.toNativeUtf8(allocator: a), _netCode(network));
    });
    return _start(l, w, path, network, node);
  }

  static FfiWallet _start(_Lib l, _P w, String path, CamoNetwork network, String node) {
    if (w == nullptr) throw StateError(l.lastError().toDartString());
    final ok = using((a) => l.connect(w, node.toNativeUtf8(allocator: a), 1));
    if (ok != 1) {
      final e = l.error(w).toDartString();
      l.close(w, 0);
      throw StateError(e);
    }
    l.startRefresh(w);
    final fw = FfiWallet._(l, w, network, path.split('/').last, node);
    fw._poll();
    fw._timer = Timer.periodic(const Duration(seconds: 2), (_) => fw._poll());
    return fw;
  }

  void _poll() {
    final h = _l.height(_w), dh = _l.daemonHeight(_w);
    _sync = SyncState(connected: _l.connected(_w) == 1, walletHeight: h, chainHeight: dh, nodeLabel: nodeAddress);
    _bal = _amt(_l.balance(_w));
    _unl = _amt(_l.unlocked(_w));
    if (h != _lastHeight) {
      _lastHeight = h;
      _l.histRefresh(_w);
      final rows = <TxRecord>[];
      for (var i = 0; i < _l.histCount(_w); i++) {
        final r = _l.histRow(_w, i);
        if (r == nullptr) continue;
        final f = r.toDartString().split('|');
        rows.add(TxRecord(
          direction: f[0] == '0' ? TxDirection.incoming : TxDirection.outgoing,
          amount: CamoAmount.atomic(BigInt.parse(f[1])),
          fee: CamoAmount.atomic(BigInt.parse(f[2])),
          time: DateTime.fromMillisecondsSinceEpoch(int.parse(f[3]) * 1000),
          confirmations: int.parse(f[4]),
          label: f[6] == '1' ? 'Mining reward' : (f[0] == '0' ? 'Received' : 'Sent'),
          txid: f[5],
        ));
      }
      rows.sort((a, b) => b.time.compareTo(a.time));
      _txs = rows;
    }
    notifyListeners();
  }

  @override
  bool get isDemo => false;
  @override
  CamoAmount get balance => _bal;
  @override
  CamoAmount get unlockedBalance => _unl;
  @override
  SyncState get sync => _sync;
  @override
  List<TxRecord> get transactions => _txs;
  @override
  List<ReceiveAddress> get receiveAddresses => [
        for (var i = 0; i < _l.numSub(_w); i++)
          ReceiveAddress(i, _l.address(_w, i).toDartString(), i == 0 ? 'Primary address' : _l.subLabel(_w, i).toDartString()),
      ];

  @override
  Future<ReceiveAddress> newReceiveAddress(String label) async {
    using((a) => _l.addSub(_w, label.toNativeUtf8(allocator: a)));
    _l.store(_w);
    notifyListeners();
    return receiveAddresses.last;
  }

  @override
  Future<void> renameReceiveAddress(int index, String label) async {
    using((a) => _l.setSubLabel(_w, index, label.toNativeUtf8(allocator: a)));
    _l.store(_w);
    notifyListeners();
  }

  @override
  bool isValidAddress(String address) => using((a) => _l.valid(address.toNativeUtf8(allocator: a), _netCode(network)) == 1);

  @override
  Future<SendDraft> prepareSend({required String address, required CamoAmount amount, required bool sweepAll, required Priority priority}) async {
    if (!isValidAddress(address)) {
      // estimate only: a fee guess for the form before an address is entered
      return SendDraft(address: address, amount: amount, sweepAll: sweepAll, priority: priority, fee: CamoAmount.tryParse('0.0013')!);
    }
    final pr = switch (priority) { Priority.low => 1, Priority.normal => 2, Priority.fast => 3 };
    final ok = using((a) => _l.prepare(_w, address.toNativeUtf8(allocator: a), amount.atomic.toUnsigned(64).toInt(), sweepAll ? 1 : 0, pr));
    if (ok != 1) throw StateError(_l.lastError().toDartString());
    return SendDraft(address: address, amount: _amt(_l.prepAmount(_w)), sweepAll: sweepAll, priority: priority, fee: _amt(_l.prepFee(_w)));
  }

  @override
  Future<String> commitSend(SendDraft draft) async {
    // re-prepare exactly what was reviewed, then broadcast
    await prepareSend(address: draft.address, amount: draft.amount, sweepAll: draft.sweepAll, priority: draft.priority);
    final r = _l.commit(_w);
    if (r == nullptr) throw StateError(_l.lastError().toDartString());
    final id = r.toDartString();
    _lastHeight = -1;
    _poll();
    return id;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _l.close(_w, 1);
    super.dispose();
  }
}

/// The device's wallet file through the real library. [node] is the CAMO node to sync from (host:port).
class FfiVault extends WalletVault {
  final _Lib _l;
  final String path;
  final CamoNetwork network;
  final String node;
  FfiVault({required String libPath, required this.path, required this.network, required this.node})
      : _l = _Lib(DynamicLibrary.open(libPath));

  @override
  bool get hasWallet => using((a) => _l.exists(path.toNativeUtf8(allocator: a)) == 1);

  @override
  Future<(WalletService, List<String>)> create(String password) async {
    final w = using((a) => _l.create(path.toNativeUtf8(allocator: a), password.toNativeUtf8(allocator: a),
        'English'.toNativeUtf8(allocator: a), _netCode(network)));
    if (w == nullptr) throw StateError(_l.lastError().toDartString());
    final words = _l.seed(w).toDartString().split(' ');
    return (FfiWallet._start(_l, w, path, network, node) as WalletService, words);
  }

  @override
  Future<WalletService> restore(List<String> words, String password, int restoreHeight) async {
    final w = using((a) => _l.restoreSeed(path.toNativeUtf8(allocator: a), password.toNativeUtf8(allocator: a),
        words.join(' ').toNativeUtf8(allocator: a), _netCode(network), restoreHeight));
    if (w == nullptr) throw StateError(_l.lastError().toDartString());
    return FfiWallet._start(_l, w, path, network, node);
  }

  @override
  Future<WalletService> open(String password) async {
    final w = using((a) => _l.open(path.toNativeUtf8(allocator: a), password.toNativeUtf8(allocator: a), _netCode(network)));
    if (w == nullptr) {
      final e = _l.lastError().toDartString();
      if (e.toLowerCase().contains('password')) throw const WrongPassword();
      throw StateError(e);
    }
    return FfiWallet._start(_l, w, path, network, node);
  }
}
