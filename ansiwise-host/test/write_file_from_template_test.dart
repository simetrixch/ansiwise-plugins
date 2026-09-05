import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_host/src/steps/host/quoted_slot.dart';
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

  /// With one. A CARRIED SLOT TAKES ITS VALUE FROM WHAT STANDS IN THE FILE ALREADY, and on a machine
  /// that has no such file yet nothing stands there — so the mark says both halves and the line is
  /// left out of the first write rather than written empty or refused.
  const String carrying =
      'fqdn: <fqdn>\n'
      'plane: <build-plane>\n'
      'to: <alert-recipients>\n'
      'note: <note?>\n'
      'release: <release!?>\n';

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

  group('a value that would end the quoting its slot stands inside', () {
    /// The slot inside a quoted flow list, which is where a value ends the scalar AND the list.
    const String quoted =
        'fqdn: <fqdn>\n'
        'plane: <build-plane>\n'
        "to: ['<alert-recipients>']\n"
        'note: <note?>\n';

    Map<String, Object> answeredWith(String recipient) =>
        Map<String, Object>.of(answered)..['alert_recipients'] = <String>[recipient];

    test('is BLOCKED at the row that would write it, and no file is written', () async {
      // Without this the file is written and reads back as nothing at all — a mailbox may carry an
      // apostrophe, so the value is one nobody would call wrong, and the failure surfaces in
      // whatever reads the file next rather than here.
      final HostMachine machine = machineWith(text: quoted);
      final StepContext context = runWith(machine, answeredWith("o'brien@example.com"));

      expect(await step.check(context), isA<Blocked>());
      await expectLater(() => step.apply(context), throwsA(isA<TemplateRefused>()));
      expect(machine.files.contents[path], isNull);
    });

    test('says nothing would be done, so a dry run names it too', () async {
      final HostMachine machine = machineWith(text: quoted);

      expect(
        await step.plan(runWith(machine, answeredWith("o'brien@example.com"))),
        isA<NothingPlan>(),
      );
    });

    test('is WRITTEN, escaped, where the row says how this file escapes', () async {
      // The row is the only one that can say it: the template already shows WHICH quoting the slot
      // stands inside, and what it cannot show is how the file writes that character inside itself,
      // because that is the grammar of the file. `doubled` is YAML single quoting and SQL.
      const WriteFileFromTemplate escaping = WriteFileFromTemplate(
        templatePath: templatePath,
        path: path,
        fileMode: 0x1a4,
        escaping: Escaping.doubled,
        values: <String, KeyBinding>{
          'fqdn': KeyBinding(answer: 'fqdn'),
          'build-plane': KeyBinding(answer: 'build_plane'),
          'alert-recipients': KeyBinding(answer: 'alert_recipients', join: ', '),
          'note': KeyBinding(answer: 'note'),
        },
      );
      final HostMachine machine = machineWith(text: quoted);
      final StepContext context = runWith(machine, answeredWith("o'brien@example.com"));

      expect(await escaping.check(context), isA<Ready>());
      await escaping.apply(context);

      expect(
        machine.files.contents[path],
        contains("to: ['o''brien@example.com']"),
        reason:
            'the apostrophe is written twice, which YAML single quoting reads back as one — the '
            'file carries the address nobody would call wrong, and it can be read',
      );
    });

    test('THE INNOCENT NEIGHBOUR: an address without one is written into the same slot', () async {
      // Without this a step that blocked on every quoted slot would pass the assertions above and
      // stop every installation whose template quotes anything.
      final HostMachine machine = machineWith(text: quoted);
      final StepContext context = runWith(machine, answeredWith('a@example.com'));

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents[path], contains("to: ['a@example.com']"));
    });

    test('THE INNOCENT NEIGHBOUR: the same value in an unquoted slot is written', () async {
      // The template beside this one writes `to: <alert-recipients>`, where an apostrophe closes
      // nothing. A step that refused the value rather than the place it lands would stop this.
      final HostMachine machine = machineWith();
      final StepContext context = runWith(machine, answeredWith("o'brien@example.com"));

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents[path], contains("to: o'brien@example.com"));
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

  group('the first write, where there is nothing to carry', () {
    test('the carried line is LEFT OUT, and the rest of the file is written', () async {
      // The state every installation passes through. A carried slot takes its value from the file
      // as it stands, and on a machine that has no such file there is nothing to take — so the mark
      // that asks for the value also says what to do about this, and the step is not blocked.
      final HostMachine machine = machineWith(text: carrying);

      expect(await step.check(runWith(machine, answered)), isA<Ready>());
      await step.apply(runWith(machine, answered));

      final String written = machine.files.contents[path]!;
      expect(written, isNot(contains('release')));
      expect(written, contains('fqdn: m1.example.com'));
    });

    test('THE INNOCENT NEIGHBOUR: the second run carries what the first one did not have', () async {
      // Without this, a version that dropped the carried line ALWAYS would pass the assertion above
      // and never write the value back on any run.
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

      expect(machine.files.contents[path], contains('release: v1.2.3'));
    });
  });

  group('the value a FILE records, for a file inherited from another installation', () {
    /// Where the other installation's values are recorded on this machine.
    const String recordsPath = '/srv/records.yaml';

    const WriteFileFromTemplate inheriting = WriteFileFromTemplate(
      templatePath: templatePath,
      path: path,
      fileMode: 0x1a4,
      values: <String, KeyBinding>{
        'fqdn': KeyBinding(answer: 'fqdn'),
        'build-plane': KeyBinding(file: recordsPath, key: 'plane'),
        'alert-recipients': KeyBinding(file: recordsPath, key: 'to', split: ', ', join: "', '"),
        'note': KeyBinding(file: recordsPath, key: 'note'),
      },
    );

    HostMachine recording(String records) {
      final HostMachine machine = machineWith();
      machine.files.contents[recordsPath] = records;
      return machine;
    }

    test('a recorded value fills its slot exactly as an answered one would', () async {
      final HostMachine machine = recording('plane: b1.example.com\nto: a@example.com\n');

      await inheriting.apply(runWith(machine, answered));

      expect(machine.files.contents[path], contains('plane: b1.example.com'));
    });

    test('a recorded line of several values is split as the file recorded them and joined as this '
        'one writes them', () async {
      final HostMachine machine = recording(
        'plane: b1.example.com\nto: a@example.com, b@example.com\n',
      );

      await inheriting.apply(runWith(machine, answered));

      expect(machine.files.contents[path], contains("to: a@example.com', 'b@example.com"));
    });

    test(
      'a key the file does not record drops the OPTIONAL line, as an unanswered one does',
      () async {
        final HostMachine machine = recording('plane: b1.example.com\nto: a@example.com\n');

        await inheriting.apply(runWith(machine, answered));

        expect(machine.files.contents[path], isNot(contains('note:')));
      },
    );

    test('a file named per installation is read with its slot filled from this run', () async {
      // THE POINT OF THE SLOT. A binding pointed at the file of one installation reads nothing on
      // the next, and reading nothing here is silent: the key is not written, and every later
      // reader takes that for "this installation has no such value".
      const WriteFileFromTemplate perInstallation = WriteFileFromTemplate(
        templatePath: templatePath,
        path: path,
        fileMode: 0x1a4,
        values: <String, KeyBinding>{
          'fqdn': KeyBinding(answer: 'fqdn'),
          'build-plane': KeyBinding(
            file: '/srv/records.<fqdn>.yaml',
            key: 'plane',
            runAnswer: 'fqdn',
          ),
          'alert-recipients': KeyBinding(answer: 'alert_recipients', join: ', '),
          'note': KeyBinding(answer: 'note'),
        },
      );
      final HostMachine machine = machineWith();
      machine.files.contents['/srv/records.m1.example.com.yaml'] = 'plane: b1.example.com\n';

      await perInstallation.apply(runWith(machine, answered));

      expect(machine.files.contents[path], contains('plane: b1.example.com'));
    });

    test('THE INNOCENT NEIGHBOUR: a path with no slot is read exactly as written', () async {
      final HostMachine machine = recording('plane: b1.example.com\nto: a@example.com\n');

      await inheriting.apply(runWith(machine, answered));

      expect(machine.files.contents[path], contains('plane: b1.example.com'));
    });

    test('a binding naming an answer and a run_answer is refused where the row is read', () {
      expect(
        () => KeyBinding.readFrom(<String, Object?>{
          'fqdn': <String, Object?>{'answer': 'fqdn', 'run_answer': 'fqdn'},
        }),
        throwsArgumentError,
        reason: 'there is no path on an answer source for a slot to stand in',
      );
    });

    test('a binding naming an answer AND a file is refused where the row is read', () {
      expect(
        () => KeyBinding.readFrom(<String, Object?>{
          'fqdn': <String, Object?>{'answer': 'fqdn', 'file': recordsPath, 'key': 'fqdn'},
        }),
        throwsArgumentError,
      );
    });

    test('a binding reading a file without a key is refused as that', () {
      expect(
        () => KeyBinding.readFrom(<String, Object?>{
          'fqdn': <String, Object?>{'file': recordsPath},
        }),
        throwsArgumentError,
      );
    });

    test('a binding splitting without saying how to join is refused as that', () {
      expect(
        () => KeyBinding.readFrom(<String, Object?>{
          'to': <String, Object?>{'file': recordsPath, 'key': 'to', 'split': ', '},
        }),
        throwsArgumentError,
      );
    });
  });
}
