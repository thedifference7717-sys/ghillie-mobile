import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/screens/subscriptions_screen.dart';
import 'package:ghillie/wallet/amount.dart';
import 'package:ghillie/wallet/demo_wallet.dart';
import 'package:ghillie/wallet/subscriptions.dart';

const miner = 'QRDxe3VEFdw3pgkqkDJwy8BCzRJxf49EwC7xCPBGchvF55si1tj45rreWb1bU1MoZp9iWaKHHQHV4gHutjkxuQrR1PN3Lxcb9';

void main() {
  Subscription sub({int day = 10, String? paid}) =>
      Subscription(id: 'a', name: 'VPN', address: miner, amount: CamoAmount.tryParse('10')!, day: day, paidMonth: paid);

  test('due on its day and after, until paid that month', () {
    expect(sub().isDue(DateTime(2027, 1, 9)), isFalse);
    expect(sub().isDue(DateTime(2027, 1, 10)), isTrue);
    expect(sub().isDue(DateTime(2027, 1, 25)), isTrue);
    expect(sub(paid: '2027-01').isDue(DateTime(2027, 1, 25)), isFalse);
    expect(sub(paid: '2027-01').isDue(DateTime(2027, 2, 10)), isTrue);
    expect(sub().nextDate(DateTime(2027, 1, 9)), DateTime(2027, 1, 10));
    expect(sub(paid: '2027-01').nextDate(DateTime(2027, 1, 12)), DateTime(2027, 2, 10));
    expect(sub(paid: '2027-12').nextDate(DateTime(2027, 12, 20)), DateTime(2028, 1, 10));
  });

  test('day 29-31 falls on the last day of shorter months', () {
    expect(sub(day: 31).isDue(DateTime(2027, 2, 27)), isFalse);
    expect(sub(day: 31).isDue(DateTime(2027, 2, 28)), isTrue);
    expect(sub(day: 31).isDue(DateTime(2027, 4, 30)), isTrue);
    expect(sub(day: 31).nextDate(DateTime(2027, 1, 31)), DateTime(2027, 1, 31));
    expect(sub(day: 31, paid: '2027-01').nextDate(DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
    expect(sub(day: 30, paid: '2028-01').nextDate(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
  });

  test('saved per wallet, survive a reload; broken data is ignored', () async {
    final store = MemorySubscriptionStore();
    final b = SubscriptionBook('w1', store: store);
    await b.load();
    await b.put(sub());
    await b.markPaid('a', DateTime(2027, 3, 11));
    final again = SubscriptionBook('w1', store: store);
    await again.load();
    expect(again.items.single.paidMonth, '2027-03');
    final other = SubscriptionBook('w2', store: store);
    await other.load();
    expect(other.items, isEmpty);
    await store.write('w3', 'not json');
    final broken = SubscriptionBook('w3', store: store);
    await broken.load();
    expect(broken.items, isEmpty);
  });

  testWidgets('add a subscription from home; it shows as due; Pay opens Send filled in; delete', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    subscriptionStore = MemorySubscriptionStore();
    await t.pumpWidget(GhillieApp(wallet: DemoWallet(), showIntro: false));
    await t.pumpAndSettle();
    expect(find.text('None yet'), findsOneWidget);
    await t.tap(find.byKey(const Key('home-subscriptions')));
    await t.pumpAndSettle();
    expect(find.text('SUBSCRIPTIONS'), findsOneWidget);

    await t.tap(find.byKey(const Key('sub-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sub-save')));
    await t.pump();
    expect(find.textContaining('Give it a name'), findsOneWidget);
    await t.enterText(find.byKey(const Key('sub-name')), 'VPN');
    await t.enterText(find.byKey(const Key('sub-address')), '44AFFq5kSiGBoZ4NMDwYtN18obc8AemS33DBLWs3H7otXft3XjrpDtQGv7SqSsaBYBb98uNbr2VBBEt7f2wfn3RVGQBEP3A');
    await t.enterText(find.byKey(const Key('sub-amount')), '10');
    await t.tap(find.byKey(const Key('sub-save')));
    await t.pump();
    expect(find.textContaining('not a CAMO address'), findsOneWidget); // Monero address refused
    await t.enterText(find.byKey(const Key('sub-address')), miner);
    await t.tap(find.byKey(const Key('sub-save')));
    await t.pumpAndSettle();
    // the day defaults to today, so it is due right away
    expect(find.text('VPN'), findsOneWidget);
    expect(find.text('DUE NOW'), findsOneWidget);

    await t.tap(find.text('Pay'));
    await t.pumpAndSettle();
    expect(find.text('SEND CAMO'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // amount filled in
    expect(find.textContaining(miner), findsWidgets);
    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();
    expect(find.text('DUE NOW'), findsOneWidget); // not sent, so still due

    await t.tap(find.text('VPN'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sub-delete')));
    await t.pumpAndSettle();
    expect(find.text('VPN'), findsNothing);
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    expect(find.text('None yet'), findsOneWidget);
  });

  testWidgets('a paid subscription shows its next date and "Pay now"', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final book = SubscriptionBook('w', store: MemorySubscriptionStore());
    await book.load();
    await book.put(sub(day: 5, paid: '2027-01'));
    await t.pumpWidget(MaterialApp(
        home: SubscriptionsScreen(wallet: DemoWallet(), book: book, now: () => DateTime(2027, 1, 20))));
    await t.pumpAndSettle();
    expect(find.textContaining('Next: Feb 5'), findsOneWidget);
    expect(find.textContaining('paid this month'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);
  });
}
