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
      final Fixture f = Fixture()..store.status = status;
      expect(await exchange.check(f.context), isA<Blocked>());
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
      await f.context.shell.run(
        Command.detailed(
          'bash',
          stdin: jsonEncode(<String, Object?>{'entry': null, 'inputs': <String, String>{}}),
          secretOutput: false,
        ),
      );
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
  void assertPrivate() {
    final String record = jsonEncode(<Object?>[
      for (final RunEvent e in recorder.events) const RecordCodec().event(e),
    ]);
    for (final String secret in <String>[
      ...values.values,
      'fixture-root-secret',
      'replacement-secret',
    ]) {
      expect(record, isNot(contains(secret)));
      expect(producer.commands.any((Command c) => c.argv.join(' ').contains(secret)), isFalse);
    }
  }
}

final class Producer implements Shell {
  final List<Command> commands = <Command>[];
  String? output;
  bool failure = false, timeout = false, forceSatisfied = false;
  @override
  Future<CommandResult> run(Command command) async {
    commands.add(command);
    if (timeout) throw TimeoutException('fixture-api-secret');
    final Map<String, dynamic> input = jsonDecode(command.stdin!) as Map<String, dynamic>;
    final Map<String, String> wanted = <String, String>{
      ...values,
      ...Map<String, String>.from(input['inputs'] as Map),
    };
    return CommandResult(
      exitCode: failure ? 1 : 0,
      stdout: failure
          ? values['api-token']!
          : output ??
                (command.observes
                    ? jsonEncode(<String, bool>{
                        'satisfied':
                            forceSatisfied || jsonEncode(input['entry']) == jsonEncode(wanted),
                      })
                    : jsonEncode(wanted)),
      stderr: failure ? values['other-token']! : '',
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
