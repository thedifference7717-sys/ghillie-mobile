// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Wraps screens that show secrets (the 25 words). While shown:
//  * Android: FLAG_SECURE (no screenshots, screen recording or recents thumbnail), via MainActivity.
//  * every platform: when the app is not in front (app switcher, notification shade), the content is covered,
//    so the words never appear in the iOS app-switcher snapshot.
//  * iOS (apps cannot block screenshots there): AppDelegate reports a screenshot ('screenshot') and screen
//    recording or mirroring ('captured', true/false). A screenshot brings up a warning to delete it; while the
//    screen is recorded or mirrored, the content is covered.
//  * [onLeave]: called once when the app actually leaves the screen (home button, another app, phone locked),
//    so a screen can close itself and drop the words. Not on 'inactive' (Face ID prompt, Control Center,
//    notification shade, app switcher): those only cover the content.
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
  final VoidCallback? onLeave;
  const Sensitive({super.key, required this.child, this.onLeave});
  @override
  State<Sensitive> createState() => _SensitiveState();
}

/// Screens showing secrets right now (normally zero or one).
final _shown = <_SensitiveState>[];

Future<dynamic> _fromPlatform(MethodCall call) async {
  if (_shown.isEmpty) return null;
  final top = _shown.last;
  switch (call.method) {
    case 'screenshot':
      top._warnScreenshot(blanked: call.arguments == true);
    case 'captured':
      top._setCaptured(call.arguments == true);
  }
  return null;
}

class _SensitiveState extends State<Sensitive> with WidgetsBindingObserver {
  bool _background = false;
  bool _captured = false;
  bool _warning = false;
  bool _left = false;
  bool get _covered => _background || _captured || (_left && widget.onLeave != null); // closing: never show again

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shown.add(this);
    _channel.setMethodCallHandler(_fromPlatform);
    _secure(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shown.remove(this);
    _secure(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state != AppLifecycleState.resumed;
    if (bg != _background) setState(() => _background = bg);
    if ((state == AppLifecycleState.hidden || state == AppLifecycleState.paused) && !_left) {
      _left = true;
      widget.onLeave?.call();
    }
  }

  void _setCaptured(bool on) {
    if (mounted && on != _captured) setState(() => _captured = on);
  }

  Future<void> _warnScreenshot({bool blanked = false}) async {
    if (!mounted || _warning) return;
    _warning = true;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('screenshot-warning'),
        backgroundColor: Gc.panel,
        title: Text('SCREENSHOT TAKEN', style: Gt.pixel(26, color: blanked ? Gc.amber : Gc.danger)),
        content: Text(
          blanked
              ? 'Ghillie blanked this screen, so the screenshot should show only black. Check it in Photos, '
                  'then delete it, and delete it again from Albums > Recently Deleted. Write the words on paper.'
              : 'Your 25 words are now in your Photos, and maybe in iCloud. Anyone who sees that picture can take '
                  'your coins.\n\nOpen Photos, delete the screenshot, then delete it again from Albums > Recently '
                  'Deleted. Write the words on paper instead.',
          style: Gt.body(15, color: Gc.text2),
        ),
        actions: [
          TextButton(
            key: const Key('screenshot-warning-ok'),
            onPressed: () => Navigator.of(c).pop(),
            child: Text('I WILL DELETE IT', style: Gt.pixel(20, color: Gc.amber)),
          ),
        ],
      ),
    );
    _warning = false;
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
