import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A file put on the machine once, and never taken back off whoever edited it afterwards.
///
/// Everything asserted here is what tells this step apart from the writers beside it. Those are
/// finished when the file holds what they render; this one is finished when the file is there. A
/// step of this shape that compared content would read an operator's own lines as a difference to
/// correct, and correcting it removes them — which is the whole reason the step exists.
///
/// **The template is written by the test rather than read off this package.** The other template
/// steps here ship a file with the plugin and their tests read that file so a copy cannot drift.
/// This step ships none: the text is whoever calls it, so there is nothing to drift from and the
/// text belongs in the case that drives it.
void main() {
  const String templatePath = 'ansiwise/templates/created-file.tpl';
  const String rendered =
      '# The first line, put here by the deployment.\n'
      'ROWS=(\n'
      '"default"\n'
      ')\n';

  /// A machine carrying the template, and nothing else this step is about.
  HostMachine machineWith({String? existing, String path = '/etc/example.conf'}) {
    final HostMachine machine = HostMachine();
    machine.files.contents[templatePath] = rendered;
    if (existing case final String held) {
      machine.files.contents[path] = held;
    }
    return machine;
  }

  const CreateFileFromTemplate step = CreateFileFromTemplate(
    templatePath: templatePath,
    path: '/etc/example.conf',
    fileMode: 0x1a4,
  );

  group('a file that is not there yet', () {
    test('is created, holding exactly what the template says', () async {
      final HostMachine machine = machineWith();
      final StepContext context = machine.contextFor(const StepName('under_test'));

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents['/etc/example.conf'], rendered);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the plan shows the whole file, not a mention of a template', () async {
      final HostMachine machine = machineWith();
      final StepPlan plan = await step.plan(machine.contextFor(const StepName('under_test')));

      expect(plan, isA<DiffPlan>());
      expect((plan as DiffPlan).after, rendered);
      expect(plan.before, isEmpty);
    });
  });

  group('a file somebody has already changed', () {
    const String edited =
        '# The first line, put here by the deployment.\n'
        'ROWS=(\n'
        '"default"\n'
        '"the one somebody added"\n'
        ')\n';

    test('is not rewritten, and nothing is even written', () async {
      final HostMachine machine = machineWith(existing: edited);
      final StepContext context = machine.contextFor(const StepName('under_test'));

      expect(await step.check(context), isA<Satisfied>());
      await step.apply(context);

      expect(machine.files.contents['/etc/example.conf'], edited);
      expect(
        machine.files.written,
        isEmpty,
        reason: 'a satisfied step that writes anyway is not satisfied',
      );
    });

    test('the plan says nothing would be done to it', () async {
      final HostMachine machine = machineWith(existing: edited);
      final StepPlan plan = await step.plan(machine.contextFor(const StepName('under_test')));

      expect(plan, isA<NothingPlan>());
    });
  });

  group('taking the run back', () {
    test('removes only the file this run left', () async {
      final HostMachine machine = machineWith();
      final StepContext context = machine.contextFor(const StepName('under_test'));

      final bool wasThere = await step.capture(context);
      await step.apply(context);
      await step.undo(context, wasThere);

      expect(machine.files.contents.containsKey('/etc/example.conf'), isFalse);
    });

    test('leaves a file that was already there, whatever it now holds', () async {
      // An undo runs while cleaning up after a failure, which is the worst moment to delete lines
      // somebody typed. The check keeps that rule on the way in and this keeps it on the way out.
      const String theirs = 'ROWS=(\n"only theirs"\n)\n';
      final HostMachine machine = machineWith(existing: theirs);
      final StepContext context = machine.contextFor(const StepName('under_test'));

      await step.undo(context, await step.capture(context));

      expect(machine.files.contents['/etc/example.conf'], theirs);
      expect(machine.files.deleted, isEmpty);
    });
  });

  group('one such file per run', () {
    const CreateFileFromTemplate perRun = CreateFileFromTemplate(
      templatePath: templatePath,
      path: '/etc/example.<stage>.conf',
      fileMode: 0x1a4,
      runAnswer: 'stage',
    );

    /// A machine carrying the template, run with [answers].
    StepContext runWith(HostMachine machine, Map<String, Object> answers) =>
        machine.contextFor(const StepName('under_test'), Arguments.none, Arguments(answers));

    test('the path is named for what this run answered, not for a remembered value', () async {
      final HostMachine machine = machineWith();
      final StepContext context = runWith(machine, <String, Object>{'stage': 'prod'});

      await perRun.apply(context);

      expect(machine.files.contents.containsKey('/etc/example.prod.conf'), isTrue);
      expect(machine.files.contents.containsKey('/etc/example.<stage>.conf'), isFalse);
    });

    test('a run holding no such answer is refused, and the plan says the same', () async {
      // The counter-probe for the filling: without this, a run that answered nothing would write a
      // file called `example.<stage>.conf` and every reader of it would look somewhere else.
      final HostMachine machine = machineWith();
      final StepContext context = runWith(machine, <String, Object>{});

      final CheckResult answer = await perRun.check(context);
      expect((answer as Blocked).reason, contains('<stage>'));
      expect(await perRun.plan(context), isA<NothingPlan>());
      expect(machine.files.written, isEmpty);
    });

    test('a row that names no answer leaves the path exactly as written', () async {
      final HostMachine machine = machineWith();
      expect(await step.check(machine.contextFor(const StepName('under_test'))), isA<Ready>());
    });
  });

  group('the template the file is made from', () {
    test('a machine whose template did not travel with it is BLOCKED, never satisfied', () async {
      // The two look alike from the outside and are opposites: satisfied says this machine needs no
      // such file, and a machine whose template is missing needs it as much as any other.
      final HostMachine machine = HostMachine();
      final StepContext context = machine.contextFor(const StepName('under_test'));

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains(templatePath));
      expect(machine.files.written, isEmpty);
    });

    test('and the plan says what is missing rather than failing to be produced', () async {
      final HostMachine machine = HostMachine();
      final StepPlan plan = await step.plan(machine.contextFor(const StepName('under_test')));

      expect(plan, isA<NothingPlan>());
      expect((plan as NothingPlan).because, contains(templatePath));
    });
  });

  group('a slot is filled from the answer the ROW binds to it', () {
    // The reason a binding exists at all: a slot is spelled with hyphens and an answer with
    // underscores, so looking an answer up by the slot's own name reaches only names of one word.
    // Every answer of more than one — build_plane, unit_apex, books_cluster — was unreachable, and
    // unreachable in SILENCE: the template named the slot, nothing filled it, and the literal
    // characters went into the file for whatever read it next to take as a value.
    const String withSlots =
        'plane: <build-plane>\n'
        'domain: <fqdn>\n';
    const String templateWithSlots = 'ansiwise/templates/slotted.tpl';

    HostMachine machineForSlots() {
      final HostMachine machine = HostMachine();
      machine.files.contents[templateWithSlots] = withSlots;
      return machine;
    }

    StepContext runWith(HostMachine machine, Map<String, Object> answers) =>
        machine.contextFor(const StepName('under_test'), Arguments.none, Arguments(answers));

    const CreateFileFromTemplate bound = CreateFileFromTemplate(
      templatePath: templateWithSlots,
      path: '/etc/slotted.conf',
      fileMode: 0x1a4,
      values: <String, KeyBinding>{
        'build-plane': KeyBinding(answer: 'build_plane'),
        'fqdn': KeyBinding(answer: 'fqdn'),
      },
    );

    test('THE INNOCENT CASE: an answer of two words reaches its slot', () async {
      final HostMachine machine = machineForSlots();
      final StepContext context = runWith(machine, <String, Object>{
        'build_plane': 'b1.example.com',
        'fqdn': 'm1.example.com',
      });

      await bound.apply(context);

      expect(
        machine.files.contents['/etc/slotted.conf'],
        'plane: b1.example.com\ndomain: m1.example.com\n',
      );
    });

    test('the literal slot NEVER reaches the file, whatever else happens', () async {
      final HostMachine machine = machineForSlots();
      final StepContext context = runWith(machine, <String, Object>{
        'build_plane': 'b1.example.com',
        'fqdn': 'm1.example.com',
      });

      await bound.apply(context);

      expect(machine.files.contents['/etc/slotted.conf'], isNot(contains('<')));
    });

    test('a slot no binding covers is REFUSED, not written out as text', () async {
      // Without the refusal the seven characters <build-plane> would be read by whatever opens the
      // file as the build plane's address.
      final HostMachine machine = machineForSlots();
      const CreateFileFromTemplate half = CreateFileFromTemplate(
        templatePath: templateWithSlots,
        path: '/etc/slotted.conf',
        fileMode: 0x1a4,
        values: <String, KeyBinding>{'fqdn': KeyBinding(answer: 'fqdn')},
      );

      expect(
        await half.check(runWith(machine, <String, Object>{'fqdn': 'm1.example.com'})),
        isA<Blocked>(),
      );
    });

    test('a binding for a slot the template does not name is REFUSED', () async {
      // The other direction, and it is the one that loses a value in silence: the row says an
      // answer fills something, and the file it lands in has no such place.
      final HostMachine machine = machineForSlots();
      const CreateFileFromTemplate extra = CreateFileFromTemplate(
        templatePath: templateWithSlots,
        path: '/etc/slotted.conf',
        fileMode: 0x1a4,
        values: <String, KeyBinding>{
          'build-plane': KeyBinding(answer: 'build_plane'),
          'fqdn': KeyBinding(answer: 'fqdn'),
          'nowhere': KeyBinding(answer: 'stage'),
        },
      );

      expect(
        await extra.check(
          runWith(machine, <String, Object>{
            'build_plane': 'b1.example.com',
            'fqdn': 'm1.example.com',
            'stage': 'dev',
          }),
        ),
        isA<Blocked>(),
      );
    });

    test('several values are joined by what the row says stands between them', () async {
      // Not by whatever shape a list happens to print as, which is what stood here before.
      const String listTemplate = 'ansiwise/templates/listed.tpl';
      final HostMachine machine = HostMachine();
      machine.files.contents[listTemplate] = 'to: <alert-recipients>\n';

      const CreateFileFromTemplate joined = CreateFileFromTemplate(
        templatePath: listTemplate,
        path: '/etc/listed.conf',
        fileMode: 0x1a4,
        values: <String, KeyBinding>{
          'alert-recipients': KeyBinding(answer: 'alert_recipients', join: ','),
        },
      );

      await joined.apply(
        runWith(machine, <String, Object>{
          'alert_recipients': <String>['a@example.com', 'b@example.com'],
        }),
      );

      expect(machine.files.contents['/etc/listed.conf'], 'to: a@example.com,b@example.com\n');
    });
  });
}
