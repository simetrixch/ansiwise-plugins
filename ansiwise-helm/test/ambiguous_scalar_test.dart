import 'package:ansiwise_helm/src/steps/ambiguous_scalar.dart';
import 'package:test/test.dart';

/// Which written scalars two readers of one values file disagree about.
///
/// helm reads YAML 1.1 and this package reads YAML 1.2. The two differ on a handful of scalars, and
/// a file carrying one means two things at once — which shows up not as an error but as a step that
/// installs a release perfectly and then reports for ever that the machine is not in the state it
/// produces.
void main() {
  group('a bare leading zero', () {
    test('is octal to helm and decimal here', () {
      // THE PLANTED DEFECT. 0400 is 256 to helm and 400 here, and it is the exact value a real
      // installation stopped on: the mode of a mounted key.
      final List<AmbiguousScalar> found = ambiguousScalarsIn('secret:\n  defaultMode: 0400\n');

      expect(found, hasLength(1));
      expect(found.single.line, 2);
      expect(found.single.written, '0400');
      expect(found.single.asHelmReads, contains('256'));
      expect(found.single.asHereRead, contains('400'));
    });

    test('is found in a list entry as well as after a key', () {
      final List<AmbiguousScalar> found = ambiguousScalarsIn('modes:\n  - 0755\n');

      expect(found, hasLength(1), reason: 'a list entry is a value like any other');
      expect(found.single.written, '0755');
    });
  });

  group('a word YAML 1.1 makes a boolean of', () {
    test('is a boolean to helm and text here', () {
      // THE SECOND PLANTED SHAPE, and a different mechanism from the one above: not a number read
      // in another base, but text one reader converts and the other does not.
      final List<AmbiguousScalar> found = ambiguousScalarsIn('metrics:\n  enabled: yes\n');

      expect(found, hasLength(1));
      expect(found.single.written, 'yes');
      expect(found.single.asHelmReads, contains('true'));
      expect(found.single.asHereRead, contains('"yes"'));
    });

    test('is caught however it is spelled', () {
      expect(ambiguousScalarsIn('a: NO\nb: On\nc: off\n'), hasLength(3));
    });
  });

  group('what is not a disagreement', () {
    test('a quoted scalar is text to both', () {
      // THE INNOCENT CASE, and it is the one the refusal asks for: quoting is the fix, so reporting
      // it would tell an operator to do what they have already done.
      expect(ambiguousScalarsIn('a: "0400"\nb: \'yes\'\n'), isEmpty);
    });

    test('the number both readers agree on is left alone', () {
      expect(ambiguousScalarsIn('defaultMode: 256\nreplicas: 0\nratio: 0.5\n'), isEmpty);
    });

    test('a key is text to both, whatever it is called', () {
      // A key is never converted by either reader, so a key called `no` is not a disagreement — and
      // a scanner that looked at whole lines would report one.
      expect(ambiguousScalarsIn('no: 1\n0400: a\n'), isEmpty);
    });

    test('a comment carries no value', () {
      expect(
        ambiguousScalarsIn('# defaultMode: 0400 is what this used to say\nmode: 256 # was 0400\n'),
        isEmpty,
      );
    });

    test('a colon inside text does not open a value', () {
      expect(ambiguousScalarsIn('note: "the ratio is 1:0400"\n'), isEmpty);
    });

    test('true and false are what both readers already agree on', () {
      expect(ambiguousScalarsIn('enabled: true\ndisabled: false\n'), isEmpty);
    });
  });
}
