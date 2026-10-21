import 'dart:async';
import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';
import 'package:test/test.dart';

const Map<String, String> values = <String, String>{
  'identity': 'fixture-identity',
  'api-token': 'fixture-api-secret',
  'other-token': 'fixture-other-secret',
};
const VaultLayout layout = VaultLayout(
  profile: 'profile.yaml',
  urlKey: 'global.vaultUrl',
  nameKey: 'global.clusterName',
  authPathKey: 'global.auth',
  credentials: 'credentials.txt',
);
const VaultKvEntryFromCommand exchange = VaultKvEntryFromCommand(
  repository: '/checkout',
  mount: 'secret',
  path: 'stage/app/service',
  fields: <String>['identity', 'api-token', 'other-token'],
  fieldsFromAnswers: <String>['other-token=service_token'],
  producer: '/run/producer.sh',
  layout: layout,
);

// A secret on a line nobody approved, which must reach no message, log or record.
const String unmarkedSecret = 'fixture-unmarked-secret';
// Public by design: a user, a repository, an HTTP status.
const String publicReason = 'user ghost-user has no write access to repository acme/site';
const String secondPublicReason = 'repository acme/site answered HTTP 403';
// Public text on a line the reader must not accept, so its presence shows the line was read.
const String rejectedReason = 'a reason on a line that is not the marker at column zero';
const String refusedMessage = 'the credential producer refused with exit 1: $publicReason';
final List<String> canaries = <String>[
  ...values.values,
  'fixture-root-secret',
  'replacement-secret',
  unmarkedSecret,
];
// Unmarked lines, an indented marker and one marked line, as a producer that also logs would write.
const String mixedStderr =
    'Traceback: $unmarkedSecret\n'
    'refused: $publicReason\n'
    '  refused: indented $unmarkedSecret\n'
    'note: fixture-other-secret\n';
const String withheldCheck = 'the credential producer check failed with exit 1';

// Each line is one the reader must not accept, and each carries text that would show it was read.
const Map<String, String> unapproved = <String, String>{
  'no marker': 'Traceback: $unmarkedSecret\n',
  'an empty reason': 'refused: \n',
  'a reason of spaces': 'refused:    \n',
  'a reason of one no-break space': 'refused: \u00a0\n',
  'a marker without a reason or a space': 'refused:\n',
  'an indented marker': ' refused: $rejectedReason $unmarkedSecret\n',
  'a marker after a tab': '\trefused: $rejectedReason $unmarkedSecret\n',
  'a marker inside a line': 'error: refused: $rejectedReason $unmarkedSecret\n',
  'a marker without its space': 'refused:$rejectedReason $unmarkedSecret\n',
  'a marker in capitals': 'REFUSED: $rejectedReason $unmarkedSecret\n',
  'a carriage return ending the line': 'refused: $rejectedReason $unmarkedSecret\r\n',
  'a null character': 'refused: $rejectedReason\u0000$unmarkedSecret\n',
  'a tab inside the reason': 'refused: $rejectedReason\t$unmarkedSecret\n',
  'an escape sequence': 'refused: $rejectedReason\u001b[2K$unmarkedSecret\n',
  'a delete character': 'refused: $rejectedReason\u007f$unmarkedSecret\n',
  'a next-line character': 'refused: $rejectedReason\u0085$unmarkedSecret\n',
  'a line separator': 'refused: $rejectedReason\u2028$unmarkedSecret\n',
  'a paragraph separator': 'refused: $rejectedReason\u2029$unmarkedSecret\n',
};

