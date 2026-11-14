// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/scope_intro.dart';
import 'ui/theme.dart';
import 'dart:io';
import 'screens/setup_screen.dart';
import 'wallet/demo_wallet.dart';
import 'wallet/vault.dart';
import 'wallet/ffi_wallet.dart';
import 'wallet/network.dart';
import 'wallet/wallet_service.dart';

/// Development: set CAMO_WALLET_LIB (path to libcamo_wallet.so), CAMO_WALLET (wallet file) and CAMO_NODE
/// (host:port) to run a real wallet (setup / unlock screens first); CAMO_NETWORK = mainnet|stagenet|testnet
/// (default stagenet). Without them the app opens straight on demo data.
void main() {
  final env = Platform.environment;
  WalletVault? vault;
  if (env['CAMO_WALLET_LIB'] != null && env['CAMO_WALLET'] != null && env['CAMO_NODE'] != null) {
    final net = CamoNetwork.values.firstWhere((n) => n.name == env['CAMO_NETWORK'], orElse: () => CamoNetwork.stagenet);
    vault = FfiVault(libPath: env['CAMO_WALLET_LIB']!, path: env['CAMO_WALLET']!, network: net, node: env['CAMO_NODE']!);
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
                  ? SetupScreen(key: const ValueKey('setup'), vault: widget.vault!, onReady: (w) => setState(() => _wallet = w))
                  : HomeScreen(key: const ValueKey('home'), wallet: _wallet!),
        ),
      );
}
