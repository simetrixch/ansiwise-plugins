import 'package:ansiwise_host/src/steps/host/quoted_slot.dart';
import 'package:test/test.dart';

/// Which slots of a template stand inside quoting that the value would close.
///
/// A template is filled by substituting text, so a slot inside a quoted run of text is a slot whose
/// value has to not carry the character that closes it. `to: '<recipients>'` and an address with an
/// apostrophe in its local part end the quoting four characters early, and what fails afterwards is
/// whatever reads the whole file — nowhere near the line the value came from.
///
/// Every case below pairs the shape with its INNOCENT NEIGHBOUR: the same value where it is
/// harmless, or the same place with a value that carries nothing. Without those a scan that reported
/// every slot, or one that reported none, would pass half of this file.
void main() {
  group('a slot inside single quoting', () {
    test('is reported when the value carries an apostrophe', () {
      final List<QuotingBroken> broken = quotingBrokenIn("to: '<recipients>'\n", <String, String>{
        'recipients': "o'brien@example.com",
      });

      expect(broken, hasLength(1));
      expect(broken.single.line, 1);
      expect(broken.single.slot, '<recipients>');
      expect(broken.single.quote, "'");
    });

    test('THE INNOCENT NEIGHBOUR: an address without one is left alone', () {
      expect(
        quotingBrokenIn("to: '<recipients>'\n", <String, String>{'recipients': 'a@example.com'}),
        isEmpty,
      );
    });

    test('is reported inside a flow list, where the apostrophe ends the list as well', () {
      // The shape that was measured: the value ends the scalar AND the sequence it stands in, so
      // the reader fails on the line the sequence opened on rather than on this one.
      expect(
        quotingBrokenIn("alertRecipients: ['<recipients>']\n", <String, String>{
          'recipients': "o'brien@example.com",
        }),
        hasLength(1),
      );
    });

    test('THE INNOCENT NEIGHBOUR: the same value outside quoting is ordinary text', () {
      // Nothing is open where the slot stands, so the apostrophe closes nothing and the line reads
      // back exactly as it was written.
      expect(
        quotingBrokenIn('to: <recipients>\n', <String, String>{
          'recipients': "o'brien@example.com",
        }),
        isEmpty,
      );
    });

    test('THE INNOCENT NEIGHBOUR: a double quote does not close single quoting', () {
      expect(
        quotingBrokenIn("to: '<recipients>'\n", <String, String>{'recipients': 'a"b@example.com'}),
        isEmpty,
      );
    });
  });

  group('a slot inside double quoting', () {
    test('is reported when the value carries a double quote', () {
      final List<QuotingBroken> broken = quotingBrokenIn('note: "<note>"\n', <String, String>{
        'note': 'he said "hi"',
      });

      expect(broken, hasLength(1));
      expect(broken.single.quote, '"');
    });

    test('THE INNOCENT NEIGHBOUR: an apostrophe does not close double quoting', () {
      expect(quotingBrokenIn('note: "<note>"\n', <String, String>{'note': "o'brien"}), isEmpty);
    });

    test('is reported when an escaped quote stands between the opening one and the slot', () {
      // `\"` does not close the quoting, so the slot is still inside it. ONE escaped quote before
      // the slot is what tells the two readings apart: a walk that counted every quote character
      // would find two here, call the quoting closed, and wave the value through.
      expect(
        quotingBrokenIn(
          r'command: "run \"<name>\""'
          '\n',
          <String, String>{'name': 'a "quoted" name'},
        ),
        hasLength(1),
      );
    });

    test('THE INNOCENT NEIGHBOUR: quoting that was closed before the slot leaves it outside', () {
      expect(
        quotingBrokenIn('note: "hi" <note>\n', <String, String>{'note': 'a "quoted" name'}),
        isEmpty,
      );
    });
  });

  group('what the scan passes over', () {
    test('a slot this run holds no value for', () {
      // Its line is the framework's to drop or to refuse by name, and either way nothing is
      // substituted here for a quote character to come out of.
      expect(quotingBrokenIn("to: '<recipients>'\n", const <String, String>{}), isEmpty);
    });

    test('a doubled apostrophe closes and reopens, so a slot after the scalar stands outside', () {
      expect(
        quotingBrokenIn("note: 'it''s' <recipients>\n", <String, String>{
          'recipients': "o'brien@example.com",
        }),
        isEmpty,
      );
    });
  });

  group('what it reports', () {
    test('the line it stands on, counted from one', () {
      final List<QuotingBroken> broken = quotingBrokenIn(
        "fqdn: <fqdn>\nto: '<recipients>'\n",
        <String, String>{'fqdn': 'm1.example.com', 'recipients': "o'brien@example.com"},
      );

      expect(broken.single.line, 2);
    });

    test('an optional slot with the mark the template wrote', () {
      final List<QuotingBroken> broken = quotingBrokenIn("note: '<note?>'\n", <String, String>{
        'note': "o'brien",
      });

      expect(broken.single.slot, '<note?>');
    });

    test('every broken slot at once, so one run names all of them', () {
      final List<QuotingBroken> broken = quotingBrokenIn(
        "to: '<recipients>'\nnote: \"<note>\"\n",
        <String, String>{'recipients': "o'brien@example.com", 'note': 'he said "hi"'},
      );

      expect(broken.map((QuotingBroken each) => each.slot), <String>['<recipients>', '<note>']);
    });
  });
}