void main() {
  test('test/dry reads and plans without credential creation, writes or copies', () async {
    final Fixture f = Fixture();
    expect(await exchange.check(f.context), isA<Ready>());
    final StepPlan plan = await exchange.plan(f.context);
    expect(plan.summary, contains('secret/data/stage/app/service'));
    expect((plan as RequestPlan).body, contains('identity, api-token, other-token'));
    expect(f.producer.commands.every((Command c) => c.observes), isTrue);
    expect(f.store.writes, isEmpty);
    expect(f.files.written, isEmpty);
    f.assertPrivate();
  });

  test(
    'an entry whose latest version was deleted is written against the version Vault kept',
    () async {
      // PLANTED: Vault retains version 7 after a soft delete and refuses a write checked against 0.
      final Fixture f = Fixture()..store.deleted = 7;
      expect(await exchange.check(f.context), isA<Ready>());
      await exchange.apply(f.context);
      expect(f.store.writes.single['options'], <String, Object>{'cas': 7});
      expect(f.store.entry, values);
      expect(await exchange.check(f.context), isA<Satisfied>());
      f.assertPrivate();
    },
  );

  test(
    'one complete exchange is validated, CAS written once and verified without recording values',
    () async {
      final Fixture f = Fixture();
      await exchange.apply(f.context);
      expect(f.store.writes, hasLength(1));
      expect(f.store.entry, values);
      expect(f.store.writes.single['options'], <String, Object>{'cas': 0});
      final Command command = f.producer.commands.single;
      expect(command.observes, isFalse);
      expect(command.secretOutput, isTrue);
      expect(command.arguments, <String>['/run/producer.sh', '--apply', '--', 'kubectl']);
      expect(jsonDecode(command.stdin!), <String, Object?>{
        'entry': null,
        'inputs': <String, String>{'other-token': values['other-token']!},
      });
      expect(f.files.written, isEmpty);
      expect(await exchange.check(f.context), isA<Satisfied>());
      expect(f.store.writes, hasLength(1));
      f.assertPrivate();
    },
  );

  test(
    'a valid standing entry is reused and a changed answer reaches the producer in memory',
    () async {
      final Fixture f = Fixture(entry: values);
      expect(await exchange.check(f.context), isA<Satisfied>());
      expect(f.store.writes, isEmpty);
      final Fixture changed = Fixture(entry: values, answer: 'replacement-secret');
      expect(await exchange.check(changed.context), isA<Ready>());
      await exchange.apply(changed.context);
      expect(changed.store.entry?['api-token'], values['api-token']);
      expect(changed.store.entry?['other-token'], 'replacement-secret');
      changed.assertPrivate();
    },
  );

  test('unreadable Vault is blocked and never invokes the producer or writes', () async {
    for (final int status in <int>[403, 500]) {
      // The producer would refuse with a public reason, so a reason in the answer shows it ran.
      final Fixture f = failing(stderr: 'refused: $publicReason\n')..store.status = status;
      expect(await blockedReason(f), isNot(contains(publicReason)));
      await expectLater(exchange.apply(f.context), throwsA(isA<Exception>()));
      expect(f.producer.commands, isEmpty);
      expect(f.store.writes, isEmpty);
      f.assertPrivate();
    }
  });

  test(
    'partial, empty, extra and malformed producer output cannot write any sibling field',
    () async {
      for (final String output in <String>[
        '{"identity":"fixture-identity"}',
        '{}',
        jsonEncode(<String, String>{...values, 'extra': 'unexpected'}),
        jsonEncode(<String, String>{...values, 'api-token': ''}),
        'not JSON',
      ]) {
        final Fixture f = Fixture()..producer.output = output;
        await expectLater(exchange.apply(f.context), throwsA(isA<Exception>()));
        expect(f.store.writes, isEmpty);
        f.assertPrivate();
      }
    },
  );

  test('a refusing or timed out producer exposes no output and writes nothing', () async {
    final Fixture f = Fixture()..producer.failure = true;
    await expectLater(exchange.apply(f.context), throwsA(isA<CommandFailed>()));
    expect(f.store.writes, isEmpty);
    f.assertPrivate();
    final Fixture timeout = Fixture()..producer.timeout = true;
    await expectLater(exchange.apply(timeout.context), throwsA(isA<Exception>()));
    expect(timeout.store.writes, isEmpty);
  });

  test('a timed out producer says its deadline and nothing the timeout carried', () async {
    const String deadline = 'the credential producer exceeded its 120 second deadline';
    final Fixture f = Fixture()..producer.timeout = true;
    expect(await blockedReason(f), deadline);
    expect((await thrownBy(f)).toString(), deadline);
    expect(f.store.writes, isEmpty);
    f.assertPrivate();
  });

  test('a rejected CAS or mismatched verification cannot claim success', () async {
    final Fixture rejected = Fixture()..store.refuseWrite = true;
    await expectLater(exchange.apply(rejected.context), throwsA(isA<Exception>()));
    rejected.assertPrivate();
    final Fixture different = Fixture()..store.ignoreWrite = true;
    await expectLater(exchange.apply(different.context), throwsA(isA<Exception>()));
    different.assertPrivate();
  });

  test(
    'the records check rejects a planted producer-output leak beside an innocent line',
    () async {
      final Fixture f = Fixture()..producer.failure = true;
      f.context.log.info('credential exchange is ready');
      f.assertPrivate();
      final CommandResult answer = await f.context.shell.run(
        Command.detailed(
          'bash',
          stdin: jsonEncode(<String, Object?>{'entry': null, 'inputs': <String, String>{}}),
        ),
      );
      // A command given stdin keeps its output out of the record whatever it declares.
      f.assertPrivate();
      // PLANTED: a step that logged what the producer answered carries it into the record.
      f.context.log.info(answer.stdout);
      expect(f.assertPrivate, throwsA(isA<TestFailure>()));
    },
  );

  test('a later caller preserves the held fields without supplying the secret answer', () async {
    final Fixture f = Fixture(entry: values, supplied: false);
    expect(await exchange.check(f.context), isA<Satisfied>());
    await exchange.apply(f.context);
    expect(f.store.writes, isEmpty);
    f.assertPrivate();
  });

  test('a false satisfied result without a complete matching entry is blocked', () async {
    final Fixture f = Fixture()..producer.forceSatisfied = true;
    expect(await exchange.check(f.context), isA<Blocked>());
    expect(f.store.writes, isEmpty);
  });

  group('a producer that refuses', () {
    // A check is told by what blocks it and an apply by what it throws; both are the reader's.
    final Map<String, Future<String> Function(Fixture)> told =
        <String, Future<String> Function(Fixture)>{
          'check': blockedReason,
          'apply': (Fixture f) async => (await thrownBy(f)).toString(),
        };

    for (final MapEntry<String, Future<String> Function(Fixture)> exchanged in told.entries) {
      group('in ${exchanged.key}', () {
        test('shows the reason it marked, with its exit code, and nothing else it wrote', () async {
          final Fixture f = failing(stderr: 'refused: $publicReason\n')..producer.failureExit = 3;
          expect(
            await exchanged.value(f),
            'the credential producer refused with exit 3: $publicReason',
          );
          expect(f.store.writes, isEmpty);
          f.assertPrivate();
        });

        test('keeps only the marked lines of a mixed stderr, in the order written', () async {
          final Fixture f = failing(
            stderr:
                '$mixedStderr'
                'refused: $secondPublicReason',
          );
          expect(
            await exchanged.value(f),
            'the credential producer refused with exit 1: $publicReason; $secondPublicReason',
          );
          expect(f.store.writes, isEmpty);
          f.assertPrivate();
        });

        for (final MapEntry<String, String> line in unapproved.entries) {
          test('accepts nothing from ${line.key}', () async {
            final Fixture alone = failing(stderr: line.value);
            final String said = await exchanged.value(alone);
            expect(said, isNot(contains(rejectedReason)));
            alone.assertPrivate();
            expect(alone.store.writes, isEmpty);

            // The rejected line costs the lines after it nothing.
            final Fixture beside = failing(stderr: '${line.value}refused: $publicReason\n');
            expect(await exchanged.value(beside), refusedMessage);
            beside.assertPrivate();
          });
        }

        test(
          'withholds a failure that marked nothing, and a marker on stdout is no marker',
          () async {
            for (final Fixture f in <Fixture>[
              failing(),
              failing(stderr: 'Traceback: $unmarkedSecret\n'),
              failing(stdout: 'refused: $rejectedReason\n', stderr: 'Traceback: $unmarkedSecret\n'),
            ]) {
              final String said = await exchanged.value(f);
              expect(said, isNot(contains(rejectedReason)));
              f.assertPrivate();
              expect(f.store.writes, isEmpty);
            }
            final Fixture onStdout = failing(
              stdout: 'refused: $rejectedReason\n',
              stderr: 'refused: $publicReason\n',
            );
            expect(await exchanged.value(onStdout), refusedMessage);
            onStdout.assertPrivate();
          },
        );
      });
    }

    test(
      'stays the generic blocked check and the withheld failure when nothing is marked',
      () async {
        final Fixture f = failing(stderr: 'Traceback: $unmarkedSecret\n');
        expect(await blockedReason(f), withheldCheck);
        final Object thrown = await thrownBy(f);
        expect(thrown, isA<CommandFailed>());
        expect(
          thrown.toString(),
          CommandFailed.withheldOutput(argv: f.producer.commands.last.argv, exitCode: 1).toString(),
        );
        f.assertPrivate();
      },
    );

    test('is a refusal of the exchange and not a failed command once a reason is marked', () async {
      final Fixture f = failing(stderr: 'refused: $publicReason\n');
      expect(await thrownBy(f), isNot(isA<CommandFailed>()));
      expect(await exchange.check(f.context), isA<Blocked>());
    });

    test('is not read at all when the producer succeeds', () async {
      final Fixture f = Fixture()..producer.stderr = 'refused: $publicReason\n';
      expect(await exchange.check(f.context), isA<Ready>());
      await exchange.apply(f.context);
      expect(f.store.entry, values);
      expect(f.recorder.output, isEmpty);
      expect(jsonEncode(f.recorder.logLines), isNot(contains(publicReason)));
      f.assertPrivate();
      expect(f.record, isNot(contains(publicReason)));
    });
  });

  group('through the engine and the record codec', () {
    // Everything a failed row leaves: the engine's verdict, its log, and what the codec writes.
    final Map<String, ({Mode mode, bool onlyApply})> failures =
        <String, ({Mode mode, bool onlyApply})>{
          'a run whose check refuses': (mode: Mode.run, onlyApply: false),
          'a run whose apply refuses': (mode: Mode.run, onlyApply: true),
          'a test whose check refuses': (mode: Mode.test, onlyApply: false),
          'a dry run whose check refuses': (mode: Mode.dry, onlyApply: false),
        };

    for (final MapEntry<String, ({Mode mode, bool onlyApply})> shape in failures.entries) {
      test('${shape.key} shows the approved reason and not a line of the rest', () async {
        final Fixture f = failing(stderr: mixedStderr, onlyApply: shape.value.onlyApply);
        final Run run = await runOf(f, mode: shape.value.mode);
        expectApprovedReason(run, refusedMessage);
        expectNothingUnapproved(run, stderrLines: 4);
        expect(f.store.writes, isEmpty);
      });

      test('${shape.key} without a marked line stays withheld and shows no text', () async {
        final Fixture f = failing(
          stderr: unapproved['no marker'],
          onlyApply: shape.value.onlyApply,
        );
        final Run run = await runOf(f, mode: shape.value.mode);
        final Failed verdict = run.verdict as Failed;
        expect(
          verdict.reason,
          shape.value.onlyApply
              ? CommandFailed.withheldOutput(
                  argv: f.producer.commands.last.argv,
                  exitCode: 1,
                ).toString()
              : withheldCheck,
        );
        expectNothingUnapproved(run, stderrLines: 1);
        expect(f.store.writes, isEmpty);
      });
    }

    test('a row resting on an earlier step is declared in a test and fails in a run', () async {
      final Fixture asTested = failing(stderr: mixedStderr);
      final Run tested = await runOf(asTested, mode: Mode.test, restsOnAnEarlierStep: true);
      expect(tested.verdict, isA<Succeeded>());
      expect(tested.row.standing, StepStanding.declared);
      expect(
        tested.recorder.logLines,
        contains('not answered before the steps it rests on have run: $refusedMessage'),
      );
      expectNothingUnapproved(tested, stderrLines: 4);

      final Fixture asRun = failing(stderr: mixedStderr);
      final Run live = await runOf(asRun, mode: Mode.run, restsOnAnEarlierStep: true);
      expect(live.record.exitCode, 1);
      expectApprovedReason(live, refusedMessage);
      expectNothingUnapproved(live, stderrLines: 4);
    });

    test(
      'the record checks reject disclosure of unmarked output and the loss of the reason',
      () async {
        // The same failing producer, run by a step that has each defect, beside the real step.
        for (final Defect defect in Defect.values) {
          final Fixture f = failing(stderr: mixedStderr, onlyApply: true);
          final Run run = await runOf(f, mode: Mode.run, registry: plantedRegistry(defect));
          if (defect.discloses) {
            expect(
              () => expectNothingUnapproved(run, stderrLines: 4),
              rejectedFor('a secret reached the written record'),
              reason: defect.name,
            );
          } else {
            expectNothingUnapproved(run, stderrLines: 4);
            expect(
              () => expectApprovedReason(run, refusedMessage),
              rejectedFor('lost the approved reason'),
              reason: defect.name,
            );
          }
        }
        final Run innocent = await runOf(
          failing(stderr: mixedStderr, onlyApply: true),
          mode: Mode.run,
        );
        expectApprovedReason(innocent, refusedMessage);
        expectNothingUnapproved(innocent, stderrLines: 4);
      },
    );
  });
}

