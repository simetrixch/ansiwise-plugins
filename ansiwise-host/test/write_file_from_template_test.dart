import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A file rewritten from a template on every run, and what a rewrite must not take away.
///
/// The sibling of the create-only writer, and everything asserted here is the difference between
/// them. That one is finished when the file exists; this one is finished when the file holds what
/// this run renders. So the case that decides is a file that stands and says something else.
void main() {
  const String templatePath = 'ansiwise/templates/map.tpl';
  const String path = '/srv/checkout/map.yaml';

  /// Without a carried slot, so it can be rendered the first time the file is written.
  const String template =
      'fqdn: <fqdn>\n'
      'plane: <build-plane>\n'
      'to: <alert-recipients>\n'
      'note: <note?>\n';

  /// With one. A CARRIED SLOT CANNOT BE RENDERED ONTO A MACHINE THAT HAS NO SUCH FILE YET: it takes
  /// its value from what stands there, and on a first write nothing does. The framework refuses,
  /// naming the line, so a template of this shape belongs only where the file is known to stand.
  const String carrying =
      'fqdn: <fqdn>\n'
      'plane: <build-plane>\n'
      'to: <alert-recipients>\n'
      'note: <note?>\n'
      'release: <release!>\n';

  HostMachine machineWith({String? existing, String text = template}) {
    final HostMachine machine = HostMachine();
    machine.files.contents[templatePath] = text;
    if (existing case final String held) {
      machine.files.contents[path] = held;
    }
    return machine;
  }

  const WriteFileFromTemplate step = WriteFileFromTemplate(
    templatePath: templatePath,
    path: path,
    fileMode: 0x1a4,
    values: <String, KeyBinding>{
      'fqdn': KeyBinding(answer: 'fqdn'),
      'build-plane': KeyBinding(answer: 'build_plane'),
      'alert-recipients': KeyBinding(answer: 'alert_recipients', join: ', '),
      'note': KeyBinding(answer: 'note'),
    },
  );

  StepContext runWith(HostMachine machine, Map<String, Object> answers) =>
      machine.contextFor(const StepName('under_test'), Arguments.none, Arguments(answers));

  const Map<String, Object> answered = <String, Object>{
    'fqdn': 'm1.example.com',
    'build_plane': 'b1.example.com',
    'alert_recipients': <String>['a@example.com'],
    'note': 'something',
  };

  group('what tells it apart from the create-only writer', () {
    test('a file that stands and says something else is REWRITTEN', () async {
      // The whole difference. The create-only writer answers Satisfied here and leaves it.
      final HostMachine machine = machineWith(existing: 'fqdn: an-old-name\n');
      final StepContext context = runWith(machine, answered);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents[path], contains('fqdn: m1.example.com'));
      expect(machine.files.contents[path], isNot(contains('an-old-name')));
    });

    test('a second run has nothing to do', () async {
      final HostMachine machine = machineWith();
      await step.apply(runWith(machine, answered));

      expect(await step.check(runWith(machine, answered)), isA<Satisfied>());
    });
  });

  group('what a rewrite must not take away', () {
    test('a CARRIED slot keeps what the file already said', () async {
      // The value nothing in this run holds: something a later act put there. Without the carried
      // slot a rewrite from answers alone would take it back out, and nothing would report it.
      final HostMachine machine = machineWith(
        text: carrying,
        existing:
            'fqdn: m1.example.com\n'
            'plane: b1.example.com\n'
            'to: a@example.com\n'
            'note: something\n'
            'release: v1.2.3\n',
      );

      await step.apply(runWith(machine, answered));

      expect(machine.files.contents[path], contains('release: v1.2.3'));
    });

    test('THE INNOCENT NEIGHBOUR: everything else IS rewritten', () async {
      // Without this, a step that carried the whole file forward would pass the assertion above
      // while never writing anything at all.
      final HostMachine machine = machineWith(
        text: carrying,
        existing:
            'fqdn: an-old-name\n'
            'plane: an-old-plane\n'
            'to: old@example.com\n'
            'note: old\n'
            'release: v1.2.3\n',
      );

      await step.apply(runWith(machine, answered));

      final String written = machine.files.contents[path]!;
      expect(written, contains('plane: b1.example.com'));
      expect(written, isNot(contains('an-old-plane')));
      expect(written, contains('release: v1.2.3'));
    });
  });

  group('an answer nobody gave', () {
    test('drops the line of an OPTIONAL slot rather than writing it empty', () async {
      final HostMachine machine = machineWith();
      final Map<String, Object> withoutNote = Map<String, Object>.of(answered)..remove('note');

      await step.apply(runWith(machine, withoutNote));

      expect(machine.files.contents[path], isNot(contains('note:')));
      expect(machine.files.contents[path], contains('fqdn: m1.example.com'));
    });
  });

  group('taking it back', () {
    test('a file that was not there is GONE again', () async {
      final HostMachine machine = machineWith();
      final StepContext context = runWith(machine, answered);

      final String? captured = await step.capture(context);
      expect(captured, isNull);
      await step.apply(context);
      await step.undo(context, captured);

      expect(machine.files.contents[path], isNull);
    });

    test('THE INNOCENT NEIGHBOUR: a file that stood is put back, never deleted', () async {
      const String before = 'fqdn: somebody-elses\nrelease: v1.2.3\n';
      final HostMachine machine = machineWith(text: carrying, existing: before);
      final StepContext context = runWith(machine, answered);

      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);

      expect(machine.files.contents[path], before);
    });
  });

  group('what a carried slot cannot do', () {
    test('it is REFUSED on the first write, naming the line', () async {
      // Stated as a case rather than left to be met on a machine. A carried slot takes its value
      // from the file as it stands, so there is nothing to take on a machine that has no such file
      // — and a template of this shape belongs only where the file is known to stand.
      final HostMachine machine = machineWith(text: carrying);

      expect(await step.check(runWith(machine, answered)), isA<Blocked>());
    });
  });
}
