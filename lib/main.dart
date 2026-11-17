// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'screens/send_screen.dart';
import 'wallet/payment_uri.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/scope_intro.dart';
import 'ui/app_lock.dart';
import 'wallet/password_check.dart';
import 'ui/theme.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'screens/setup_screen.dart';
import 'wallet/demo_wallet.dart';
import 'wallet/quick_unlock.dart';
import 'wallet/reminders.dart';
import 'wallet/subscriptions.dart';
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

/// The wallet locks itself after this long without a touch, or after this long in the background (Anthony, Nov 17: 7:17).
const autoLockAfter = Duration(minutes: 7, seconds: 17);

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
      subscriptionStore = DeviceSubscriptionStore();
      paymentReminders = DeviceReminders();
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
  /// camo: links opened from outside (tests pass their own stream; null = the platform's, via app_links).
  final Stream<String>? links;
  const GhillieApp({super.key, this.vault, this.wallet, this.showIntro = true, this.links})
      : assert(vault != null || wallet != null);
  @override
  State<GhillieApp> createState() => _GhillieAppState();
}

class _GhillieAppState extends State<GhillieApp> with WidgetsBindingObserver {
  late bool _intro = widget.showIntro;
  late WalletService? _wallet = widget.wallet;
  bool _turnOnQuick = false;
  bool _lockedByUser = false; // after Settings > Lock, Face ID waits for a tap instead of popping up at once

  Timer? _idle;
  DateTime? _wentAway;
  final _nav = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _links;
  PaymentUri? _pendingPay; // a camo: link that arrived; opened on Send once the wallet is unlocked

  @override
  void initState() {
    super.initState();
    if (widget.vault != null) {
      AppLock.lock = _lock;
      WidgetsBinding.instance.addObserver(this);
    }
    try {
      _links = (widget.links ?? AppLinks().stringLinkStream).listen(_onLink, onError: (_) {});
    } catch (_) {
      // no platform link support (desktop dev builds)
    }
  }

  /// A tapped camo: link: Send opens filled in (after unlock); nothing is ever paid without the normal review.
  void _onLink(String link) {
    final p = PaymentUri.tryParse(link);
    if (p == null) return;
    _pendingPay = p;
    _openPendingPay();
  }

  void _openPendingPay() {
    final p = _pendingPay, w = _wallet;
    if (p == null || w == null || _intro) return;
    _pendingPay = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.currentState?.push(MaterialPageRoute(builder: (_) => SendScreen(wallet: w, prefill: p)));
    });
    WidgetsBinding.instance.scheduleFrame(); // a link can arrive while nothing else is redrawing
  }

  @override
  void dispose() {
    if (AppLock.lock == _lock) AppLock.lock = null;
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _links?.cancel();
    super.dispose();
  }

  /// Auto-lock: any touch restarts the 13-minute clock while a real wallet is open.
  void _touched() {
    _idle?.cancel();
    if (widget.vault == null || _wallet == null) return;
    _idle = Timer(autoLockAfter, () {
      if (mounted && _wallet != null) _lock();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wentAway ??= DateTime.now(); // timers may not run while the app is in the background
    } else if (state == AppLifecycleState.resumed) {
      final away = _wentAway;
      _wentAway = null;
      if (away != null && _wallet != null && DateTime.now().difference(away) >= autoLockAfter) {
        _lock();
      } else {
        _touched();
      }
    }
  }

  void _lock({bool turnOnQuickUnlock = false}) {
    PasswordCheck.forget();
    final w = _wallet;
    setState(() {
      _wallet = null;
      _turnOnQuick = turnOnQuickUnlock;
      // Lock goes back to the opening screen (the scope), like a fresh start; after it, Face ID is offered as at app
      // start. Turning Face ID on from Settings skips the scope and goes straight to the password.
      _intro = widget.showIntro && !turnOnQuickUnlock;
      _lockedByUser = !_intro;
    });
    _idle?.cancel();
    w?.dispose(); // closes and saves the wallet file; the keys leave memory
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ghillie',
        navigatorKey: _nav,
        debugShowCheckedModeBanner: false,
        theme: ghillieTheme(),
        builder: (c, child) =>
            Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _touched(), child: child),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _intro
              ? ScopeIntro(key: const ValueKey('intro'), onEnter: () {
                  setState(() => _intro = false);
                  _openPendingPay();
                })
              : _wallet == null
                  ? SetupScreen(
                      key: ValueKey('setup-$_turnOnQuick-$_lockedByUser'),
                      vault: widget.vault!,
                      rememberNext: _turnOnQuick,
                      autoQuickUnlock: !_lockedByUser,
                      onReady: (w) {
                        setState(() => _wallet = w);
                        _touched();
                        _openPendingPay();
                      })
                  : HomeScreen(key: const ValueKey('home'), wallet: _wallet!),
        ),
      );
}