final class Fixture {
  Fixture({Map<String, String>? entry, String? answer, bool supplied = true})
    : store = Store(entry) {
    final FakeClock clock = FakeClock();
    recorder = MemoryRecorder(clock);
    context = StepContext(
      shell: RecordingShell(producer, recorder: recorder, redactor: Redactor.none, step: name),
      http: RecordingHttp(store, recorder: recorder, redactor: Redactor.none, step: name),
      files: files,
      clock: clock,
      entropy: FakeEntropy(),
      log: RecordingLogger(recorder: recorder, redactor: Redactor.none, step: name),
      step: name,
      arguments: Arguments.none,
      facts: Facts.none,
      answers: Arguments(<String, Object>{
        if (supplied) 'service_token': answer ?? values['other-token']!,
      }),
    );
  }
  static const StepName name = StepName('vault_kv_entry_from_command');
  final Store store;
  final Producer producer = Producer();
  final FakeFiles files = FakeFiles(<String, String>{
    '/checkout/profile.yaml': 'global:\n  vaultUrl: https://vault.example.invalid\n',
    '/checkout/credentials.txt': 'Root Token: fixture-root-secret\n',
  });
  late final StepContext context;
  late final MemoryRecorder recorder;
  String get record =>
      jsonEncode(<Object?>[for (final RunEvent e in recorder.events) const RecordCodec().event(e)]);
  void assertPrivate() {
    for (final String secret in canaries) {
      expect(record, isNot(contains(secret)));
      expect(producer.commands.any((Command c) => c.argv.join(' ').contains(secret)), isFalse);
    }
  }
}

