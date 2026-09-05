import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A key of a YAML file, addressed by a dotted path, read for one value and for anything but it.
///
/// The five readings the issue names each have a stated answer here, and the four that are not an
/// answer are refused rather than answered false. A condition that answers false where it means "I
/// could not read this" switches off every row waiting on it, and the only trace is one line saying
/// the condition did not hold.
void main() {
  const String map = '/srv/subject/cluster.yaml';
  const String key = 'certificates.issuer.name';
  const String wanted = 'subject-public';

  const String document =
      'certificates:\n'
      '  issuer:\n'
      '    name: $wanted\n'
      '    ready: true\n'
      '    retries: 3\n'
      '    empty:\n'
      '  authorities:\n'
      '    - one\n'
      '    - two\n';

  Future<PredicateResult> ask(String text, {required bool matching, String path = key}) =>
      YamlKeyHasValue(path: map, key: path, value: wanted, holdsWhenEqual: matching).evaluate(
        HostMachine(
          files: FakeFiles(<String, String>{map: text}),
        ).contextFor(const StepName('yaml_key_has_value')),
      );

  group('reading for one value', () {
    test('THE INNOCENT CASE: the key carries it, and the condition holds', () async {
      final PredicateResult result = await ask(document, matching: true);

      expect(result.held, isTrue);
      expect(
        result.because,
        allOf(contains(map), contains(key), contains(wanted)),
        reason: 'the plan an operator reads has to say which value switched these rows on',
      );
    });

    test('another value does not hold, and the record says what stood there', () async {
      final PredicateResult result = await ask(
        document.replaceAll(wanted, 'subject-local'),
        matching: true,
      );

      expect(result.held, isFalse);
      expect(result.because, contains('subject-local'));
    });

    test('a key written with nothing under it does not hold, and is NOT refused', () async {
      // The file a fill row has not reached yet says this cluster does not carry the stated value,
      // which is a fact about it and not a gap in it. Refusing here would stop the run whose job is
      // to fill it.
      final PredicateResult result = await ask(
        document,
        matching: true,
        path: 'certificates.issuer.empty',
      );

      expect(result.held, isFalse);
      expect(result.because, contains('nothing at all'));
    });

    test('a boolean and a number are compared as the file wrote them', () async {
      for (final (String path, String value) in <(String, String)>[
        ('certificates.issuer.ready', 'true'),
        ('certificates.issuer.retries', '3'),
      ]) {
        final PredicateResult result =
            await YamlKeyHasValue(
              path: map,
              key: path,
              value: value,
              holdsWhenEqual: true,
            ).evaluate(
              HostMachine(
                files: FakeFiles(<String, String>{map: document}),
              ).contextFor(const StepName('yaml_key_has_value')),
            );

        expect(
          result.held,
          isTrue,
          reason: 'a declarative tree writes its switches unquoted, and $path is one of them',
        );
      }
    });
  });

  group('reading for anything but that value', () {
    test('THE INNOCENT CASE: another value holds', () async {
      final PredicateResult result = await ask(
        document.replaceAll(wanted, 'subject-local'),
        matching: false,
      );

      expect(result.held, isTrue);
    });

    test('the stated value does not hold', () async {
      final PredicateResult result = await ask(document, matching: false);

      expect(result.held, isFalse);
    });
  });

  group('what is not an answer is refused, in both shapes', () {
    for (final bool shape in <bool>[true, false]) {
      test('a file that is not on this machine, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          YamlKeyHasValue(path: map, key: key, value: wanted, holdsWhenEqual: shape).evaluate(
            HostMachine(
              files: FakeFiles(<String, String>{}),
            ).contextFor(const StepName('yaml_key_has_value')),
          ),
          throwsA(isA<ConditionUnanswerable>()),
          reason: 'a missing file says nothing about this machine, in either direction',
        );
      });

      test('a file that does not parse, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          ask('certificates:\n  issuer:\n   name: "unterminated\n', matching: shape),
          throwsA(
            isA<ConditionUnanswerable>().having(
              (ConditionUnanswerable refusal) => refusal.because,
              'because',
              allOf(contains(map), contains('YAML')),
            ),
          ),
        );
      });

      test('a path that names nothing, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          ask(document, matching: shape, path: 'certificates.issuer.authority'),
          throwsA(
            isA<ConditionUnanswerable>().having(
              (ConditionUnanswerable refusal) => refusal.because,
              'because',
              contains('certificates.issuer.authority'),
            ),
          ),
        );
      });

      test('a path that leaves the maps, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          ask(document, matching: shape, path: 'certificates.issuer.name.deeper'),
          throwsA(isA<ConditionUnanswerable>()),
          reason: 'a scalar has nothing under it, and a step further in names nothing',
        );
      });

      test('a value that is a list, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          ask(document, matching: shape, path: 'certificates.authorities'),
          throwsA(
            isA<ConditionUnanswerable>().having(
              (ConditionUnanswerable refusal) => refusal.because,
              'because',
              contains('list or a map'),
            ),
          ),
        );
      });

      test('a value that is a map, reading for ${shape ? 'it' : 'anything else'}', () {
        expect(
          ask(document, matching: shape, path: 'certificates.issuer'),
          throwsA(isA<ConditionUnanswerable>()),
        );
      });
    }
  });

  group('it changes nothing', () {
    test('no write, no delete and no command, on the answer and on the refusal alike', () async {
      final FakeFiles files = FakeFiles(<String, String>{map: document});
      final HostMachine machine = HostMachine(files: files);

      await const YamlKeyHasValue(
        path: map,
        key: key,
        value: wanted,
        holdsWhenEqual: true,
      ).evaluate(machine.contextFor(const StepName('yaml_key_has_value')));
      await expectLater(
        const YamlKeyHasValue(
          path: map,
          key: 'certificates.issuer',
          value: wanted,
          holdsWhenEqual: true,
        ).evaluate(machine.contextFor(const StepName('yaml_key_has_value'))),
        throwsA(isA<ConditionUnanswerable>()),
      );

      expect(files.written, isEmpty);
      expect(files.deleted, isEmpty);
      expect(files.asRoot, isEmpty, reason: 'a condition reads what any account may read');
      expect(machine.shell.commands, isEmpty);
    });
  });

  group('a path carrying a slot', () {
    test('is filled from the answer the row names', () {
      const YamlKeyHasValue bound = YamlKeyHasValue(
        path: '/srv/subject/cluster.<stage>.yaml',
        key: key,
        value: wanted,
        holdsWhenEqual: true,
        runAnswer: 'stage',
      );

      expect(
        bound.pathIn(const Arguments(<String, Object>{'stage': 'second'})),
        '/srv/subject/cluster.second.yaml',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a path with no slot is left exactly as written', () {
      const YamlKeyHasValue plain = YamlKeyHasValue(
        path: map,
        key: key,
        value: wanted,
        holdsWhenEqual: true,
      );

      expect(plain.pathIn(const Arguments(<String, Object>{'stage': 'prod'})), map);
    });
  });

  group('the dotted reader itself', () {
    test('THE PLANTED DEFECT: a key read out of the wrong file answers about that file', () async {
      // What a reader taking its path from the wrong place produces: the same key stands in two
      // files under two values, and nothing in the answer would say which one was opened. The
      // condition names the path it read in every sentence, so the record cannot hide it.
      final PredicateResult here =
          await const YamlKeyHasValue(
            path: map,
            key: key,
            value: wanted,
            holdsWhenEqual: true,
          ).evaluate(
            HostMachine(
              files: FakeFiles(<String, String>{
                map: document,
                '/srv/subject/other.yaml': document.replaceAll(wanted, 'subject-local'),
              }),
            ).contextFor(const StepName('yaml_key_has_value')),
          );

      expect(here.held, isTrue);
      expect(here.because, contains(map));
      expect(here.because, isNot(contains('other.yaml')));
    });
  });
}
