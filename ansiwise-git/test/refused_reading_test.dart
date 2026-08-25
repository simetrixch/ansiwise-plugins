import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// A reading that was REFUSED is not an answer, and these steps decide on readings that can be.
///
/// **The shape.** Each step asks a tool a question and acts on what comes back. `git rev-parse
/// --abbrev-ref HEAD` names the branch a checkout stands on; `stat -c %U` names the account a
/// directory belongs to; `git ls-remote` names what a remote publishes; `git ls-files` names what a
/// checkout tracks. Every one of them can also answer nothing at all — the checkout is not one, the
/// tool is missing, a directory above the path may not be entered, the remote was never reached —
/// and a step that turns that silence into a value decides on a measurement nobody took.
///
/// **AN EMPTY ANSWER AND A NON-ZERO EXIT ARE DIFFERENT THINGS, and the git plumbing here is careful
/// about which is which.** `ls-remote` writes nothing at exit zero for a name the remote does not
/// publish, and `ls-files` writes nothing at exit zero for a pathspec the index matches nothing
/// against. Those empty answers keep their meaning throughout; what changed is that a non-zero exit
/// no longer joins them.
///
/// **Why it is measured here rather than in each step's own file.** Both steps carry the property,
/// the property is one sentence, and a case written twice in two files is a case that stops agreeing
/// with itself. The steps' own files measure what each of them does; this one measures what neither
/// may do.
///
/// **Every row here is built through [gitRegistry] from the KEYS a shipped program writes, and never
/// by calling a constructor.** Two things ride on that. A value reaches a step through its factory,
/// so a factory that dropped one would be invisible to a test that put the field in by hand. And the
/// row shape is the one that ships: `elevated` is left OUT of both rows below, exactly as the
/// programs leave it out, so what is measured is the step as an installation really runs it rather
/// than a shape invented to make the case convenient.
void main() {
  /// The literal a source tree carries where one installation carries a value of its own.
  const String standIn = 'master';

  /// What this installation answers, and the branch its checkout stands on once one is cut.
  const String fqdn = 'm1.example.com';

  /// The directory of the checkout the stamping row limits its search to.
  const String searched = 'rendered';

  /// One file of that directory, carrying a line the stamp would rewrite.
  const String stamped = '$searched/apps/root-app.yaml';

  /// The stamping row, with the keys a branch program writes after its defaults are merged in.
  ///
  /// `elevated` is absent because no program writes it, and that absence is the whole subject: the
  /// reading below is taken as the account the run started as, and it is the one that can be
  /// refused.
  Step stampingRow() => gitRegistry
      .step(const StepName('stamp_placeholder_in_tracked_files'))!
      .create(
        const Arguments(<String, Object>{
          'repository': repository,
          'refuse_on_branch': standIn,
          'placeholder': standIn,
          'value_answer': 'fqdn',
          'keep_marker': 'set-domain:keep',
          'tree': searched,
          'keys': <String>['revision', 'targetRevision'],
          'excluded_segments': <String>['docs', 'templates'],
          'excluded_names': <String>[],
          'script_suffixes': <String>['.sh', '.ps1'],
        }),
      );

  /// The content search of the stamping row, as the step composes it.
  const String search =
      'git -C $repository grep --full-name --files-with-matches --fixed-strings -e $standIn '
      '-- $searched';

  /// The reading the whole refusal turns on.
  const String readHead = 'git -C $repository rev-parse --abbrev-ref HEAD';

  /// A checkout whose files carry the literal, and whose search finds the one file that does.
  FakeFiles carryingTheLiteral() =>
      FakeFiles(<String, String>{'$repository/$stamped': 'targetRevision: $standIn\n'});

  /// What the checkout tracks under the tree the row names, which is what the guard before the
  /// search asks and the same index the search itself is matched against.
  const String listTracked = 'git -C $repository ls-files -- $searched';

  /// A machine that answers the search and answers [readHead] with [head].
  FakeShell answeringHead(String head) => FakeShell()
    ..answers(readHead, '$head\n')
    ..answers(listTracked, '$stamped\n')
    ..answers(search, '$stamped\n');

  /// A machine that answers the search and REFUSES [readHead], the way git refuses it.
  ///
  /// Exit code 128 with the tool's own sentence, which is what a path that is no checkout, a git
  /// that is not installed and a directory the run may not enter all come back as.
  FakeShell refusingHead() => FakeShell()
    ..fails(
      readHead,
      exitCode: 128,
      stderr: 'fatal: not a git repository (or any of the parent directories): .git',
    )
    ..answers(search, '$stamped\n');

  StepContext stamping(FakeShell shell, FakeFiles files) =>
      contextOn(shell: shell, files: files, name: fqdn, answerName: 'fqdn');

  group('the branch a stamp refuses to run on', () {
    test('THE PLANTED DEFECT: a HEAD that could not be read REFUSES the stamp', () async {
      // The whole of it. The row names the branch every installation is cut from and refuses to
      // stamp it; a reading that answered nothing is not that branch and is not another one either,
      // and taken as a name it is neither — so the guard passed and the row wrote one installation's
      // own values into the source every other installation is cut from.
      final FakeFiles files = carryingTheLiteral();
      final FakeShell shell = refusingHead();

      final CheckResult answer = await stampingRow().check(stamping(shell, files));

      expect(answer, isA<Blocked>(), reason: answer is Blocked ? answer.reason : '$answer');
      expect(
        files.written,
        isEmpty,
        reason: 'a row that could not read the branch has written nothing',
      );
      expect(
        shell.ran,
        isNot(contains(search)),
        reason: 'it stopped at the reading rather than working out what it would stamp',
      );
    });

    test(
      'the same machine, the same row: a HEAD that ANSWERS the refused branch refuses',
      () async {
        // The guard that already worked, kept beside the one that did not. Without it a red result
        // above could mean this row refuses every machine.
        final CheckResult answer = await stampingRow().check(
          stamping(answeringHead(standIn), carryingTheLiteral()),
        );

        expect(answer, isA<Blocked>());
      },
    );

    test('THE INNOCENT CASE: a HEAD that answers another branch is stamped', () async {
      // The only difference from the planted case is that the reading answered. Same row, same
      // files, same search, same content — and the step goes on and rewrites the line.
      final FakeFiles files = carryingTheLiteral();
      final StepContext context = stamping(answeringHead(fqdn), files);
      final Step row = stampingRow();

      expect(await row.check(context), isA<Ready>());
      await row.apply(context);

      expect(files.contents['$repository/$stamped'], contains('targetRevision: $fqdn'));
    });

    test(
      'THE INNOCENT CASE: a HEAD that answers, over a tree already stamped, is nothing to do',
      () async {
        // The other green answer this refusal must not swallow: the reading answered, the checkout
        // really tracks the tree, the search found nothing left in it, and that is a measurement
        // rather than a silence.
        final FakeShell shell = FakeShell()
          ..answers(readHead, '$fqdn\n')
          ..answers(listTracked, '$stamped\n')
          ..fails(search);

        expect(
          await stampingRow().check(
            stamping(
              shell,
              FakeFiles(<String, String>{'$repository/$stamped': 'targetRevision: $fqdn\n'}),
            ),
          ),
          isA<Satisfied>(),
        );
      },
    );
  });

  group('the account a checkout belongs to', () {
    /// Where the checkout the cloning row makes stands.
    const String checkout = '/srv/programs-checkout';

    /// The account the row hands the checkout to, as this run answers it.
    const String account = 'operator';

    /// The reading that decides whether the hand-over has to happen.
    const String readOwner = 'stat -c %U $checkout';

    /// The cloning row, with the keys the program that makes a first checkout writes.
    ///
    /// `elevated` is absent here too, and for a reason of its own: the flag says whether the
    /// checkout and the settings files are root's to read, and every git command of this row is run
    /// at it. A checkout that has just been handed to another account is one git refuses to root, so
    /// this row cannot grant it — which is why the ownership reading below is taken as root on its
    /// own, like the two commands that perform the hand-over.
    Step cloningRow() => gitRegistry
        .step(const StepName('git_clone'))!
        .create(
          const Arguments(<String, Object>{
            'repository': checkout,
            'host': 'code.example.com',
            'branch': base,
            'origin_answer': 'platform_repo',
            'owner_answer': 'operator_user',
          }),
        );

    StepContext cloning(FakeShell shell, FakeFiles files) => contextOn(
      shell: shell,
      files: files,
      name: 'acme/acme-platform',
      answerName: 'platform_repo',
      also: const <String, Object>{'operator_user': account},
    );

    /// A machine that refuses [readOwner], the way stat refuses a path under a directory only root
    /// may enter.
    FakeShell refusingOwner() => FakeShell()
      ..fails(readOwner, stderr: "stat: cannot statx '$checkout': Permission denied")
      ..answers('git -C $checkout rev-parse --is-inside-work-tree', 'true\n');

    test('THE PLANTED DEFECT: an owner that could not be read over a checkout that IS there '
        'REFUSES', () async {
      // Read as a name, the refusal came back as "nobody else owns it" — so the row went on to ask
      // git questions of a checkout git answers nothing about, and skipped the hand-over that is the
      // only thing making those questions answerable.
      final FakeShell shell = refusingOwner();
      final FakeFiles files = FakeFiles()..directories.add(checkout);

      final CheckResult answer = await cloningRow().check(cloning(shell, files));

      expect(answer, isA<Blocked>(), reason: answer is Blocked ? answer.reason : '$answer');
      expect(
        shell.ran.where((String each) => each.startsWith('git ')),
        isEmpty,
        reason: 'git is asked nothing about a checkout whose owner is unknown',
      );
    });

    test(
      'THE INNOCENT CASE: a path that is NOT there has no owner to read and is cloned',
      () async {
        // The ordinary first run, and the case a refusal must not swallow: there is nothing to hand
        // over because there is nothing there, and the clone makes it.
        final FakeShell shell = FakeShell()
          ..fails(readOwner, stderr: "stat: cannot statx '$checkout': No such file or directory")
          ..fails('git -C $checkout rev-parse --is-inside-work-tree');

        expect(await cloningRow().check(cloning(shell, FakeFiles())), isA<Ready>());
      },
    );

    test('THE INNOCENT CASE: an owner that ANSWERS another account is handed over', () async {
      final FakeShell shell = FakeShell()..answers(readOwner, 'root\n');

      expect(
        await cloningRow().check(cloning(shell, FakeFiles()..directories.add(checkout))),
        isA<Ready>(),
      );
    });

    test(
      'THE INNOCENT CASE: an owner that ANSWERS this account is asked the git questions',
      () async {
        // The reading answered, it named the account the row hands the checkout to, and there is
        // nothing to hand over — so the row goes on and measures the checkout itself.
        final FakeShell shell = FakeShell()
          ..answers(readOwner, '$account\n')
          ..fails('git -C $checkout rev-parse --is-inside-work-tree');

        expect(
          await cloningRow().check(cloning(shell, FakeFiles()..directories.add(checkout))),
          isA<Ready>(),
        );
        expect(shell.ran, contains('git -C $checkout rev-parse --is-inside-work-tree'));
      },
    );
  });

  group('a remote that could not be reached is not a remote that publishes nothing', () {
    const String tag = 'v1.2.3';
    const String commit = '0f9fef51a0e1e0b6c9e21c1f0a0b0c0d0e0f0a0b';

    /// The tagging row of a release program: the checkout as text, the tag, and the remote.
    Step taggingRow() => gitRegistry
        .step(const StepName('git_tag'))!
        .create(
          const Arguments(<String, Object>{
            'repository': repository,
            'tag': tag,
            'ref': 'HEAD',
            'message': 'what this run released',
            'remote': remote,
          }),
        );

    /// What the remote is asked about the tag, as the step composes it.
    const String askRemote = 'git -C $repository ls-remote --tags $remote refs/tags/$tag*';

    /// A checkout that carries the commit and answers every local question about the tag.
    FakeShell taggableCheckout() => FakeShell()
      ..answers('git check-ref-format refs/tags/$tag', '')
      ..answers('git -C $repository rev-parse --quiet --verify HEAD^{commit}', '$commit\n')
      ..fails('git -C $repository rev-parse --quiet --verify refs/tags/$tag^{commit}');

    test('THE PLANTED DEFECT: an undo leaves a tag it could not read alone', () async {
      // capture answers "the tag was already there, here or on the remote", and its false half is
      // what runs `push --delete`. Answered false out of a refused ls-remote, an undo deletes a tag
      // somebody else published - against the doc that says exactly that is not this run's to do.
      final FakeShell shell = taggableCheckout()
        ..fails(askRemote, exitCode: 128, stderr: 'fatal: Could not read from remote repository.');
      final ReversibleStep<Object?> step = taggingRow() as ReversibleStep<Object?>;
      final StepContext context = contextOn(shell: shell, files: FakeFiles());

      final Object? captured = await step.capture(context);
      await step.undo(context, captured);

      expect(captured, isTrue, reason: 'a reading nobody took must not read as "it was not there"');
      expect(
        shell.ran,
        isNot(contains('git -C $repository push --delete $remote $tag')),
        reason: 'the undo deleted a tag it never measured',
      );
    });

    test('THE PLANTED DEFECT: the check refuses rather than pushing over it', () async {
      final CheckResult answer = await taggingRow().check(
        contextOn(
          shell: taggableCheckout()
            ..fails(
              askRemote,
              exitCode: 128,
              stderr: 'fatal: Could not read from remote repository.',
            ),
          files: FakeFiles(),
        ),
      );

      expect(answer, isA<Blocked>(), reason: '$answer');
    });

    test('THE INNOCENT CASE: a remote that answers and carries no such tag is tagged', () async {
      // `ls-remote` writes nothing at exit zero for a pattern it matches nothing against, and that
      // empty answer keeps meaning a remote without the tag.
      final CheckResult answer = await taggingRow().check(
        contextOn(shell: taggableCheckout()..answers(askRemote, ''), files: FakeFiles()),
      );

      expect(answer, isA<Ready>(), reason: answer is Blocked ? answer.reason : '$answer');
    });

    test('THE PLANTED DEFECT: a push proves nothing over two readings nobody took', () async {
      // The postcondition of git_push compares what this checkout stands on with what the remote
      // carries. Both answered null where the command failed, null equals null, and the assertion
      // passed - a green verdict from a check that cannot go red, in the one place the step proves
      // it did its work.
      final Step step = gitRegistry
          .step(const StepName('git_push'))!
          .create(const Arguments(<String, Object>{'repository': repository, 'remote': remote}));
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'm1.example.com\n')
        ..answers('git -C $repository push $remote m1.example.com', '')
        ..fails('git -C $repository rev-parse m1.example.com', exitCode: 128)
        ..fails(
          'git -C $repository ls-remote --heads $remote m1.example.com',
          exitCode: 128,
          stderr: 'fatal: Could not read from remote repository.',
        );

      await expectLater(
        step.apply(contextOn(shell: shell, files: FakeFiles())),
        throwsA(isA<CommandFailed>()),
        reason: 'the push reported success over a remote nobody could ask about',
      );
    });

    test('THE INNOCENT CASE: a push whose readings agree is proven', () async {
      final Step step = gitRegistry
          .step(const StepName('git_push'))!
          .create(const Arguments(<String, Object>{'repository': repository, 'remote': remote}));
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'm1.example.com\n')
        ..answers('git -C $repository push $remote m1.example.com', '')
        ..answers('git -C $repository rev-parse m1.example.com', '$commit\n')
        ..answers(
          'git -C $repository ls-remote --heads $remote m1.example.com',
          '$commit\trefs/heads/m1.example.com\n',
        );

      await step.apply(contextOn(shell: shell, files: FakeFiles()));
    });

    test(
      'THE PLANTED DEFECT: a remote that would not answer is not a remote without the ref',
      () async {
        // git_fetch stated a verdict ABOUT THE REMOTE - "the name is wrong, or whatever writes it has
        // not run" - out of a question nobody managed to put to it.
        final Step step = gitRegistry
            .step(const StepName('git_fetch'))!
            .create(
              const Arguments(<String, Object>{
                'repository': repository,
                'remote': remote,
                'branch': 'm1.example.com',
              }),
            );
        final FakeShell shell = FakeShell()
          ..fails(
            'git -C $repository ls-remote $remote refs/heads/m1.example.com',
            exitCode: 128,
            stderr: 'fatal: Could not read from remote repository.',
          );

        final CheckResult answer = await step.check(contextOn(shell: shell, files: FakeFiles()));

        expect(answer, isA<Blocked>());
        expect(
          (answer as Blocked).reason,
          isNot(contains('publishes no branch')),
          reason: 'a remote that would not answer is not a remote without the branch',
        );
      },
    );

    test('THE INNOCENT CASE: a remote that answers and publishes no such branch says so', () async {
      final Step step = gitRegistry
          .step(const StepName('git_fetch'))!
          .create(
            const Arguments(<String, Object>{
              'repository': repository,
              'remote': remote,
              'branch': 'm1.example.com',
            }),
          );
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository ls-remote $remote refs/heads/m1.example.com', '');

      final CheckResult answer = await step.check(contextOn(shell: shell, files: FakeFiles()));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('publishes no branch'));
    });
  });

  group('a tree the checkout does not TRACK is not a tree with nothing in it', () {
    /// The row's search is limited to a tree, and `git grep -- <tree>` matches against the INDEX.
    /// A guard that measured the disk instead asked a different question from the search it
    /// protects: a directory that is on disk and carries nothing tracked, and one .gitignore
    /// covers, both pass a file test and both make the search answer exit one - indistinguishable
    /// from a tracked tree holding no occurrence.
    test('THE PLANTED DEFECT: a tree on disk that carries nothing tracked is refused', () async {
      final FakeShell shell = FakeShell()
        ..answers(readHead, '$fqdn\n')
        ..answers(listTracked, '')
        ..fails(search);
      // The tree IS on disk - the files port finds a file under it - and the index tracks nothing
      // there, which is the state a file test cannot tell from a tracked tree with no occurrence.
      final FakeFiles files = FakeFiles(<String, String>{
        '$repository/$searched/untracked.yaml': 'targetRevision: $standIn\n',
      });

      final CheckResult answer = await stampingRow().check(stamping(shell, files));

      expect(answer, isA<Blocked>(), reason: '$answer');
      expect(
        shell.ran,
        isNot(contains(search)),
        reason: 'it stopped at the guard rather than reading an exit code that says two things',
      );
    });

    test('THE INNOCENT CASE: a tree the checkout TRACKS and that carries no occurrence', () async {
      final FakeShell shell = FakeShell()
        ..answers(readHead, '$fqdn\n')
        ..answers(listTracked, '$stamped\n')
        ..fails(search);
      final FakeFiles files = FakeFiles(<String, String>{
        '$repository/$stamped': 'targetRevision: $fqdn\n',
      });

      expect(await stampingRow().check(stamping(shell, files)), isA<Satisfied>());
    });
  });
}