/// A producer that exits nonzero, and the stdout and stderr it wrote doing so.
///
/// [onlyApply] lets its check answer, so a run reaches the apply that then refuses.
Fixture failing({String? stderr, String? stdout, bool onlyApply = false}) => Fixture()
  ..producer.failure = true
  ..producer.failsOnlyApply = onlyApply
  ..producer.stderr = stderr
  ..producer.failureStdout = stdout;

/// What blocks a check of [f].
Future<String> blockedReason(Fixture f) async {
  final CheckResult result = await exchange.check(f.context);
  expect(result, isA<Blocked>());
  return (result as Blocked).reason;
}

/// What an apply of [f] throws.
Future<Object> thrownBy(Fixture f) async {
  try {
    await exchange.apply(f.context);
  } on Object catch (failure) {
    return failure;
  }
  fail('the apply returned');
}

/// One run of the step through the engine, and what it left.
final class Run {
  Run(this.record, this.recorder);
  final RunRecord record;
  final MemoryRecorder recorder;
  StepRecord get row => record.steps.single;
  Verdict get verdict => row.verdict;

  /// Everything the codec writes of the run, the closed record and every event.
  String get written => jsonEncode(<Object?>[
    const RecordCodec().run(record),
    for (final RunEvent e in recorder.events) const RecordCodec().event(e),
  ]);
}

