import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Filling a file of `KEY=value` lines from the template beside it.
///
/// **This step is driven here rather than by the idempotence audit, and the ledger says why.** The
/// prober hands every text argument with no default the same one-character value, so the template it
/// would read and the file it would write are the same path — and filling a file from itself is not
/// the act this step performs. No fixture can change what the prober hands over, so the two paths
/// are told apart here instead.
///
/// What is asserted is what tells this step apart from every other writer in this package. Those are
/// finished when a file holds what they render. This one is finished when every key the template
/// declares carries an answer, and it fills IN PLACE so that every key keeps the paragraph
/// explaining it.
///
/// **Which of two values wins, and why that was turned around.** This step used to leave any key
/// alone that held a value at all, so that a value somebody typed could not be taken back by an
/// answer. That protected a way of working which has since been abolished: a credential reaches an
/// installation through the answers a run is given and through nothing else, never through a file
/// somebody edits on the machine. Under the old rule an operator who rotated a token, put the new
/// one in the answers and ran the programs again got every step green and an installation still
/// using the old one — measured on a machine carrying five GitHub tokens that all answered 401.
///
/// So the answer wins now, and only ever over a key it HAS an answer for: a value under a key no
/// answer names is still untouched, because this run was told nothing about it. Where a value is
/// replaced rather than supplied, the row says which key — never which value, since these files hold
/// credentials.
void main() {
  const String templatePath = '/srv/checkout/configs/config.example';
  const String path = '/srv/checkout/configs/config.dev';

  /// The template as such a file really looks: every value empty, each key under its explanation.
  const String template =
      '# What this installation answers on.\n'
      'DOMAIN_SUFFIX=""\n'
      '\n'
      '# Which stage it runs.\n'
      'DEPLOY_ENV=""\n'
      '\n'
      '# The mailboxes an alert with no recipients of its own is delivered to.\n'
      'ALERT_RECIPIENTS=""\n';

  const Arguments answers = Arguments(<String, Object>{
    'fqdn': 'm1.example.com',
    'stage': 'dev',
    'alert_recipients': <String>['a@example.com', 'b@example.com'],
  });

  FillKeyValueFile stepWith({
    bool holdsCredentials = false,
    Map<String, KeyBinding>? values,
    String subject = 'configuration',
  }) => FillKeyValueFile(
    templatePath: templatePath,
    path: path,
    fileMode: 0x1a4,
    subject: subject,
    holdsCredentials: holdsCredentials,
    values:
        values ??
        const <String, KeyBinding>{
          'DOMAIN_SUFFIX': KeyBinding(answer: 'fqdn'),
          'DEPLOY_ENV': KeyBinding(answer: 'stage'),
          'ALERT_RECIPIENTS': KeyBinding(answer: 'alert_recipients', join: ','),
        },
  );

  /// A machine carrying the template, and the file only where one is given.
  HostMachine machineWith({String? existing}) {
    final HostMachine machine = HostMachine();
    machine.files.contents[templatePath] = template;
    if (existing case final String held) {
      machine.files.contents[path] = held;
    }
    return machine;
  }

  StepContext contextOn(HostMachine machine) =>
      machine.contextFor(const StepName('under_test'), Arguments.none, answers);

  group('a file nobody has filled yet', () {
    test('every key gets its answer, in place, under the paragraph explaining it', () async {
      final HostMachine machine = machineWith();
      final StepContext context = contextOn(machine);

      expect(await stepWith().check(context), isA<Ready>());
      await stepWith().apply(context);

      final String written = machine.files.contents[path]!;
      expect(written, contains('DOMAIN_SUFFIX="m1.example.com"'));
      expect(written, contains('DEPLOY_ENV="dev"'));
      expect(
        written,
        contains('# What this installation answers on.\nDOMAIN_SUFFIX='),
        reason: 'each key keeps the explanation it stands under, which is the file\'s whole value',
      );
      expect(
        RegExp('^DOMAIN_SUFFIX=', multiLine: true).allMatches(written).length,
        1,
        reason: 'filled in place and never appended, or the file carries the key twice',
      );
    });

    test('a list is written on one line, with what the row says stands between', () async {
      final HostMachine machine = machineWith();
      await stepWith().apply(contextOn(machine));

      expect(
        machine.files.contents[path],
        contains('ALERT_RECIPIENTS="a@example.com,b@example.com"'),
      );
    });

    test('a second run has nothing to do', () async {
      // The property the audit could not measure here, measured directly: the same step, twice, over
      // two paths that differ.
      final HostMachine machine = machineWith();
      await stepWith().apply(contextOn(machine));
      final String afterFirst = machine.files.contents[path]!;

      expect(await stepWith().check(contextOn(machine)), isA<Satisfied>());
      await stepWith().apply(contextOn(machine));

      expect(machine.files.contents[path], afterFirst);
    });
  });

  group('which of two values wins', () {
    test('a value that disagrees with the answer is replaced by it', () async {
      // THE DEFECT THIS CLOSES. The file held one value and the run was told another, and the row
      // used to call that finished — so a rotated credential never reached the installation and
      // every step reported green. Measured on a machine carrying five tokens that answered 401.
      final HostMachine machine = machineWith(
        existing: template.replaceFirst('DEPLOY_ENV=""', 'DEPLOY_ENV="staging-by-hand"'),
      );
      await stepWith().apply(contextOn(machine));

      final String written = machine.files.contents[path]!;
      expect(written, contains('DEPLOY_ENV="dev"'));
      expect(
        written,
        isNot(contains('staging-by-hand')),
        reason: 'the old value is gone, not left standing beside the new one',
      );
    });

    test('the row says WHICH key it took back, and never what stood there', () async {
      // A row holding credentials must reach no record, so the key is named and the value is not —
      // and something has to be said, or a replacement is a silent one.
      final HostMachine machine = machineWith(
        existing: template.replaceFirst('DEPLOY_ENV=""', 'DEPLOY_ENV="staging-by-hand"'),
      );
      await stepWith(holdsCredentials: true).apply(contextOn(machine));

      final String said = machine.said.join('\n');
      expect(said, contains('DEPLOY_ENV'));
      expect(said, isNot(contains('staging-by-hand')));
    });

    test('THE INNOCENT NEIGHBOUR: a key no answer names is left exactly as it was typed', () async {
      // The half of the old rule that stands. This run was told nothing about such a key, so it has
      // nothing to say about it — and a writer that rendered the whole file would take it back.
      final HostMachine machine = machineWith(
        existing: '$template\n# Something only this installation knows.\nHAND_WRITTEN="kept"\n',
      );
      await stepWith().apply(contextOn(machine));

      expect(machine.files.contents[path], contains('HAND_WRITTEN="kept"'));
    });

    test('a value still equal to the template counts as unanswered', () async {
      // A file somebody copied and never filled must not read as an answered one.
      final HostMachine machine = machineWith(existing: template);
      expect(await stepWith().check(contextOn(machine)), isA<Ready>());

      await stepWith().apply(contextOn(machine));
      expect(machine.files.contents[path], contains('DEPLOY_ENV="dev"'));
    });
  });

  group('an answer holding nothing', () {
    test('is left as the template had it, rather than written empty', () async {
      // Writing an empty value would leave the key unanswered by the file's OWN rule — these files
      // count empty as unanswered — so the check would say there is still work and the row would
      // report work for ever. An optional answer nobody gave is a value this installation does not
      // have, and a key it does not have belongs in the file as the template left it.
      final HostMachine machine = machineWith();
      final StepContext context = machine.contextFor(
        const StepName('under_test'),
        Arguments.none,
        const Arguments(<String, Object>{'fqdn': 'm1.example.com', 'stage': ''}),
      );
      final FillKeyValueFile step = stepWith(
        values: const <String, KeyBinding>{
          'DOMAIN_SUFFIX': KeyBinding(answer: 'fqdn'),
          'DEPLOY_ENV': KeyBinding(answer: 'stage'),
        },
      );

      await step.apply(context);

      expect(machine.files.contents[path], contains('DOMAIN_SUFFIX="m1.example.com"'));
      expect(machine.files.contents[path], contains('DEPLOY_ENV=""'));
      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'the row is finished; without this it would report work on every run for ever',
      );
    });

    test('THE INNOCENT NEIGHBOUR: an answer that holds something is still written', () async {
      // Without this, a step that skipped every value would pass the assertion above and write a
      // file of nothing at all.
      final HostMachine machine = machineWith();
      await stepWith().apply(contextOn(machine));

      expect(machine.files.contents[path], contains('DEPLOY_ENV="dev"'));
    });
  });

  group('what it refuses rather than writes', () {
    test('a key the template does not declare, by name', () async {
      final CheckResult answer = await stepWith(
        values: const <String, KeyBinding>{'NOT_DECLARED': KeyBinding(answer: 'stage')},
      ).check(contextOn(machineWith()));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('NOT_DECLARED'));
    });

    test('a value carrying a quote or a line break, by name', () async {
      final HostMachine machine = machineWith();
      final StepContext context = machine.contextFor(
        const StepName('under_test'),
        Arguments.none,
        const Arguments(<String, Object>{'fqdn': 'has "a quote"', 'stage': 'dev'}),
      );
      final CheckResult answer = await stepWith(
        values: const <String, KeyBinding>{'DOMAIN_SUFFIX': KeyBinding(answer: 'fqdn')},
      ).check(context);

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('DOMAIN_SUFFIX'));
    });

    test('the refusal names what the ROW says this file is', () async {
      // The one reason the two files were two classes: a credential and a setting are not the same
      // thing to whoever reads the refusal. The word is a row value now, so it still is not.
      final HostMachine machine = HostMachine();
      final CheckResult answer = await stepWith(
        subject: 'credential',
      ).check(machine.contextFor(const StepName('under_test'), Arguments.none, answers));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('credential'));
    });
  });

  test('a file missing a line its template declares is refused, not silently left short', () async {
    // Found by a test of this suite that was wrong about something else. Filling happens IN PLACE,
    // so a key whose line is gone from the file has nothing to rewrite: the write would leave it
    // out, the check afterwards would say there is still work, and the row would report doing
    // something it did not do.
    final HostMachine machine = machineWith(existing: 'DEPLOY_ENV="mine"\n');
    final CheckResult answer = await stepWith().check(contextOn(machine));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('DOMAIN_SUFFIX'));
    expect(answer.reason, contains('ALERT_RECIPIENTS'));
  });

  group('a template that is not there yet', () {
    test('is refused rather than treated as an empty one', () async {
      final CheckResult answer = await stepWith().check(contextOn(HostMachine()));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(templatePath));
    });

    test('PLANS instead of throwing, because a dry run must still say what would happen', () async {
      // It threw here once. A step whose plan throws leaves a dry run with nothing to say about
      // that row — which is the one outcome the mode exists to prevent, and it is the state a dry
      // run is pointed at: a machine where the earlier row has not cloned anything yet.
      final StepPlan plan = await stepWith().plan(contextOn(HostMachine()));

      expect(plan.summary, contains(path));
      expect(plan.summary, contains('earlier row'));
    });

    test('says it rests on an earlier step, which is what makes that deferral legitimate', () {
      expect(stepWith().restsOnAnEarlierStep, isTrue);
    });
  });

  group('what a plan may carry into the record', () {
    test('a row holding credentials plans the KEYS and never the values', () async {
      final StepPlan plan = await stepWith(holdsCredentials: true).plan(contextOn(machineWith()));

      expect(plan.summary, contains('DEPLOY_ENV'));
      expect(
        plan.summary,
        isNot(contains('m1.example.com')),
        reason: 'a plan is read out of the run record, and a record is not where a credential goes',
      );
    });

    test('THE INNOCENT NEIGHBOUR: any other row plans the whole file', () async {
      // Without this, a step that hid every plan would pass the assertion above and leave an
      // operator unable to see the file they are about to get.
      final StepPlan plan = await stepWith().plan(contextOn(machineWith()));

      expect(plan.summary, contains(path));
      expect(plan, isA<DiffPlan>());
    });
  });

  group('taking it back', () {
    test('the file as it stood is put back', () async {
      final String before = template.replaceFirst('DEPLOY_ENV=""', 'DEPLOY_ENV="mine"');
      final HostMachine machine = machineWith(existing: before);
      final StepContext context = contextOn(machine);

      final String? captured = await stepWith().capture(context);
      await stepWith().apply(context);
      expect(machine.files.contents[path], isNot(before));

      await stepWith().undo(context, captured);
      expect(machine.files.contents[path], before);
    });

    test('a file that was not there is GONE again, not left standing', () async {
      // The record says "taken back" the moment undo returns without throwing. An undo that
      // returned here left this installation's own answers — its domain, its addresses — on a
      // machine the record describes as untouched, which is the one thing a record may not do.
      final HostMachine machine = machineWith();
      final StepContext context = contextOn(machine);

      final String? captured = await stepWith().capture(context);
      expect(captured, isNull);

      await stepWith().apply(context);
      expect(machine.files.contents[path], isNotNull, reason: 'apply created it');

      await stepWith().undo(context, captured);

      expect(machine.files.contents[path], isNull);
    });

    test('THE INNOCENT NEIGHBOUR: a file that already stood is restored, never deleted', () async {
      // Without this, an undo that simply deleted whatever it found would pass the two tests above
      // while taking away a file this step only edited.
      const String before = 'DEPLOY_ENV="someone else wrote this"\n';
      final HostMachine machine = machineWith(existing: before);
      final StepContext context = contextOn(machine);

      final String? captured = await stepWith().capture(context);
      await stepWith().apply(context);
      await stepWith().undo(context, captured);

      expect(machine.files.contents[path], before);
    });
  });

  group('a template that gained a key after this file was made', () {
    // Keys are added as the product is built. An installation made before one was added has a file
    // without it, filling happens in place, and so there is nothing to rewrite: whatever needed the
    // key reads nothing and every step on the way reports success. On a FIRST installation it never
    // shows, because the file is copied from the template — which is what makes it the fault that
    // waits until there is something to lose.
    const String gainedParagraph = '# The name the monitoring administrator logs in under.\n';
    const String grownTemplate = '$template\n${gainedParagraph}OBSERVABILITY_ADMIN_USER="admin"\n';

    /// The file as an installation made before that key holds it, with answers typed into it.
    const String older =
        '# What this installation answers on.\n'
        'DOMAIN_SUFFIX="m1.example.com"\n'
        '\n'
        '# Which stage it runs.\n'
        'DEPLOY_ENV="dev"\n'
        '\n'
        '# The mailboxes an alert with no recipients of its own is delivered to.\n'
        'ALERT_RECIPIENTS="a@example.com,b@example.com"\n';

    HostMachine grown({String? file}) {
      final HostMachine machine = HostMachine();
      machine.files.contents[templatePath] = grownTemplate;
      machine.files.contents[path] = file ?? older;
      return machine;
    }

    test('the file is not finished, because a key it needs is not in it', () async {
      expect(await stepWith().check(contextOn(grown())), isA<Ready>());
    });

    test('the key is added, UNDER ITS OWN PARAGRAPH', () async {
      final HostMachine machine = grown();
      await stepWith().apply(contextOn(machine));

      final String written = machine.files.contents[path]!;
      expect(
        written,
        contains('${gainedParagraph}OBSERVABILITY_ADMIN_USER'),
        reason: 'the paragraph is the only documentation an operator opening this file ever gets',
      );
    });

    test('AND NOTHING SOMEBODY TYPED IS TAKEN BACK, which is the whole shape', () async {
      final HostMachine machine = grown();
      await stepWith().apply(contextOn(machine));

      final String written = machine.files.contents[path]!;
      expect(written, contains('DOMAIN_SUFFIX="m1.example.com"'));
      expect(written, contains('ALERT_RECIPIENTS="a@example.com,b@example.com"'));
    });

    test('and it is finished afterwards, so the row does not report work for ever', () async {
      final HostMachine machine = grown();
      await stepWith().apply(contextOn(machine));
      expect(await stepWith().check(contextOn(machine)), isA<Satisfied>());
    });

    test('COUNTER-PROBE: a file that already carries every key gains nothing', () async {
      // Without this the growing could run on every pass, and a file that gained the same key twice
      // is a file whose second, blank copy is the one a shell ends up reading.
      final HostMachine machine = grown(
        file: '$older\n${gainedParagraph}OBSERVABILITY_ADMIN_USER="admin"\n',
      );

      await stepWith().apply(contextOn(machine));

      expect(
        'OBSERVABILITY_ADMIN_USER'.allMatches(machine.files.contents[path]!).length,
        1,
        reason: 'appending on every run is how a file ends up carrying the same key twice',
      );
    });
  });
}
