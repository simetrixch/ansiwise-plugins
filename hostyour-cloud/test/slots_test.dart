import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// The one slot notation every filling in this plugin goes through.
void main() {
  group('what counts as a slot', () {
    test('a lower-case name in angle brackets, and nothing else', () {
      expect(slotsIn('argocd/<stage>/root-app.yaml'), <String>['stage']);
      expect(slotsIn('<a>/<b-2>/<a>'), <String>['a', 'b-2'], reason: 'each name once, in order');
      expect(
        slotsIn('<Stage> <STAGE> <under_score> <>'),
        isEmpty,
        reason: 'the grammar is the notation — what it rejects is not a slot',
      );
    });
  });

  group('filling', () {
    test('every named slot gets its value, a value without a slot changes nothing', () {
      expect(
        filledSlots('https://idp.<master-domain>/o/<client>/', <String, String>{
          'master-domain': 'm1.example.com',
          'client': 'headlamp',
          'unused': 'x',
        }),
        'https://idp.m1.example.com/o/headlamp/',
      );
    });
  });

  group('the leftover scan', () {
    test('reports what still looks like a slot, misspellings included', () {
      // Broader than the grammar on purpose: a mis-cased or misspelled name matches no declared
      // slot, and a scan that only knew the grammar would wave it through to the tool.
      expect(leftoverSlotIn('a <verison> b'), '<verison>');
      expect(leftoverSlotIn('a <Stage> b'), '<Stage>');
      expect(leftoverSlotIn('nothing here'), isNull);
    });
  });
}