const RunId runId = RunId('20261021T090000Z-1');

/// Runs one row of the step through the engine against the machine [f] stands for.
Future<Run> runOf(
  Fixture f, {
  required Mode mode,
  bool restsOnAnEarlierStep = false,
  Registry registry = vaultKubernetesRegistry,
}) async {
  final FakeClock clock = FakeClock();
  final MemoryRecorder recorder = MemoryRecorder(clock);
  final ResolvedProgram program = ProgramResolver(registry).resolve(
    Program(
      name: const ProgramName('credential'),
      roles: const <Role>[Role('master')],
      steps: <ProgramStep>[
        ProgramStep(
          step: Fixture.name,
          onFailure: OnFailure.exit,
          restsOnAnEarlierStep: restsOnAnEarlierStep,
          arguments: Arguments(<String, Object>{
            'repository': exchange.repository,
            'mount': exchange.mount,
            'path': exchange.path,
            'fields': exchange.fields,
            'producer': exchange.producer,
            'profile_path': layout.profile,
            'vault_url_key': layout.urlKey,
            'cluster_name_key': layout.nameKey,
            'kubernetes_auth_path_key': layout.authPathKey,
            'credentials_path': layout.credentials,
          }),
        ),
      ],
    ),
  );
  final RunRecord closed =
      await Runner(
        machine: Machine(
          shell: f.producer,
          files: f.files,
          http: f.store,
          clock: clock,
          entropy: FakeEntropy(),
        ),
        recorder: recorder,
        redactor: Redactor(const <String>[]),
      ).run(
        program: program,
        mode: mode,
        header: RunRecord(
          id: runId,
          program: const ProgramName('credential'),
          mode: mode,
          argv: const <String>['ansiwise', 'credential'],
          start: clock.now(),
          stage: const Stage('dev'),
          role: const Role('master'),
          fqdn: const Fqdn('m1.example.com'),
          commit: '0000000',
          fingerprint: 'test-fingerprint',
        ),
      );
  return Run(closed, recorder);
}

