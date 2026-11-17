import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/wallet/address_book.dart';
import 'package:ghillie/wallet/demo_wallet.dart';
import 'package:ghillie/wallet/subscriptions.dart';

const miner = 'QRDxe3VEFdw3pgkqkDJwy8BCzRJxf49EwC7xCPBGchvF55si1tj45rreWb1bU1MoZp9iWaKHHQHV4gHutjkxuQrR1PN3Lxcb9';
const monero = '44AFFq5kSiGBoZ4NMDwYtN18obc8AemS33DBLWs3H7otXft3XjrpDtQGv7SqSsaBYBb98uNbr2VBBEt7f2wfn3RVGQBEP3A';

void main() {
  test('saved per wallet, sorted exchanges first, separate from subscriptions', () async {
    final store = MemorySubscriptionStore();
    final b = AddressBook('w', store: store);
    await b.load();
    await b.put(const SavedAddress(id: '1', kind: ContactKind.person, name: 'Alex', address: miner));
    await b.put(const SavedAddress(id: '2', kind: ContactKind.exchange, name: 'Some Exchange', address: miner));
    final again = AddressBook('w', store: store);
    await again.load();
    expect(again.items.map((e) => e.name), ['Some Exchange', 'Alex']);
    final subs = SubscriptionBook('w', store: store);
    await subs.load();
    expect(subs.items, isEmpty);
    await again.remove('2');
    expect(again.items.single.name, 'Alex');
  });

  testWidgets('Settings > Saved addresses: add an exchange; Send > Saved fills the address', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    subscriptionStore = MemorySubscriptionStore();
    await t.pumpWidget(GhillieApp(wallet: DemoWallet(), showIntro: false));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('settings-saved')));
    await t.pumpAndSettle();
    expect(find.text('Nothing saved yet.'), findsOneWidget);

    await t.tap(find.byKey(const Key('ab-add-exchange')));
    await t.pumpAndSettle();
    expect(find.textContaining('change deposit addresses'), findsOneWidget);
    await t.tap(find.byKey(const Key('ab-save')));
    await t.pump();
    expect(find.textContaining("exchange's name"), findsOneWidget);
    await t.enterText(find.byKey(const Key('ab-name')), 'My Exchange');
    await t.enterText(find.byKey(const Key('ab-address')), monero);
    await t.tap(find.byKey(const Key('ab-save')));
    await t.pump();
    expect(find.textContaining('not a CAMO address'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ab-address')), miner);
    await t.tap(find.byKey(const Key('ab-save')));
    await t.pumpAndSettle();
    expect(find.text('My Exchange'), findsOneWidget);
    expect(find.textContaining('Exchange · QRDxe3VE'), findsOneWidget);

    // back to home, open Send, pick the saved exchange
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('send-saved')));
    await t.pumpAndSettle();
    expect(find.text('SEND TO'), findsOneWidget);
    await t.tap(find.text('My Exchange'));
    await t.pumpAndSettle();
    expect(find.text('SEND CAMO'), findsOneWidget);
    expect(find.text(miner), findsOneWidget);
  });
}
