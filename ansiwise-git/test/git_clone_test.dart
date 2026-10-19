import 'dart:convert';

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
    shell.fails('git -c safe.directory=$path -C $path rev-parse --is-inside-work-tree');
    return shell;
  }

  /// A machine whose checkout stands exactly where the remote, served at [address], publishes the
  /// branch.
  FakeShell standing({String localTip = tip, String address = url}) {
    final FakeShell shell = FakeShell();
    shell
      ..answers('git -c safe.directory=$path -C $path rev-parse --is-inside-work-tree', 'true\n')
      ..answers('git -c safe.directory=$path -C $path remote get-url origin', '$address\n')
      ..answers('git -c safe.directory=$path -C $path rev-parse --abbrev-ref HEAD', '$base\n')
      ..answers('git ls-remote --heads $address $base', '$tip\trefs/heads/$base\n')
      ..answers('git -c safe.directory=$path -C $path rev-parse HEAD', '$localTip\n');
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
          'git -c safe.directory=$path -C $path fetch origin $base',
          'git -c safe.directory=$path -C $path checkout -B $base origin/$base',
        ]),
      );
      expect(shell.ran, isNot(contains('git clone --branch $base $url $path')));
    });

    test(
      'a remote pointing somewhere else is corrected to the address the settings compose',
      () async {
        final FakeShell shell = standing();
        shell.answers(
          'git -c safe.directory=$path -C $path remote get-url origin',
          'https://$host/somebody/else.git\n',
        );
        expect(await step.check(contextOn(shell: shell, files: settings())), isA<Ready>());

        await step.apply(contextOn(shell: shell, files: settings()));
        expect(
          shell.ran,
          contains('git -c safe.directory=$path -C $path remote set-url origin $url'),
        );
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

  group('a working tree that is not clean', () {
    /// What the row asks the checkout about its own working tree.
    const String asking = 'git -c safe.directory=$path -C $path status --porcelain';

    /// A commit that is not the published tip, so the row has the branch to place.
    const String behind = 'f6c1a2d90b7e8f3a4c5d6e7f8a9b0c1d2e3f4a5b';

    test('PLANTED DEFECT: work over an unclean tree is refused, naming what stands there', () async {
      // `checkout -B` carries an uncommitted change that does not collide onto the branch it places,
      // and it lands in whatever commits next. Nothing said so before this refusal.
      final FakeShell shell = standing(localTip: behind)..answers(asking, ' M values.yaml\n');

      final CheckResult result = await step.check(contextOn(shell: shell, files: settings()));
      expect((result as Blocked).reason, contains('values.yaml'));
      expect(shell.ran, isNot(contains('git -c safe.directory=$path -C $path fetch origin $base')));
    });

    test('a reading that could not be taken is refused, not read as a clean tree', () async {
      final FakeShell shell = standing(localTip: behind)
        ..fails(asking, exitCode: 128, stderr: 'fatal: not a git repository');

      final CheckResult result = await step.check(contextOn(shell: shell, files: settings()));
      expect((result as Blocked).reason, contains('could not be read'));
    });

    test('a checkout already on the published tip is not asked at all', () async {
      // A row that would change nothing must not start refusing because somebody left an edit in
      // the tree. The reading is placed after the placement questions precisely for this.
      final FakeShell shell = standing()..answers(asking, ' M values.yaml\n');

      expect(await step.check(contextOn(shell: shell, files: settings())), isA<Satisfied>());
      expect(shell.ran, isNot(contains(asking)));
    });

    test('INNOCENT CASE: a clean tree with work to do is ready, and was really asked', () async {
      final FakeShell shell = standing(localTip: behind);

      expect(await step.check(contextOn(shell: shell, files: settings())), isA<Ready>());
      expect(shell.ran, contains(asking));
    });
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
      // for no elevation of its own is still a root process. Handing over first leaves the account
      // an empty directory and root owning the `.git` inside it, on every machine, from the first
      // install. Nothing meets that while only elevated programs drive the checkout; the first
      // caller that is not root is refused by git outright.
      //
      // The order is asserted here so the next reader cannot quietly put it back.
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
      // What a checkout standing under the wrong owner looks like: the tree is there, on the right
      // branch, at the right tip — and git will not read a word of it.
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
      // would call this machine finished. The shared `standing` fixture cannot serve here: its
      // remote is the settings-based address, so this case would pass for the wrong reason and stay
      // green with the ownership reading taken out.
      final FakeShell shell = FakeShell();
      shell
        ..answers('stat -c %U $path', 'root\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -c safe.directory=$path -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip\trefs/heads/$base\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse HEAD', '$tip\n');

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

    // THE SHAPE A CHECK OF THE OUTER DIRECTORY ALONE ADMITS: the worktree is handed to the
    // operator account and the `.git` inside it still belongs to the account that made it.
    // Such a row reads the OUTER directory, calls the hand-over done, and never applies — so git
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
        ..answers('git -c safe.directory=$path -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -c safe.directory=$path -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip	refs/heads/$base\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse HEAD', '$tip\n');

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
        ..answers('git -c safe.directory=$path -C $path rev-parse --is-inside-work-tree', 'true\n')
        ..answers('git -c safe.directory=$path -C $path remote get-url origin', '$openUrl\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse --abbrev-ref HEAD', '$base\n')
        ..answers('git ls-remote --heads $openUrl $base', '$tip\trefs/heads/$base\n')
        ..answers('git -c safe.directory=$path -C $path rev-parse HEAD', '$tip\n');

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

  // ---------------------------------------------------------------------------------------------
  // A REPOSITORY WHOSE HOST AND WHOSE CREDENTIAL ARE ANSWERS. A program file ships to every
  // installation and so names no installation's host; and the first clone of a machine precedes any
  // settings file that could hold the credential, so the run is given it. The two travel like the
  // origin and the branch already do: the row names the answer, the run holds the value.
  // ---------------------------------------------------------------------------------------------
  group('a repository whose host and credential are answers', () {
    const String hostAnswer = 'platform_host';
    const String originAnswer = 'platform_repo';
    const String credentialAnswer = 'platform_token';
    const String forgeHost = 'forge.example.com';
    const String forgeOwnerName = 'acme/acme-platform';
    const String forgeUrl = 'https://$forgeHost/$forgeOwnerName.git';

    const GitClone answered = GitClone(
      repository: path,
      hostAnswer: hostAnswer,
      branch: base,
      originAnswer: originAnswer,
      credentialAnswer: credentialAnswer,
      credentialUser: 'reader',
      runAnswer: null,
    );

    final String authorization = base64Encode(utf8.encode('reader:$credential'));
    const Map<String, Object> everything = <String, Object>{
      hostAnswer: forgeHost,
      originAnswer: forgeOwnerName,
      credentialAnswer: credential,
    };

    /// A run holding [held], against [shell].
    StepContext holding(Map<String, Object> held, {Shell? shell}) =>
        contextOn(shell: shell ?? bare(), files: FakeFiles(), name: null, also: held);

    Map<String, Object> without(String answer) => <String, Object>{...everything}..remove(answer);

    /// The first command of [shell] that passed git [verb].
    Command commandOf(FakeShell shell, String verb) =>
        shell.commands.firstWhere((Command each) => each.arguments.contains(verb));

    test(
      'INNOCENT CASE: the address is composed from the answered host and the recorded owner/name',
      () async {
        final FakeShell shell = bare();
        await answered.apply(holding(everything, shell: shell));

        expect(shell.ran, contains('git clone --branch $base $forgeUrl $path'));
      },
    );

    test('INNOCENT CASE: the credential stands in the environment of the clone, keyed on the '
        'answered host', () async {
      final FakeShell shell = bare();
      await answered.apply(holding(everything, shell: shell));

      expect(commandOf(shell, 'clone').environment, <String, String>{
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'http.https://$forgeHost/.extraHeader',
        'GIT_CONFIG_VALUE_0': 'Authorization: Basic $authorization',
      });
    });

    test('INNOCENT CASE: a checkout on another address is moved to the plain one, and only the '
        'commands that reach the network carry the credential', () async {
      final FakeShell shell = standing(
        localTip: 'f6c1a2d90b7e8f3a4c5d6e7f8a9b0c1d2e3f4a5b',
        address: 'https://$forgeHost/somebody/else.git',
      );
      await answered.apply(holding(everything, shell: shell));

      expect(
        shell.ran,
        contains('git -c safe.directory=$path -C $path remote set-url origin $forgeUrl'),
      );
      for (final Command command in shell.commands) {
        final bool reachesNetwork = command.arguments.contains('fetch');
        expect(
          command.environment.containsKey('GIT_CONFIG_VALUE_0'),
          reachesNetwork,
          reason: '${command.argv.join(' ')} reaches the network: $reachesNetwork',
        );
      }
    });

    test(
      'INNOCENT CASE: a checkout on the published tip is asked with the credential and finished',
      () async {
        final FakeShell shell = standing(address: forgeUrl);
        final CheckResult result = await answered.check(holding(everything, shell: shell));

        expect(result, isA<Satisfied>());
        expect(
          commandOf(shell, 'ls-remote').environment['GIT_CONFIG_KEY_0'],
          'http.https://$forgeHost/.extraHeader',
        );
      },
    );

    test(
      'INNOCENT CASE: the credential is in no argument, in no plan and in no remote address',
      () async {
        final FakeShell shell = bare();
        final StepContext context = holding(everything, shell: shell);
        final StepPlan plan = await answered.plan(context);
        await answered.apply(context);

        for (final String command in <String>[...shell.ran, ...(plan as ArgvPlan).argv]) {
          expect(command, isNot(contains(credential)));
          expect(command, isNot(contains(authorization)));
        }
      },
    );

    test('INNOCENT CASE: the record of the run does not contain the credential', () async {
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());
      await answered.apply(holding(everything, shell: recording(bare(), recorder)));

      final List<String> record = <String>[
        for (final CommandStarted started in recorder.only<CommandStarted>()) ...started.argv,
        ...recorder.output,
        ...recorder.logLines,
      ];
      expect(record, isNotEmpty, reason: 'a record that holds nothing proves nothing about it');
      for (final String line in record) {
        expect(line, isNot(contains(credential)));
        expect(line, isNot(contains(authorization)));
      }
    });

    test(
      'INNOCENT CASE: a literal host with an answered credential keys the header on that host',
      () async {
        const GitClone literalHost = GitClone(
          repository: path,
          host: host,
          branch: base,
          originAnswer: originAnswer,
          credentialAnswer: credentialAnswer,
          credentialUser: 'reader',
          runAnswer: null,
        );
        final FakeShell shell = bare();
        await literalHost.apply(holding(everything, shell: shell));

        expect(
          commandOf(shell, 'clone').environment['GIT_CONFIG_KEY_0'],
          'http.https://$host/.extraHeader',
        );
        expect(
          shell.ran,
          contains('git clone --branch $base https://$host/$forgeOwnerName.git $path'),
        );
      },
    );

    test('INNOCENT CASE: an answered host with the credential read from a file keys the header on '
        'the answered host', () async {
      const GitClone fromFile = GitClone(
        repository: path,
        hostAnswer: hostAnswer,
        branch: base,
        originFile: settingsFile,
        originKey: settingsKey,
        credentialFile: credentialFile,
        credentialKey: credentialKey,
        credentialUser: 'reader',
        runAnswer: null,
      );
      final FakeShell shell = bare();
      await fromFile.apply(
        contextOn(shell: shell, files: settings(), name: forgeHost, answerName: hostAnswer),
      );

      expect(
        shell.ran,
        contains('git clone --branch $base https://$forgeHost/$ownerName.git $path'),
      );
      expect(
        commandOf(shell, 'clone').environment['GIT_CONFIG_KEY_0'],
        'http.https://$forgeHost/.extraHeader',
      );
    });

    test('PLANTED DEFECT: a run holding no value under host_answer is refused, naming the answer, '
        'and nothing is asked', () async {
      final FakeShell shell = bare();
      final CheckResult result = await answered.check(holding(without(hostAnswer), shell: shell));

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(hostAnswer));
      expect(shell.ran, isEmpty);

      await expectLater(
        answered.apply(holding(without(hostAnswer), shell: shell)),
        throwsA(isA<StateError>()),
      );
      expect(shell.ran, isEmpty, reason: 'a run that does not know the host clones from nowhere');
    });

    for (final (String why, Map<String, Object> held) in <(String, Map<String, Object>)>[
      ('holding none', without(credentialAnswer)),
      ('holding an empty one', <String, Object>{...everything, credentialAnswer: ''}),
    ]) {
      test('PLANTED DEFECT: a run $why under credential_answer is refused, naming the answer and '
          'no file, and nothing is asked', () async {
        final FakeShell shell = bare();
        final CheckResult result = await answered.check(holding(held, shell: shell));

        expect(result, isA<Blocked>());
        expect(
          (result as Blocked).reason,
          allOf(contains(credentialAnswer), isNot(contains('.dev'))),
        );
        expect(shell.ran, isEmpty);
      });
    }

    test('PLANTED DEFECT: a clone refused by the remote names the answer the credential came from, '
        'not a file', () async {
      final FakeShell shell = standing(address: forgeUrl)
        ..fails('git ls-remote --heads $forgeUrl $base', stderr: 'fatal: Authentication failed');
      final CheckResult result = await answered.check(holding(everything, shell: shell));

      expect(result, isA<Blocked>());
      expect(
        (result as Blocked).reason,
        allOf(contains(credentialAnswer), isNot(contains('null')), isNot(contains(credential))),
      );
    });

    test('PLANTED DEFECT: a clone git refuses is reported without the credential and without the '
        'variables it rode in', () async {
      final FakeShell shell = bare()
        ..fails(
          'git clone --branch $base $forgeUrl $path',
          exitCode: 128,
          stderr: 'fatal: Authentication failed',
        );

      await expectLater(
        answered.apply(holding(everything, shell: shell)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed failure) => failure.message,
            'message',
            allOf(
              contains('Authentication failed'),
              contains(forgeUrl),
              isNot(contains(credential)),
              isNot(contains(authorization)),
              isNot(contains('GIT_CONFIG')),
            ),
          ),
        ),
      );
    });

    // ansiwise-core hands root an elevated command's variables through `sudo env NAME=value`, which
    // writes them into sudo's own arguments: in the process listing while git runs, and at rest in
    // the journal's line for the command. FakeShell keeps elevation as a flag and never builds that
    // argument list, so what is measured is that no command carrying the credential is elevated.
    test('PLANTED DEFECT: an elevated row holding the credential is refused, and no command of it '
        'reaches the machine', () async {
      const GitClone elevatedRow = GitClone(
        repository: path,
        hostAnswer: hostAnswer,
        branch: base,
        originAnswer: originAnswer,
        credentialAnswer: credentialAnswer,
        credentialUser: 'reader',
        runAnswer: null,
        elevated: true,
      );
      final FakeShell shell = bare();

      await expectLater(
        elevatedRow.apply(holding(everything, shell: shell)),
        throwsA(isA<StateError>()),
      );
      expect(shell.commands, isEmpty);
    });

    test('INNOCENT CASE: an elevated row with no credential still runs elevated, and sudo is given '
        'no variables for it', () async {
      const GitClone elevatedOpen = GitClone(
        repository: path,
        host: host,
        branch: base,
        originAnswer: originAnswer,
        runAnswer: null,
        elevated: true,
      );
      final FakeShell shell = bare();
      await elevatedOpen.apply(holding(everything, shell: shell));

      final List<Command> elevated = shell.commands.where((Command each) => each.elevated).toList();
      expect(elevated, isNotEmpty, reason: 'a row that never ran elevated proves nothing about it');
      for (final Command command in elevated) {
        expect(elevatedArgumentsFor(command), isNot(contains('env')));
      }
    });
  });

  group('COUNTER-PROBE: a row whose own shape is wrong is refused before a machine is asked', () {
    /// The row as it would stand with [named] given and everything else left off.
    GitClone rowWith({
      String? hostName = host,
      String? hostAnswer,
      String? originFile,
      String? originKey,
      String? originAnswer,
      String? credentialAnswer,
      String? credentialFile,
      String? credentialKey,
      String? credentialUser,
      bool elevated = false,
    }) => GitClone(
      repository: path,
      host: hostName,
      hostAnswer: hostAnswer,
      branch: base,
      originFile: originFile,
      originKey: originKey,
      originAnswer: originAnswer,
      credentialAnswer: credentialAnswer,
      credentialFile: credentialFile,
      credentialKey: credentialKey,
      credentialUser: credentialUser,
      runAnswer: null,
      elevated: elevated,
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

    test(
      'PLANTED DEFECT: both host and host_answer — two answers to which host serves it',
      () async {
        expect(
          await refusalOf(rowWith(hostAnswer: 'platform_host', originAnswer: 'platform_repo')),
          allOf(contains('host'), contains('host_answer'), contains('both')),
        );
      },
    );

    test('PLANTED DEFECT: neither host nor host_answer — nothing says who serves it', () async {
      final String refusal = await refusalOf(
        rowWith(hostName: null, originAnswer: 'platform_repo'),
      );
      expect(refusal, allOf(contains('host'), contains('host_answer'), contains('neither')));
    });

    test('PLANTED DEFECT: credential_answer beside the credential file pair — two answers to where '
        'the credential comes from', () async {
      expect(
        await refusalOf(
          rowWith(
            originAnswer: 'platform_repo',
            credentialAnswer: 'platform_token',
            credentialFile: credentialFile,
            credentialKey: credentialKey,
            credentialUser: 'reader',
          ),
        ),
        allOf(contains('credential_answer'), contains('credential_file'), contains('both')),
      );
    });

    test(
      'PLANTED DEFECT: credential_answer beside a lone credential_key is the same two answers',
      () async {
        expect(
          await refusalOf(
            rowWith(
              originAnswer: 'platform_repo',
              credentialAnswer: 'platform_token',
              credentialKey: credentialKey,
              credentialUser: 'reader',
            ),
          ),
          allOf(
            contains('credential_answer'),
            contains('credential_key'),
            isNot(contains('credential_file')),
            contains('both'),
          ),
        );
      },
    );

    test('PLANTED DEFECT: credential_answer beside elevated — an elevated command\'s variables are '
        'written into the arguments of sudo', () async {
      expect(
        await refusalOf(
          rowWith(
            originAnswer: 'platform_repo',
            credentialAnswer: 'platform_token',
            credentialUser: 'reader',
            elevated: true,
          ),
        ),
        allOf(contains('credential_answer'), contains('elevated'), contains('sudo')),
      );
    });

    test('PLANTED DEFECT: the credential_file group beside elevated is refused in check, plan and '
        'apply, and no command reaches the machine', () async {
      final GitClone row = rowWith(
        originAnswer: 'platform_repo',
        credentialFile: '/etc/acme/secrets.yaml',
        credentialKey: 'token',
        credentialUser: 'reader',
        elevated: true,
      );
      expect(
        await refusalOf(row),
        allOf(contains('credential_file'), contains('elevated'), contains('sudo')),
      );

      final FakeShell shell = bare();
      final StepContext context = contextOn(
        shell: shell,
        files: settings(),
        name: 'acme/whatever',
        answerName: 'platform_repo',
      );
      final StepPlan plan = await row.plan(context);
      expect(plan, isA<NothingPlan>());
      expect(plan.summary, allOf(contains('credential_file'), contains('elevated')));
      await expectLater(row.apply(context), throwsA(isA<StateError>()));
      expect(shell.commands, isEmpty);
    });

    test('PLANTED DEFECT: a lone credential_user beside elevated is refused', () async {
      expect(
        await refusalOf(
          rowWith(originAnswer: 'platform_repo', credentialUser: 'reader', elevated: true),
        ),
        allOf(contains('credential_user'), contains('elevated')),
      );
    });

    test('PLANTED DEFECT: credential_answer without credential_user — a credential nothing can '
        'present', () async {
      expect(
        await refusalOf(rowWith(originAnswer: 'platform_repo', credentialAnswer: 'platform_token')),
        allOf(contains('credential_answer'), contains('credential_user')),
      );
    });

    test('INNOCENT CASE: credential_answer with credential_user is a whole row', () async {
      final FakeShell shell = bare();
      final CheckResult result =
          await rowWith(
            originAnswer: 'platform_repo',
            credentialAnswer: 'platform_token',
            credentialUser: 'reader',
          ).check(
            contextOn(
              shell: shell,
              name: 'acme/whatever',
              answerName: 'platform_repo',
              also: const <String, Object>{'platform_token': credential},
            ),
          );
      expect(result, isA<Ready>());
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

  group('a checkout git would call dubious', () {
    // WHAT GIT DOES, IN ITS OWN WORDS. A repository owned by another account is refused before any
    // question asked of it is answered, and the refusal arrives on the same channel an answer would
    // — so a caller that does not say the checkout is trusted reads "there is no checkout here"
    // and clones onto the one that is standing. Measured on a real machine: an elevated row met a
    // checkout belonging to the operating account, and the clone that followed died with
    // "destination path already exists and is not an empty directory".
    //
    // The fixture is the machine as it really answered: the guarded form works, the bare form is
    // refused. If the step ever stops saying safe.directory, it meets the refusal instead of the
    // answer and every one of these goes red.
    FakeShell refusingTheUnguarded({String localTip = tip}) {
      final FakeShell shell = standing(localTip: localTip);
      for (final String bare in <String>[
        'git -C $path rev-parse --is-inside-work-tree',
        'git -C $path remote get-url origin',
        'git -C $path rev-parse --abbrev-ref HEAD',
        'git -C $path rev-parse HEAD',
      ]) {
        shell.fails(
          bare,
          exitCode: 128,
          stderr: "fatal: detected dubious ownership in repository at '$path'",
        );
      }
      return shell;
    }

    test('is read, not mistaken for absent — a checkout on the tip is finished', () async {
      final FakeShell shell = refusingTheUnguarded();

      expect(
        await step.check(contextOn(shell: shell, files: settings())),
        isA<Satisfied>(),
        reason:
            'a checkout standing on the published tip is finished. Reading git\'s ownership '
            'refusal as an answer about the checkout makes this Ready, and the apply then clones '
            'onto a directory that is not empty',
      );
      expect(
        shell.ran,
        isNot(contains('git clone --branch $base $url $path')),
        reason: 'nothing is cloned over a checkout that is already standing where it should',
      );
    });

    test(
      'is still corrected where it has fallen behind, and the refusal never decides it',
      () async {
        final FakeShell shell = refusingTheUnguarded(
          localTip: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
        );

        expect(await step.check(contextOn(shell: shell, files: settings())), isA<Ready>());
      },
    );

    test('every command it puts to the checkout says the checkout is trusted', () async {
      final FakeShell shell = standing();
      await step.check(contextOn(shell: shell, files: settings()));

      final Iterable<String> againstTheCheckout = shell.ran.where(
        (String argv) => argv.contains('-C $path'),
      );
      expect(againstTheCheckout, isNotEmpty);
      for (final String argv in againstTheCheckout) {
        expect(
          argv,
          startsWith('git -c safe.directory=$path '),
          reason: 'git refuses a repository owned by another account before it answers anything',
        );
      }
    });

    test(
      'INNOCENT CASE: a command that reaches the network says nothing about a local path',
      () async {
        final FakeShell shell = standing();
        await step.check(contextOn(shell: shell, files: settings()));

        expect(
          shell.ran,
          contains('git ls-remote --heads $url $base'),
          reason:
              'ls-remote asks a remote and meets no owner at all, so a statement about a directory '
              'in front of it would stand in the record saying nothing',
        );
      },
    );
  });
}
