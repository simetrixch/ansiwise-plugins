import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// Materializing one field of one entry into a file on the machine.
///
/// The property everything here circles is that the CREDENTIAL passes through the run and reaches
/// nothing but the file: the check decides on presence without reading the store, the plan names
/// the read and the file and never the value, and a field the entry does not carry is reported as
/// the skipped earlier row it is — never papered over with a fresh value, because nothing mints
/// here.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentials = '$repository/secrets/vault-dev.txt';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String entryPath = 'dev/machine/serve';
  const String dataPath = 'secret/data/$entryPath';
  const String field = 'service-token';
  const String value = 'ThisIsNotARealServiceTokenItIsATestFixture';
  const String filePath = '/etc/serve/service-token';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  const FileFromVault step = FileFromVault(
    repository: repository,
    mount: 'secret',
    path: '<stage>/machine/serve',
    field: field,
    filePath: filePath,
    fileMode: 384,
    layout: layout,
    elevated: true,
  );

  /// A checkout whose profile names the store and whose credential file carries the root token.
  FakeFiles checkout() => FakeFiles(<String, String>{
    profilePath: 'global:\n  vaultUrl: $url\n',
    credentials: renderCredentials(url: url, unsealKeys: <String>['k1'], rootToken: token),
  });

  StepContext contextOn(FakeFiles files, Http http) => StepContext(
    shell: FakeShell(),
    files: files,
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev'}),
    facts: Facts.none,
  );

  group('what the apply writes', () {
    test(
      'the field of the entry becomes the whole of the file, only its owner may read it',
      () async {
        final ScriptedHttp http = ScriptedHttp(
          (HttpRequest request, int nth) => answer('{"data":{"data":{"$field":"$value"}}}'),
        );
        final FakeFiles files = checkout();

        await step.apply(contextOn(files, http));

        expect(files.contents[filePath], value);
        expect(files.modes[filePath], 384);
        expect(http.sent.single.url, '$url/v1/$dataPath');
      },
    );

    test('PLANTED DEFECT: an entry without the field is a skipped earlier row, and no file '
        'appears', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"data":{"data":{"another-field":"held"}}}'),
      );
      final FakeFiles files = checkout();

      await expectLater(
        step.apply(contextOn(files, http)),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(contains(field), contains('earlier row')),
          ),
        ),
      );
      expect(
        files.contents.containsKey(filePath),
        isFalse,
        reason: 'nothing mints here, so nothing may land in the file either',
      );
    });
  });

  group('what the check decides on', () {
    test(
      'a machine already carrying the file is satisfied, and the store is not read for it',
      () async {
        final ScriptedHttp http = ScriptedHttp(
          (HttpRequest request, int nth) => answer('{"data":{"data":{"$field":"$value"}}}'),
        );
        final FakeFiles files = checkout();
        files.contents[filePath] = value;

        expect(await step.check(contextOn(files, http)), isA<Satisfied>());
        expect(
          http.sent,
          isEmpty,
          reason:
              'presence is the question — reading the credential to compare would carry it '
              'through every converge run',
        );
      },
    );

    test('a machine without the file has work to do', () async {
      expect(await step.check(contextOn(checkout(), FakeHttp())), isA<Ready>());
    });
  });

  group('what reaches the record', () {
    test('the plan names the read and the file, and never the value', () async {
      final StepPlan plan = await step.plan(contextOn(checkout(), FakeHttp()));
      expect(plan, isA<RequestPlan>());
      final RequestPlan request = plan as RequestPlan;
      expect(request.url, '$url/v1/$dataPath');
      expect(request.body, allOf(contains(field), contains(filePath), isNot(contains(value))));
    });
  });

  group('what the undo takes back', () {
    test('a file this run created goes away again', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"data":{"data":{"$field":"$value"}}}'),
      );
      final FakeFiles files = checkout();
      final StepContext context = contextOn(files, http);

      final bool wasThere = await step.capture(context);
      await step.apply(context);
      await step.undo(context, wasThere);

      expect(files.contents.containsKey(filePath), isFalse);
    });

    test('a file that was already there stays', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"data":{"data":{"$field":"$value"}}}'),
      );
      final FakeFiles files = checkout();
      files.contents[filePath] = 'what was already being presented';
      final StepContext context = contextOn(files, http);

      final bool wasThere = await step.capture(context);
      await step.apply(context);
      await step.undo(context, wasThere);

      expect(files.contents.containsKey(filePath), isTrue);
    });
  });
}

HttpAnswer answer(String body, {int status = 200}) => HttpAnswer(
  status: status,
  body: body,
  headers: const <String, String>{},
  elapsed: Duration.zero,
);

/// A log that keeps nothing, so a step's own notes do not land in the middle of a test run.
final class SilentLog implements Logger {
  /// Creates the log.
  const SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// A network port that records what was sent, so a test can assert what was NOT read as sharply as
/// what was.
final class ScriptedHttp implements Http {
  ScriptedHttp(this._answer);

  final HttpAnswer Function(HttpRequest request, int nth) _answer;

  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final int nth = sent
        .where((HttpRequest each) => each.method == request.method && each.url == request.url)
        .length;
    sent.add(request);
    return _answer(request, nth);
  }
}
