import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Placing a checkout on a machine from what the machine's own settings say, and keeping it on the
/// branch's published tip.
///
/// The property everything here circles is WHERE the credential travels: it is read out of one
/// settings file, rides the environment of the commands that reach the network, and appears in no
/// command argument and in no stored remote address — because an argument is in the process listing
/// and the record, and a stored address is at rest for as long as the checkout stands.
void main() {
  // What a product's program rows would state. The step carries no defaults for these — the paths
  // and the keys are one installation's own — so the tests state them the way a row does.
  const String path = '/srv/programs-checkout';
  const String host = 'code.example.com';
  const String settingsFile = '/srv/checkout/settings/values.dev';
  const String settingsKey = 'PROGRAMS_REPO';
  const String credentialFile = '/srv/checkout/settings/secrets.dev';
  const String credentialKey = 'PROGRAMS_REPO_READ_CREDENTIAL';
  const String ownerName = 'acme/acme-deploy';
  const String url = 'https://$host/$ownerName.git';
  const String credential = 'NotARealCredentialItIsATestFixture';
  const String tip = '4bd8b06bb2fa9d591a80c06a01e0e40b0b9f8d2e';

  const GitClone step = GitClone(
    repository: path,
    host: host,
    branch: base,
    originFile: settingsFile,
    originKey: settingsKey,
    credentialFile: credentialFile,
    credentialKey: credentialKey,
    credentialUser: 'reader',
    runAnswer: null,
  );

  FakeFiles settings({String? credentialValue = credential}) => FakeFiles(<String, String>{
    settingsFile: '# what this installation reads its programs from\n$settingsKey=$ownerName\n',
    credentialFile: credentialValue == null
        ? '$credentialKey=\n'
        : '$credentialKey=$credentialValue\n',
  });

  /// A machine with no checkout at the path.
  FakeShell bare() {
    final FakeShell shell = FakeShell();
    shell.fails('git -C $path rev-parse --is-inside-work-tree');
    return shell;
  }

  /// A machine whose checkout stands exactly where the remote publishes the branch.
  FakeShell standing({String localTip = tip}) {
    final FakeShell shell = FakeShell();
    shell
      ..answers('git -C $path rev-parse --is-inside-work-tree', 'true\n')
      ..answers('git -C $path remote get-url origin', '$url\n')
      ..answers('git -C $path rev-parse --abbrev-ref HEAD', '$base\n')
      ..answers('git ls-remote --heads $url $base', '$tip\trefs/heads/$base\n')
      ..answers('git -C $path rev-parse HEAD', '$localTip\n');
    return shell;
  }

  group('where the credential travels', () {
    test('the clone carries the plain address, and the credential rides the environment', () async {
      final FakeShell shell = bare();
      await step.apply(contextOn(shell: shell, files: settings()));

      expect(shell.ran, contains('git clone --branch $base $url $path'));
      final Command clone = shell.commands.firstWhere(
        (Command command) => command.arguments.first == 'clone',
      );
      expect(clone.environment['GIT_CONFIG_KEY_0'], 'http.https://$host/.extraHeader');
      expect(clone.environment['GIT_CONFIG_VALUE_0'], startsWith('Authorization: Basic '));
    });

    test('no command of a whole apply names the credential in an argument', () async {
      final FakeShell shell = bare();
      await step.apply(contextOn(shell: shell, files: settings()));
      for (final String command in shell.ran) {
        expect(command, isNot(contains(credential)));
      }
    });

    test('PLANTED DEFECT: a machine whose settings hold no credential is refused by file and key, '
        'and nothing is cloned', () async {
      final CheckResult result = await step.check(
        contextOn(shell: bare(), files: settings(credentialValue: null)),
      );
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, allOf(contains(credentialKey), contains(credentialFile)));

      final FakeShell shell = bare();
      await expectLater(
        step.apply(contextOn(shell: shell, files: settings(credentialValue: null))),
        throwsA(isA<StateError>()),
      );
      expect(shell.ran, isEmpty, reason: 'a run that cannot read with what it needs asks nothing');
    });

    test('a value still carrying the text that marks it unfilled is an absent value', () async {
      final CheckResult result = await step.check(
        contextOn(
          shell: bare(),
          files: settings(credentialValue: '<obtain one and fill it in>'),
        ),
      );
      expect(result, isA<Blocked>());
    });
  });

  group('what a run finds and corrects', () {
    test('a machine with no checkout has work to do', () async {
      expect(await step.check(contextOn(shell: bare(), files: settings())), isA<Ready>());
    });

    test(
      'a checkout on the published tip is finished, and the remote was asked to say so',
      () async {
        final FakeShell shell = standing();
        expect(await step.check(contextOn(shell: shell, files: settings())), isA<Satisfied>());
        expect(shell.ran, contains('git ls-remote --heads $url $base'));
      },
    );

    test('a checkout that fell behind the remote is work, and the apply fetches and places the '
        'branch', () async {
      final FakeShell shell = standing(localTip: 'f6c1a2d90b7e8f3a4c5d6e7f8a9b0c1d2e3f4a5b');
      expect(await step.check(contextOn(shell: shell, files: settings())), isA<Ready>());

      await step.apply(contextOn(shell: shell, files: settings()));
      expect(
        shell.ran,
        containsAllInOrder(<String>[
          'git -C $path fetch origin $base',
          'git -C $path checkout -B $base origin/$base',
        ]),
      );
      expect(shell.ran, isNot(contains('git clone --branch $base $url $path')));
    });

    test(
      'a remote pointing somewhere else is corrected to the address the settings compose',
      () async {
        final FakeShell shell = standing();
        shell.answers('git -C $path remote get-url origin', 'https://$host/somebody/else.git\n');
        expect(await step.check(contextOn(shell: shell, files: settings())), isA<Ready>());

        await step.apply(contextOn(shell: shell, files: settings()));
        expect(shell.ran, contains('git -C $path remote set-url origin $url'));
      },
    );

    test(
      'a remote that cannot be asked is blocked, naming the credential it was asked with',
      () async {
        final FakeShell shell = standing();
        shell.fails(
          'git ls-remote --heads $url $base',
          stderr: 'fatal: could not read from remote',
        );
        final CheckResult result = await step.check(contextOn(shell: shell, files: settings()));
        expect(result, isA<Blocked>());
        expect((result as Blocked).reason, contains(credentialKey));
      },
    );
  });
}