/// The row failed, and its verdict, the log and the written record all say [reason].
void expectApprovedReason(Run run, String reason) {
  final Verdict verdict = run.verdict;
  expect(verdict, isA<Failed>(), reason: 'the row did not fail');
  expect((verdict as Failed).reason, reason, reason: 'the verdict lost the approved reason');
  final StepFinished finished = run.recorder.only<StepFinished>().single;
  final Object? json = jsonDecode(jsonEncode(const RecordCodec().event(finished)));
  final RunEvent read = const RecordCodec().eventFrom(json! as Map<String, Object?>);
  expect(
    ((read as StepFinished).verdict as Failed).reason,
    reason,
    reason: 'the codec lost the approved reason',
  );
  expect(run.written, contains(jsonEncode(reason)), reason: 'the record lost the approved reason');
}

/// No secret reached the written record, and the lines the producer wrote are only counted.
void expectNothingUnapproved(Run run, {required int stderrLines}) {
  for (final String secret in canaries) {
    expect(run.written, isNot(contains(secret)), reason: 'a secret reached the written record');
  }
  final RegExp counted = RegExp(r'^\[withheld (\d+) lines?: ');
  expect(
    <String>[
      for (final Output o in run.recorder.only<Output>())
        '${o.stream.name}: ${counted.firstMatch(o.text)?.group(1) ?? o.text}',
    ],
    <String>['stdout: 1', 'stderr: $stderrLines'],
    reason: 'the withheld counts changed',
  );
}

/// A check that fails with a message naming [why].
Matcher rejectedFor(String why) =>
    throwsA(isA<TestFailure>().having((TestFailure e) => '${e.message}', 'message', contains(why)));

/// How a step that wants to say why a producer failed can say it wrongly.
enum Defect {
  disclosesInTheVerdict(discloses: true),
  disclosesInTheLog(discloses: true),
  losesTheReason(discloses: false);

  const Defect({required this.discloses});
  final bool discloses;
}

/// The registry a program row resolves to a step with [defect].
Registry plantedRegistry(Defect defect) => Registry(
  steps: <StepName, RegisteredStep>{
    Fixture.name: RegisteredStep(
      name: Fixture.name,
      source: 'test/vault_kv_entry_from_command_test.dart',
      create: (Arguments arguments) => PlantedExchange(defect),
      arguments: VaultKvEntryFromCommand.arguments,
    ),
  },
  predicates: const <PredicateName, RegisteredPredicate>{},
);

/// Runs the producer as the real step does and reports its failure with [defect].
final class PlantedExchange extends IrreversibleStep {
  const PlantedExchange(this.defect);
  final Defect defect;

