// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Wraps screens that show secrets (the 25 words). While shown:
//  * Android: FLAG_SECURE (no screenshots, screen recording or recents thumbnail), via MainActivity.
//  * every platform: when the app is not in front (app switcher, notification shade), the content is covered,
//    so the words never appear in the iOS app-switcher snapshot.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';

const _channel = MethodChannel('org.camocoin.ghillie/secure');

Future<void> _secure(bool on) async {
  try {
    await _channel.invokeMethod(on ? 'on' : 'off');
  } on MissingPluginException {
    // iOS, desktop, tests: nothing to call; the cover below still applies
  } on PlatformException {
    // never block the screen over this
  }
}

class Sensitive extends StatefulWidget {
  final Widget child;
  const Sensitive({super.key, required this.child});
  @override
  State<Sensitive> createState() => _SensitiveState();
}

class _SensitiveState extends State<Sensitive> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secure(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _secure(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ColoredBox(
              key: const Key('sensitive-cover'),
              color: Gc.bg,
              child: Center(child: Text('HIDDEN', style: Gt.pixel(32, color: Gc.text3))),
            ),
          ),
      ]);
}
