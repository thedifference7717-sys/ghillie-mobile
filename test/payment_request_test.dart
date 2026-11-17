import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:ghillie/main.dart';
import 'package:ghillie/screens/receive_screen.dart';
import 'package:ghillie/wallet/demo_wallet.dart';
import 'package:ghillie/wallet/payment_uri.dart';

void main() {
  testWidgets('Receive: amount + note go into the link; Send shows the note to the payer', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(GhillieApp(wallet: DemoWallet(), showIntro: false));
    await t.pumpAndSettle();
    await t.tap(find.text('Receive'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('receive-share')), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '12.5');
    await t.enterText(find.byKey(const Key('receive-note')), 'Dinner & drinks');
    await t.pump();
    final link = find.byType(SelectableText).evaluate().map((e) => (e.widget as SelectableText).data!).single;
    final p = PaymentUri.tryParse(link)!;
    expect(p.amount!.toPlain(), '12.5');
    expect(p.description, 'Dinner & drinks');

    // the payer pastes it on Send
    Navigator.of(t.element(find.text('RECEIVE CAMO'))).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, link);
    await t.pump();
    expect(find.text('For: Dinner & drinks'), findsOneWidget);
    expect(find.text('12.5'), findsOneWidget);
  });

  test('share link: camocoin.org/pay with the request after #', () {
    final u = payPageUrl('camo:QRDx?tx_amount=2&tx_description=dinner & drinks');
    expect(u, startsWith('https://camocoin.org/pay#camo%3AQRDx'));
    expect(Uri.decodeComponent(u.split('#')[1]), 'camo:QRDx?tx_amount=2&tx_description=dinner & drinks');
  });

  testWidgets('a tapped camo: link opens Send filled in; monero: links are ignored', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final links = StreamController<String>();
    addTearDown(links.close);
    await t.pumpWidget(GhillieApp(wallet: DemoWallet(), showIntro: false, links: links.stream));
    await t.pumpAndSettle();
    links.add('monero:44AFFq5kSiGBoZ4NMDwYtN18obc8AemS33DBLWs3H7otXft3XjrpDtQGv7SqSsaBYBb98uNbr2VBBEt7f2wfn3RVGQBEP3A?tx_amount=1');
    await t.pumpAndSettle();
    expect(find.text('SEND CAMO'), findsNothing);
    links.add('camo:QRDxe3VEFdw3pgkqkDJwy8BCzRJxf49EwC7xCPBGchvF55si1tj45rreWb1bU1MoZp9iWaKHHQHV4gHutjkxuQrR1PN3Lxcb9?tx_amount=2&tx_description=dinner');
    await t.pumpAndSettle();
    expect(find.text('SEND CAMO'), findsOneWidget);
    expect(find.text('For: dinner'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
