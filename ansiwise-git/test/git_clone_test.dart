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

  // ---------------------------------------------------------------------------------------------
  // THE FIRST CHECKOUT OF AN INSTALLATION, which has no earlier program to have written a file.
  //
  // Every case above reads which repository and with what right OUT OF THE MACHINE, which is right
  // and stays the ordinary way. It cannot be the only way: the programs live in a checkout, so the
  // very first one is made before any program of that installation has run and before any file it
  // would have written exists. Such a checkout names its repository in an ANSWER — still a NAME in
  // the program file, with the value coming from the installation's own answers — and, where the
  // repository is served to anybody, is read with no credential at all.
  // ---------------------------------------------------------------------------------------------
  group('a checkout made before this machine records anything', () {
    const String openOwnerName = 'acme/acme-platform';
    const String openUrl = 'https://$host/$openOwnerName.git';
    const String originAnswer = 'platform_repo';

    const GitClone open = GitClone(
      repository: path,
      host: host,
      branch: base,
      originAnswer: originAnswer,
      runAnswer: null,
    );

    StepContext holding(String? ownerName, {FakeShell? shell}) => contextOn(
      shell: shell ?? bare(),
      files: FakeFiles(),
      name: ownerName,
      answerName: originAnswer,
    );

    test('is cloned from the answer, with no file of this machine read at all', () async {
      final FakeShell shell = bare();
      await open.apply(holding(openOwnerName, shell: shell));
      expect(shell.ran, contains('git clone --branch $base $openUrl $path'));
    });

    test('carries NO authorization header, because none was asked for', () async {
      // An empty environment and a header saying `null:null` are not the same thing. The second is
      // sent to a server that never asked for one and is refused by some of them.
      final FakeShell shell = bare();
      await open.apply(holding(openOwnerName, shell: shell));
      final Command clone = shell.commands.firstWhere(
        (Command command) => command.arguments.first == 'clone',
      );
      expect(clone.environment.containsKey('GIT_CONFIG_KEY_0'), isFalse);
      expect(clone.environment.containsKey('GIT_CONFIG_VALUE_0'), isFalse);
    });

    test('a run holding no such answer is refused, naming the answer and not a file', () async {
      final CheckResult result = await open.check(holding(null));
      expect(result, isA<Blocked>());
      expect(
        (result as Blocked).reason,
        allOf(contains(originAnswer), isNot(contains('.dev'))),
        reason: 'a refusal pointing at a settings file sends somebody to a file that is not there',
      );
    });

    test('stands on the branch the run answers, and not on one written into the row', () async {
      // The material of an installation stands on THAT installation's branch. A row writing one
      // would move every other installation's checkout onto it the next time it ran.
      const GitClone answered = GitClone(
        repository: path,
        host: host,
        branchAnswer: 'platform_branch',
        originAnswer: originAnswer,
        runAnswer: null,
      );
      final FakeShell shell = bare();
      await answered.apply(
        contextOn(
          shell: shell,
          files: FakeFiles(),
          name: openOwnerName,
          answerName: originAnswer,
          also: const <String, Object>{'platform_branch': 'apps1.example.com'},
        ),
      );
      expect(shell.ran, contains('git clone --branch apps1.example.com $openUrl $path'));
    });

    test('a run holding no branch answer is refused, naming that answer', () async {
      const GitClone answered = GitClone(
        repository: path,
        host: host,
        branchAnswer: 'platform_branch',
        originAnswer: originAnswer,
        runAnswer: null,
      );
      final CheckResult result = await answered.check(
        contextOn(shell: bare(), files: FakeFiles(), name: openOwnerName, answerName: originAnswer),
      );
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('platform_branch'));
    });

    test('the directory is made for its owner BEFORE git, and handed over AFTER it', () async {
      // TWO ACTS AND THE ORDER BETWEEN THEM IS THE WHOLE OF IT. The directory is made with elevation
      // first, because a checkout under a path only root may write cannot be created by the account
      // that has to use it. The hand-over comes LAST, because git writes the repository into that
      // directory in between — and a program of this kind is started elevated, so a row that asks
      // for no elevation of its own is still a root process. Handing over first gave the account an
      // empty directory and left root owning the `.git` inside it, on every machine, from the first
      // install. Nothing met it while only elevated programs drove that checkout; the first caller
      // that was not root was refused by git outright.
      //
      // This check used to pin the order the other way round, which is why it went red on the fix
      // rather than on the defect — the order is asserted here so the next reader cannot quietly
      // put it back.
      const GitClone owned = GitClone(
        repository: path,
        host: host,
        branch: base,
        originAnswer: originAnswer,
        ownerAnswer: 'operator_user',
        runAnswer: null,
      );
      final FakeShell shell = bare();
      await owned.apply(
        contextOn(
          shell: shell,
          files: FakeFiles(),
          name: openOwnerName,
          answerName: originAnswer,
          also: const <String, Object>{'operator_user': 'digi1'},
        ),
      );

      expect(
        shell.ran,
        containsAllInOrder(<String>[
          'install -d -o digi1 -g digi1 $path',
          'git clone --branch $base $openUrl $path',
          'chown -R digi1:digi1 $path',
        ]),
        reason: 'git is asked nothing until the directory is one the run may use',
      );
    });

    test('a checkout standing under the WRONG owner is work, not a satisfied machine', () async {
      // What a machine left by an earlier shape of this row looks like: the tree is there, on the
      // right branch, at the right tip — and git will not read a word of it.
      const GitClone owned = GitClone(
        repository: path,
        host: host,
        branch: base,
        originAnswer: originAnswer,
        ownerAnswer: 'operator_user',
        runAnswer: null,
      );
      // EVERYTHING ELSE MATCHES, which is the whole point: the tree is there, its remote is right,
      // it is on the branch and at the tip. Only the owner is wrong, so a check that missed that
      // would call this machine finished. The first shape of this test used the shared `standing`
      // fixture, whose remote is the settings-based address — so it passed for the wrong reason and
      // stayed green when the ownership reading was taken out.
      final FakeShell shell = FakeShell();
      shell
        ..answers('stat -c %U $path', 'root\n')
        ..answers('git -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip\trefs/heads/$base\n')
        ..answers('git -C $path rev-parse HEAD', '$tip\n');

      expect(
        await owned.check(
          contextOn(
            shell: shell,
            files: FakeFiles(),
            name: openOwnerName,
            answerName: originAnswer,
            also: const <String, Object>{'operator_user': 'digi1'},
          ),
        ),
        isA<Ready>(),
        reason: 'every git question would come back as the same refusal, saying nothing',
      );
    });

    // THE SHAPE THAT GOT PAST THIS CHECK AND STILL LOST, met on a real machine. The worktree had
    // been handed to the operator account and the `.git` inside it was still the one that made it.
    // This row read the OUTER directory, called the hand-over done, and apply never ran — so git
    // went on refusing the repository to every caller but that one, with `fatal: detected dubious
    // ownership`, on a machine whose install had reported success.
    //
    // Git decides on the `.git`. So does this now.
    test('a worktree handed over whose .git was left behind is NOT finished', () async {
      const GitClone owned = GitClone(
        repository: path,
        host: host,
        branch: base,
        originAnswer: openOwnerName,
        ownerAnswer: 'operator_user',
        runAnswer: null,
      );
      final FakeShell shell = FakeShell();
      shell
        ..answers('stat -c %U $path', 'digi1\n')
        ..answers('stat -c %U $path/.git', 'root\n')
        ..answers('git -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip	refs/heads/$base\n')
        ..answers('git -C $path rev-parse HEAD', '$tip\n');

      expect(
        await owned.check(
          contextOn(
            shell: shell,
            files: FakeFiles(),
            name: openOwnerName,
            answerName: openOwnerName,
            also: const <String, Object>{'operator_user': 'digi1'},
          ),
        ),
        isA<Ready>(),
        reason: 'the outer directory says handed over and git still refuses — the .git decides',
      );
    });

    test('a checkout already under the right owner is not disturbed', () async {
      const GitClone owned = GitClone(
        repository: path,
        host: host,
        branch: base,
        originAnswer: openOwnerName,
        ownerAnswer: 'operator_user',
        runAnswer: null,
      );
      final FakeShell shell = FakeShell();
      shell
        ..answers('stat -c %U $path', 'digi1\n')
        ..answers('git -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip\trefs/heads/$base\n')
        ..answers('git -C $path rev-parse HEAD', '$tip\n');

      expect(
        await owned.check(
          contextOn(
            shell: shell,
            files: FakeFiles(),
            name: openOwnerName,
            answerName: openOwnerName,
            also: const <String, Object>{'operator_user': 'digi1'},
          ),
        ),
        isA<Satisfied>(),
      );
    });

    test('INNOCENT CASE: the shape every other case here uses is untouched', () async {
      final FakeShell shell = bare();
      await step.apply(contextOn(shell: shell, files: settings()));
      final Command clone = shell.commands.firstWhere(
        (Command command) => command.arguments.first == 'clone',
      );
      expect(clone.environment['GIT_CONFIG_VALUE_0'], startsWith('Authorization: Basic '));
      expect(shell.ran, contains('git clone --branch $base $url $path'));
    });
  });

  group('COUNTER-PROBE: a row whose own shape is wrong is refused before a machine is asked', () {
    /// The row as it would stand with [named] given and everything else left off.
    GitClone rowWith({
      String? originFile,
      String? originKey,
      String? originAnswer,
      String? credentialFile,
      String? credentialKey,
      String? credentialUser,
    }) => GitClone(
      repository: path,
      host: host,
      branch: base,
      originFile: originFile,
      originKey: originKey,
      originAnswer: originAnswer,
      credentialFile: credentialFile,
      credentialKey: credentialKey,
      credentialUser: credentialUser,
      runAnswer: null,
    );

    Future<String> refusalOf(GitClone row) async {
      final FakeShell shell = bare();
      final CheckResult result = await row.check(
        contextOn(shell: shell, files: settings(), name: 'acme/whatever', answerName: 'anything'),
      );
      expect(result, isA<Blocked>(), reason: 'a row of this shape can never be read');
      expect(shell.ran, isEmpty, reason: 'the row is wrong wherever it runs, so nothing is asked');
      return (result as Blocked).reason;
    }

    test('both branches — two answers to which branch it stands on', () async {
      expect(
        await refusalOf(
          const GitClone(
            repository: path,
            host: host,
            branch: base,
            branchAnswer: 'platform_branch',
            originAnswer: 'platform_repo',
            runAnswer: null,
          ),
        ),
        allOf(contains('branch'), contains('branch_answer')),
      );
    });

    test('neither branch — nothing says which one it stands on', () async {
      expect(
        await refusalOf(
          const GitClone(
            repository: path,
            host: host,
            originAnswer: 'platform_repo',
            runAnswer: null,
          ),
        ),
        allOf(contains('branch'), contains('branch_answer')),
      );
    });

    test('both origin sources — two answers to one question', () async {
      expect(
        await refusalOf(
          rowWith(originFile: settingsFile, originKey: settingsKey, originAnswer: 'platform_repo'),
        ),
        allOf(contains('origin_file'), contains('origin_answer')),
      );
    });

    test('neither origin source — nothing says which repository', () async {
      expect(await refusalOf(rowWith()), allOf(contains('origin_file'), contains('origin_answer')));
    });

    test('a file with no key names no value in it', () async {
      expect(
        await refusalOf(rowWith(originFile: settingsFile)),
        allOf(contains('origin_file'), contains('origin_key')),
      );
    });

    for (final (String half, GitClone Function() row) in <(String, GitClone Function())>[
      (
        'a credential with no account name',
        () => const GitClone(
          repository: path,
          host: host,
          branch: base,
          originAnswer: 'platform_repo',
          credentialFile: credentialFile,
          credentialKey: credentialKey,
          runAnswer: null,
        ),
      ),
      (
        'an account name with nothing behind it',
        () => const GitClone(
          repository: path,
          host: host,
          branch: base,
          originAnswer: 'platform_repo',
          credentialUser: 'reader',
          runAnswer: null,
        ),
      ),
    ]) {
      test('$half — the three are a group', () async {
        expect(await refusalOf(row()), contains('three credential arguments'));
      });
    }
  });
}
