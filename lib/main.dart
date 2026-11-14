// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/scope_intro.dart';
import 'ui/app_lock.dart';
import 'ui/theme.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'screens/setup_screen.dart';
import 'wallet/demo_wallet.dart';
import 'wallet/quick_unlock.dart';
import 'wallet/vault.dart';
import 'wallet/ffi_wallet.dart';
import 'wallet/network.dart';
import 'wallet/wallet_service.dart';

/// Phones: if the wallet engine is in the app (libcamo_wallet), the real wallet runs on STAGENET for now, with the
/// wallet file in the app's private folder and a node the user enters. Without the engine: demo data.
/// Desktop development: set CAMO_WALLET_LIB (path to libcamo_wallet.so), CAMO_WALLET (wallet file) and CAMO_NODE
/// (host:port); CAMO_NETWORK = mainnet|stagenet|testnet (default stagenet). Without them: demo data.
/// The project's public read-only stagenet node for phones (AWS seed, `deploy-seed-node.sh --public-rpc`, Nov 14).
const stagenetPhoneNode = '3.134.132.214:39749';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  WalletVault? vault;
  if (env['CAMO_WALLET_LIB'] != null && env['CAMO_WALLET'] != null && env['CAMO_NODE'] != null) {
    final net = CamoNetwork.values.firstWhere((n) => n.name == env['CAMO_NETWORK'], orElse: () => CamoNetwork.stagenet);
    vault = FfiVault(libPath: env['CAMO_WALLET_LIB']!, path: env['CAMO_WALLET']!, network: net, node: env['CAMO_NODE']!);
  } else if (Platform.isAndroid || Platform.isIOS) {
    try {
      final dir = await getApplicationSupportDirectory();
      vault = FfiVault(
          libPath: Platform.isAndroid ? 'libcamo_wallet.so' : null,
          path: '${dir.path}/stagenet-wallet',
          network: CamoNetwork.stagenet,
          defaultNode: stagenetPhoneNode,
          askNode: true);
      vault.hasWallet; // fails here if the engine is not in this build
      quickUnlock = DeviceQuickUnlock(isIOS: Platform.isIOS); // only with the real wallet; opt-in per wallet
    } catch (_) {
      vault = null; // demo build
    }
  }
  runApp(GhillieApp(vault: vault, wallet: vault == null ? DemoWallet() : null, showIntro: env['CAMO_SKIP_INTRO'] == null));
}

class GhillieApp extends StatefulWidget {
  /// With a vault, the setup/unlock screens run first; otherwise [wallet] is shown directly.
  final WalletVault? vault;
  final WalletService? wallet;
  final bool showIntro;
  const GhillieApp({super.key, this.vault, this.wallet, this.showIntro = true}) : assert(vault != null || wallet != null);
  @override
  State<GhillieApp> createState() => _GhillieAppState();
}

class _GhillieAppState extends State<GhillieApp> {
  late bool _intro = widget.showIntro;
  late WalletService? _wallet = widget.wallet;
  bool _turnOnQuick = false;

  @override
  void initState() {
    super.initState();
    if (widget.vault != null) AppLock.lock = _lock;
  }

  @override
  void dispose() {
    if (AppLock.lock == _lock) AppLock.lock = null;
    super.dispose();
  }

  void _lock({bool turnOnQuickUnlock = false}) {
    final w = _wallet;
    setState(() {
      _wallet = null;
      _turnOnQuick = turnOnQuickUnlock;
    });
    w?.dispose(); // closes and saves the wallet file; the keys leave memory
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ghillie',
        debugShowCheckedModeBanner: false,
        theme: ghillieTheme(),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _intro
              ? ScopeIntro(key: const ValueKey('intro'), onEnter: () => setState(() => _intro = false))
              : _wallet == null
                  ? SetupScreen(
                      key: ValueKey('setup-$_turnOnQuick'),
                      vault: widget.vault!,
                      rememberNext: _turnOnQuick,
                      onReady: (w) => setState(() => _wallet = w))
                  : HomeScreen(key: const ValueKey('home'), wallet: _wallet!),
        ),
      );
}
