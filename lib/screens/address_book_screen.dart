// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../wallet/address_book.dart';
import '../wallet/payment_uri.dart';
import '../wallet/wallet_service.dart';

/// Saved addresses. With [pick], tapping an entry returns its address (used by Send).
class AddressBookScreen extends StatelessWidget {
  final WalletService wallet;
  final AddressBook book;
  final bool pick;
  const AddressBookScreen({super.key, required this.wallet, required this.book, this.pick = false});

  Future<void> _edit(BuildContext context, {SavedAddress? s, ContactKind kind = ContactKind.exchange}) async {
    final r = await showDialog<SavedAddress>(
        context: context, builder: (_) => _EditDialog(wallet: wallet, existing: s, kind: s?.kind ?? kind));
    if (r == null) return;
    r.name.isEmpty ? await book.remove(r.id) : await book.put(r); // empty name = Delete was tapped
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: book,
            builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ScreenHeader(pick ? 'SEND TO' : 'SAVED ADDRESSES'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const ShieldLine('Stored encrypted on this phone. An exchange that knows who you are can see what you '
                      'deposit to it; Ghillie cannot hide that part.'),
                  const SizedBox(height: 14),
                  if (book.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Nothing saved yet.', style: Gt.body(14, color: Gc.text3)),
                    ),
                  for (final s in book.items) ...[
                    _Row(
                      s: s,
                      onTap: pick ? () => Navigator.pop(context, s.address) : () => _edit(context, s: s),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: const Key('ab-add-exchange'),
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.account_balance_outlined, color: Gc.text2),
                    label: Text('ADD EXCHANGE', style: Gt.pixel(20)),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('ab-add-other'),
                    onPressed: () => _edit(context, kind: ContactKind.person),
                    icon: const Icon(Icons.person_add_alt, color: Gc.text2),
                    label: Text('ADD PERSON OR SHOP', style: Gt.pixel(20)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final SavedAddress s;
  final VoidCallback onTap;
  const _Row({required this.s, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        key: Key('ab-${s.id}'),
        onTap: onTap,
        child: NotchBox(
          borderColor: Gc.line2,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            Icon(
                switch (s.kind) {
                  ContactKind.exchange => Icons.account_balance_outlined,
                  ContactKind.person => Icons.person_outline,
                  ContactKind.shop => Icons.storefront_outlined,
                  ContactKind.other => Icons.bookmark_outline,
                },
                color: Gc.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: Gt.body(16, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text('${s.kind.label} · ${shortAddress(s.address)}', style: Gt.mono(12, color: Gc.text3)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Gc.text3),
          ]),
        ),
      );
}

class _EditDialog extends StatefulWidget {
  final WalletService wallet;
  final SavedAddress? existing;
  final ContactKind kind;
  const _EditDialog({required this.wallet, this.existing, required this.kind});
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late ContactKind _kind = widget.kind;
  String? _error;

  void _save() {
    final address = PaymentUri.tryParse(_address.text)?.address ?? _address.text.trim();
    if (_name.text.trim().isEmpty) {
      return setState(() => _error = _kind == ContactKind.exchange ? 'Type the exchange\'s name.' : 'Give it a name.');
    }
    if (!widget.wallet.isValidAddress(address)) return setState(() => _error = 'That is not a CAMO address for this network.');
    Navigator.pop(
        context,
        SavedAddress(
            id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
            kind: _kind,
            name: _name.text.trim(),
            address: address));
  }

  @override
  Widget build(BuildContext context) {
    // label above the box: a floating label would be crossed by the notched border
    Widget field(String label, Widget box) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label, style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500))),
            box,
          ]),
        );
    final exchange = _kind == ContactKind.exchange;
    return AlertDialog(
      title: Text(widget.existing != null ? 'EDIT ADDRESS' : (exchange ? 'ADD EXCHANGE' : 'ADD ADDRESS'), style: Gt.pixel(24)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!exchange || widget.existing != null)
            field(
                'Type',
                DropdownButton<ContactKind>(
                  key: const Key('ab-kind'),
                  value: _kind,
                  isExpanded: true,
                  items: [for (final k in ContactKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                  onChanged: (k) => setState(() => _kind = k ?? _kind),
                )),
          field(
              exchange ? 'Exchange name' : 'Name',
              TextField(
                  key: const Key('ab-name'),
                  controller: _name,
                  decoration: InputDecoration(hintText: exchange ? 'The exchange you deposit to' : 'Alex, coffee shop…'))),
          field(
              exchange ? 'Your CAMO deposit address there' : 'CAMO address',
              TextField(
                  key: const Key('ab-address'),
                  controller: _address,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: Gt.mono(13))),
          if (exchange)
            Text('Exchanges sometimes change deposit addresses. Check it on the exchange before each deposit.',
                style: Gt.body(12, color: Gc.amber)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: Gt.body(13, color: Gc.danger))),
        ]),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const Key('ab-delete'),
            onPressed: () => Navigator.pop(
                context, SavedAddress(id: widget.existing!.id, kind: _kind, name: '', address: widget.existing!.address)),
            child: Text('Delete', style: Gt.body(14, color: Gc.danger)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('ab-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
