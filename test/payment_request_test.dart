import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
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
}
