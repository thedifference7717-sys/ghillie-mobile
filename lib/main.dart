// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/scope_intro.dart';
import 'ui/theme.dart';
import 'dart:io';
import 'wallet/demo_wallet.dart';
import 'wallet/ffi_wallet.dart';
import 'wallet/network.dart';
import 'wallet/wallet_service.dart';

/// Development: set CAMO_WALLET_LIB (path to libcamo_wallet.so), CAMO_WALLET (wallet file) and CAMO_NODE
/// (host:port) to run a real wallet; CAMO_NETWORK = mainnet|stagenet|testnet (default stagenet).
/// Without them the app runs on demo data.
void main() {
  final env = Platform.environment;
  WalletService wallet = DemoWallet();
  if (env['CAMO_WALLET_LIB'] != null && env['CAMO_WALLET'] != null && env['CAMO_NODE'] != null) {
    final net = CamoNetwork.values.firstWhere((n) => n.name == env['CAMO_NETWORK'], orElse: () => CamoNetwork.stagenet);
    wallet = FfiWallet.openOrCreate(libPath: env['CAMO_WALLET_LIB']!, path: env['CAMO_WALLET']!, network: net, node: env['CAMO_NODE']!);
  }
  runApp(GhillieApp(wallet: wallet, showIntro: env['CAMO_SKIP_INTRO'] == null));
}

class GhillieApp extends StatefulWidget {
  final WalletService wallet;
  final bool showIntro;
  const GhillieApp({super.key, required this.wallet, this.showIntro = true});
  @override
  State<GhillieApp> createState() => _GhillieAppState();
}

class _GhillieAppState extends State<GhillieApp> {
  late bool _intro = widget.showIntro;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ghillie',
        debugShowCheckedModeBanner: false,
        theme: ghillieTheme(),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _intro
              ? ScopeIntro(key: const ValueKey('intro'), onEnter: () => setState(() => _intro = false))
              : HomeScreen(key: const ValueKey('home'), wallet: widget.wallet),
        ),
      );
}
