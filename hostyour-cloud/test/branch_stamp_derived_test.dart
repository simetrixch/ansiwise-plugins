import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

void main() {
  const String repository = '/srv/hostyour-cloud';
  const String masterFqdn = 'm1.example.com';
  const String slaveFqdn = 's1.example.com';
  const String trunk = 'master';
  const String keepMarker = 'set-domain:keep';

  StepContext contextFor({required FakeShell shell, required FakeFiles files, required Arguments answers}) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  FakeShell searching({
    required List<String> carrying,
    String head = 'm1.example.com',
    required String literal,
    String? within,
  }) {
    final List<String> argv = <String>[
      'git',
      '-C',
      repository,
      'grep',
      '--full-name',
      '--files-with-matches',
      '--fixed-strings',
      '-e',
      literal,
      if (within != null) ...<String>['--', within],
    ];
    final FakeShell shell = FakeShell()
      ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$head\n');
    if (carrying.isEmpty) {
      shell.fails(argv.join(' '));
    } else {
      shell.answers(argv.join(' '), '${carrying.join('\n')}\n');
    }
    return shell;
  }

  FakeFiles tree(Map<String, String> files) => FakeFiles(<String, String>{
    for (final MapEntry<String, String> f in files.entries) '$repository/${f.key}': f.value,
  });

  String read(FakeFiles files, String path) => files.contents['$repository/$path'] ?? '';

  group('StampDerivedPlaceholder master behavior', () {
    final Arguments masterAnswers = Arguments(<String, Object>{
      'fqdn': masterFqdn,
      'role': 'master',
    });

    test('replaces __CLUSTER__ with short name', () async {
      final FakeFiles files = tree(<String, String>{
        'file.yaml': 'cluster: __CLUSTER__\n',
      });
      final FakeShell shell = searching(carrying: <String>['file.yaml'], literal: '__CLUSTER__');
      final StampDerivedPlaceholder stamp = StampDerivedPlaceholder(
        repository: repository,
        trunk: trunk,
        placeholder: '__CLUSTER__',
        derivedValue: 'cluster',
        keepMarker: keepMarker,
      );

      await stamp.apply(contextFor(shell: shell, files: files, answers: masterAnswers));
      expect(read(files, 'file.yaml'), contains('cluster: m1'));
    });

    test('replaces __BOOKS_BRANCH__ with fqdn', () async {
      final FakeFiles files = tree(<String, String>{
        'file.yaml': 'revision: __BOOKS_BRANCH__\n',
      });
      final FakeShell shell = searching(carrying: <String>['file.yaml'], literal: '__BOOKS_BRANCH__');
      final StampDerivedPlaceholder stamp = StampDerivedPlaceholder(
        repository: repository,
        trunk: trunk,
        placeholder: '__BOOKS_BRANCH__',
        derivedValue: 'books_branch',
        keepMarker: keepMarker,
      );

      await stamp.apply(contextFor(shell: shell, files: files, answers: masterAnswers));
      expect(read(files, 'file.yaml'), contains('revision: m1.example.com'));
    });
  });

  group('StampDerivedPlaceholder slave behavior', () {
    final Arguments slaveAnswers = Arguments(<String, Object>{
      'fqdn': slaveFqdn,
      'role': 'slave',
      'master': masterFqdn,
    });

    test('replaces __CLUSTER__ with short name of slave', () async {
      final FakeFiles files = tree(<String, String>{
        'file.yaml': 'cluster: __CLUSTER__\n',
      });
      final FakeShell shell = searching(carrying: <String>['file.yaml'], literal: '__CLUSTER__', head: slaveFqdn);
      final StampDerivedPlaceholder stamp = StampDerivedPlaceholder(
        repository: repository,
        trunk: trunk,
        placeholder: '__CLUSTER__',
        derivedValue: 'cluster',
        keepMarker: keepMarker,
      );

      await stamp.apply(contextFor(shell: shell, files: files, answers: slaveAnswers));
      expect(read(files, 'file.yaml'), contains('cluster: s1'));
    });

    test('replaces __BOOKS_BRANCH__ with master name', () async {
      final FakeFiles files = tree(<String, String>{
        'file.yaml': 'revision: __BOOKS_BRANCH__\n',
      });
      final FakeShell shell = searching(carrying: <String>['file.yaml'], literal: '__BOOKS_BRANCH__', head: slaveFqdn);
      final StampDerivedPlaceholder stamp = StampDerivedPlaceholder(
        repository: repository,
        trunk: trunk,
        placeholder: '__BOOKS_BRANCH__',
        derivedValue: 'books_branch',
        keepMarker: keepMarker,
      );

      await stamp.apply(contextFor(shell: shell, files: files, answers: slaveAnswers));
      expect(read(files, 'file.yaml'), contains('revision: m1.example.com'));
    });
  });
}

class _SilentLog implements Logger {
  const _SilentLog();
  @override
  void debug(String message) {}
  @override
  void info(String message) {}
  @override
  void warn(String message) {}
  @override
  void error(String message) {}
  @override
  void notice(String message) {}
}