  @override
  String get irreversibleReason => 'planted';

  @override
  Future<CheckResult> check(StepContext context) async {
    await _exchange(context, apply: false);
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('planted');

  @override
  Future<void> apply(StepContext context) => _exchange(context, apply: true);

  Future<void> _exchange(StepContext context, {required bool apply}) async {
    final List<String> argv = <String>['bash', exchange.producer, apply ? '--apply' : '--check'];
    final CommandResult result = await context.shell.run(
      Command.detailed(
        argv.first,
        arguments: argv.sublist(1),
        stdin: jsonEncode(<String, Object?>{'entry': null, 'inputs': <String, String>{}}),
        observes: !apply,
        secretOutput: true,
      ),
    );
    if (result.ok) return;
    switch (defect) {
      case Defect.disclosesInTheVerdict:
        throw CommandFailed(
          argv: argv,
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      case Defect.disclosesInTheLog:
        context.log.info(result.stderr);
        throw const _Said(refusedMessage);
      case Defect.losesTheReason:
        throw CommandFailed.withheldOutput(argv: argv, exitCode: result.exitCode);
    }
  }
}

final class _Said implements Exception {
  const _Said(this.message);
  final String message;
  @override
  String toString() => message;
}

final class Producer implements Shell {
  final List<Command> commands = <Command>[];
  String? output, stderr, failureStdout;
  int failureExit = 1;
  bool failure = false, timeout = false, forceSatisfied = false, failsOnlyApply = false;
  @override
  Future<CommandResult> run(Command command) async {
    commands.add(command);
    if (timeout) throw TimeoutException('fixture-api-secret');
    final Map<String, dynamic> input = jsonDecode(command.stdin!) as Map<String, dynamic>;
    final Map<String, String> wanted = <String, String>{
      ...values,
      ...Map<String, String>.from(input['inputs'] as Map),
    };
    final bool fails = failure && !(failsOnlyApply && command.observes);
    return CommandResult(
      exitCode: fails ? failureExit : 0,
      stdout: fails
          ? failureStdout ?? values['api-token']!
          : output ??
                (command.observes
                    ? jsonEncode(<String, bool>{
                        'satisfied':
                            forceSatisfied || jsonEncode(input['entry']) == jsonEncode(wanted),
                      })
                    : jsonEncode(wanted)),
      stderr: stderr ?? (fails ? values['other-token']! : ''),
      elapsed: Duration.zero,
    );
  }
}

// Strict about check-and-set, as Vault is: a write names the entry's current version, which a
// deleted latest version keeps (KV v2 createupdate-secret), or 0 where nothing was ever written.
final class Store implements Http {
  Store(this.entry);
  Map<String, String>? entry;
  int status = 200, version = 1;
  int? deleted;
  bool refuseWrite = false, ignoreWrite = false;
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];
  int get _current => entry != null ? version : deleted ?? 0;
  HttpAnswer _answer(int status, Object? body) => HttpAnswer(
    status: status,
    body: jsonEncode(body),
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );
  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    if (status != 200) return _answer(status, null);
    if (request.url.contains('/metadata/')) {
      return entry == null && deleted == null
          ? _answer(404, <String, Object>{'errors': <Object>[]})
          : _answer(200, <String, Object?>{
              'data': <String, Object?>{'current_version': _current},
            });
    }
    if (request.method == 'POST') {
      final Map<String, Object?> body = jsonDecode(request.body!) as Map<String, Object?>;
      writes.add(body);
      if (refuseWrite) {
        return const HttpAnswer(
          status: 409,
          body: 'fixture-api-secret',
          headers: <String, String>{},
          elapsed: Duration.zero,
        );
      }
      if ((body['options']! as Map<String, Object?>)['cas'] != _current) {
        return _answer(400, <String, Object>{
          'errors': <String>['check-and-set parameter did not match the current version'],
        });
      }
      version = _current + 1;
      if (!ignoreWrite) entry = Map<String, String>.from(body['data']! as Map);
    }
    return _answer(entry == null ? 404 : 200, <String, Object?>{
      'data': <String, Object?>{
        'data': entry,
        'metadata': <String, Object>{'version': entry == null ? _current : version},
      },
    });
  }
}
