import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The two rows of one stamp that turn a copy of a shared source tree into one installation.
///
/// One capability, two rows: one replaces a stand-in wherever it stands, and the other replaces a
/// common word only where a named key carries it. Both are asserted here against the same class,
/// which is what says the one class still does both jobs.
///
/// Everything asserted here was found on a real tree. A stamp that rewrote a script turned that
/// script's own guard into a refusal of the very domain it was installed for; a stamp that rewrote a
/// whole line rewrote the word inside a trailing comment; a stamp that tested every tracked file
/// before narrowing the set took eight and a half seconds per call.
void main() {
  const String repository = '/srv/checkout';
  const String fqdn = 'm1.example.com';

  /// The branch a checkout of the shared source stands on, which neither row may stamp.
  const String sourceBranch = 'master';

  /// The stand-in the shared source carries where one installation carries its own domain.
  ///
  /// Written out here rather than read off the class under test: a test that takes its input from
  /// the subject asserts that the subject agrees with itself, which is true however wrong both are.
  const String standIn = 'example.invalid';

  /// The exclusion lists, exactly as the program's defaults block states them.
  const StampSelection rule = StampSelection(
    excludedSegments: <String>['docs', 'templates'],
    excludedNames: <String>['branch-classes.yaml'],
    scriptSuffixes: <String>['.sh', '.ps1'],
  );

  /// The marker the tree being generated writes, as the program's defaults block states it.
  const String keepMarker = 'set-domain:keep';

  /// The revision row: a common word, under one directory, only where a named key carries it.
  const StampPlaceholderInTrackedFiles retarget = StampPlaceholderInTrackedFiles(
    repository: repository,
    refuseOnBranch: sourceBranch,
    placeholder: sourceBranch,
    valueAnswer: 'fqdn',
    keepMarker: keepMarker,
    rule: rule,
    tree: 'rendered',
    keys: <String>['revision', 'targetRevision'],
  );

  /// The domain row of `deploy-branch`: the placeholder, anywhere in the checkout, on no key.
  ///
  /// Neither the tree nor the keys is written here, exactly as the row does not write them: those
  /// two are left OUT rather than stated as empty, which is what "the whole checkout" and "every
  /// occurrence on the line is the value" are.
  const StampPlaceholderInTrackedFiles stamp = StampPlaceholderInTrackedFiles(
    repository: repository,
    refuseOnBranch: sourceBranch,
    placeholder: standIn,
    valueAnswer: 'fqdn',
    keepMarker: keepMarker,
    rule: rule,
  );

  /// The domain this installation answers on, which both stamps read out of the run by name.
  const Arguments answers = Arguments(<String, Object>{'fqdn': fqdn});

  StepContext contextOn({required FakeShell shell, required Files files}) => StepContext(
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

  /// A checkout on the installation branch whose content search answers with [carrying].
  FakeShell searching({
    required List<String> carrying,
    String head = fqdn,
    String literal = 'example.invalid',
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

  group('the revision retarget rewrites the value and nothing else', () {
    test('a plain revision becomes this installation\'s branch', () async {
      final FakeFiles files = tree(<String, String>{
        'rendered/dev/apps/root-app.yaml': 'spec:\n  source:\n    targetRevision: master\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/root-app.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      await retarget.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'rendered/dev/apps/root-app.yaml'), contains('targetRevision: $fqdn'));
    });

    test('a YAML anchor survives, and the word in a trailing comment is untouched', () async {
      // The looser expression that rewrote the whole line also rewrote the comment, and left an
      // installation branch explaining itself with a sentence its own code contradicted.
      const String line = 'targetRevision: &branch master # cut from master by the installer';
      final FakeFiles files = tree(<String, String>{'rendered/dev/apps/appset.yaml': '$line\n'});
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/appset.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      await retarget.apply(contextOn(shell: shell, files: files));
      expect(
        read(files, 'rendered/dev/apps/appset.yaml').trim(),
        'targetRevision: &branch $fqdn # cut from master by the installer',
      );
    });

    test('a line carrying the keep marker still reads the sourceBranch', () async {
      // What is marked is material every installation shares — charts read from one place
      // catalog. Retargeted, they would be read from a branch that does not carry them.
      const String content =
          'targetRevision: master\n'
          'targetRevision: master # set-domain:keep\n';
      final FakeFiles files = tree(<String, String>{'rendered/dev/apps/catalog.yaml': content});
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/catalog.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      await retarget.apply(contextOn(shell: shell, files: files));
      final List<String> lines = read(files, 'rendered/dev/apps/catalog.yaml').split('\n');
      expect(lines[0], 'targetRevision: $fqdn');
      expect(lines[1], 'targetRevision: master # set-domain:keep');
    });

    test('the books placeholder is neither stamped here nor marked', () async {
      // The branch those generators need is the branch of the cluster holding the master part, which
      // on a slave is not this branch and is not something this stage knows.
      const String content =
          'revision: master\n'
          'revision: __BOOKS_BRANCH__\n';
      final FakeFiles files = tree(<String, String>{'rendered/dev/apps/books.yaml': content});
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/books.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      await retarget.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'rendered/dev/apps/books.yaml'), contains('revision: __BOOKS_BRANCH__'));
      expect(read(files, 'rendered/dev/apps/books.yaml'), contains('revision: $fqdn'));
    });

    test('a longer branch name that merely begins with the sourceBranch is left alone', () async {
      final FakeFiles files = tree(<String, String>{
        'rendered/dev/apps/other.yaml': 'revision: master-of-record\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/other.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      final StepContext context = contextOn(shell: shell, files: files);
      expect(await retarget.check(context), isA<Satisfied>());
    });

    test('a key that is not a revision is left alone', () async {
      final FakeFiles files = tree(<String, String>{
        'rendered/dev/apps/other.yaml': 'branch: master\nname: master\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/other.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );

      expect(await retarget.check(contextOn(shell: shell, files: files)), isA<Satisfied>());
    });

    test('a second run finds nothing to do, and writes nothing', () async {
      final FakeFiles files = tree(<String, String>{
        'rendered/dev/apps/root-app.yaml': 'targetRevision: master\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/root-app.yaml'],
        literal: sourceBranch,
        within: 'rendered',
      );
      final StepContext context = contextOn(shell: shell, files: files);

      await retarget.apply(context);
      final String once = read(files, 'rendered/dev/apps/root-app.yaml');
      files.written.clear();

      expect(await retarget.check(context), isA<Satisfied>());
      await retarget.apply(context);
      expect(files.written, isEmpty);
      expect(read(files, 'rendered/dev/apps/root-app.yaml'), once);
    });

    test(
      'a chart template naming the sourceBranch is product material and is left alone',
      () async {
        // One file rule for every row of this stamp: what a chart keeps under its own templates/ is
        // shipped to every installation and belongs to none, whatever literal it carries.
        const String content = 'targetRevision: master\n';
        final FakeFiles files = tree(<String, String>{
          'rendered/dev/apps/templates/member.yaml': content,
        });
        final FakeShell shell = searching(
          carrying: <String>['rendered/dev/apps/templates/member.yaml'],
          literal: sourceBranch,
          within: 'rendered',
        );

        expect(await retarget.check(contextOn(shell: shell, files: files)), isA<Satisfied>());
      },
    );

    test('the sourceBranch is refused, whatever it carries', () async {
      final FakeFiles files = tree(<String, String>{
        'rendered/dev/apps/root-app.yaml': 'targetRevision: master\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['rendered/dev/apps/root-app.yaml'],
        head: sourceBranch,
        literal: sourceBranch,
        within: 'rendered',
      );

      final CheckResult answer = await retarget.check(contextOn(shell: shell, files: files));
      expect((answer as Blocked).reason, contains('cut the branch first'));
    });
  });

  group('the domain stamp replaces one literal and recognises nothing', () {
    test('the placeholder becomes this installation\'s domain', () async {
      final FakeFiles files = tree(<String, String>{
        'platform/values-dev.yaml': 'global:\n  domain: example.invalid\n',
      });
      final FakeShell shell = searching(carrying: <String>['platform/values-dev.yaml']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'platform/values-dev.yaml'), contains('domain: $fqdn'));
    });

    test('an illustration is a different literal, so it is never a case to decide', () async {
      // Nothing here recognises a domain. example.com survives because it was never matched, and a
      // stamp that matched "anything domain-shaped" would rewrite it.
      const String content =
          '# reached at idp.example.com once this is stamped\n'
          'domain: example.invalid\n'
          'placeholder: m1.example.com\n';
      final FakeFiles files = tree(<String, String>{'cluster/profile.yaml': content});
      final FakeShell shell = searching(carrying: <String>['cluster/profile.yaml']);

      await stamp.apply(contextOn(shell: shell, files: files));
      final String after = read(files, 'cluster/profile.yaml');
      expect(after, contains('# reached at idp.example.com once this is stamped'));
      expect(after, contains('placeholder: m1.example.com'));
      expect(after, contains('domain: $fqdn'));
    });

    test('a label key whose prefix is domain-shaped is unchanged', () async {
      // A label key is a namespace in the Kubernetes convention: a product identifier nothing
      // resolves and nothing addresses. Renaming one reaches every selector at once.
      const String content =
          'metadata:\n'
          '  labels:\n'
          '    labels.example/tier: "example"\n'
          '    labels.example/workload: "web"\n'
          'domain: example.invalid\n';
      final FakeFiles files = tree(<String, String>{'apps/web/values-dev.yaml': content});
      final FakeShell shell = searching(carrying: <String>['apps/web/values-dev.yaml']);

      await stamp.apply(contextOn(shell: shell, files: files));
      final String after = read(files, 'apps/web/values-dev.yaml');
      expect(after, contains('labels.example/tier: "example"'));
      expect(after, contains('labels.example/workload: "web"'));
      expect(after, contains('domain: $fqdn'));
    });

    test('an extensionless script keeps the placeholder, recognised by its first line', () async {
      // A suffix list alone lets this one through, and the stamp reached into a script again.
      final FakeFiles files = tree(<String, String>{
        'tools/ops/sync-versions': '#!/usr/bin/env bash\nDOMAIN="example.invalid"\n',
      });
      final FakeShell shell = searching(carrying: <String>['tools/ops/sync-versions']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'tools/ops/sync-versions'), contains('example.invalid'));
      expect(files.written, isEmpty);
    });

    test('a script whose own guard names the placeholder is unchanged', () async {
      // Stamped, this guard becomes a refusal of the very domain the installation is for, and the
      // script can never run again on its own branch.
      const String content =
          '#!/usr/bin/env bash\n'
          'if [[ "\${FQDN}" == "example.invalid" ]]; then die "give a real domain"; fi\n';
      final FakeFiles files = tree(<String, String>{'install.sh': content});
      final FakeShell shell = searching(carrying: <String>['install.sh']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'install.sh'), content);
    });

    test('a library whose empty-value test names the placeholder is unchanged', () async {
      const String content =
          'if [ -z "\$DOMAIN_SUFFIX" ]; then DOMAIN_SUFFIX=example.invalid; fi\n';
      final FakeFiles files = tree(<String, String>{'base/lib/cli.sh': content});
      final FakeShell shell = searching(carrying: <String>['base/lib/cli.sh']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(
        read(files, 'base/lib/cli.sh'),
        content,
        reason:
            'this one carries no first line to '
            'recognise it by, and the suffix is what answers',
      );
    });

    test('a PowerShell script is excluded by its suffix, having no first line', () async {
      const String content = 'param([string]\$Domain = "example.invalid")\n';
      final FakeFiles files = tree(<String, String>{'tools/ops/publish.ps1': content});
      final FakeShell shell = searching(carrying: <String>['tools/ops/publish.ps1']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'tools/ops/publish.ps1'), content);
    });

    test('the file that declares this stamp is excluded by name', () async {
      // It states which paths hold installation state, so it quotes the placeholder to explain what
      // is done to it. Rewritten, the one file an operator opens to learn what is never stamped
      // would itself name a real domain.
      const String content = 'never-stamp:\n  - reason: they quote example.invalid to explain it\n';
      final FakeFiles files = tree(<String, String>{'branch-classes.yaml': content});
      final FakeShell shell = searching(carrying: <String>['branch-classes.yaml']);

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'branch-classes.yaml'), content);
    });

    test('documentation and chart templates are unchanged', () async {
      const String doc = 'The sourceBranch carries example.invalid until a branch is cut.\n';
      const String template = 'host: example.invalid\n';
      final FakeFiles files = tree(<String, String>{
        'docs/branching.md': doc,
        'charts/shared/templates/ingress.yaml': template,
        'templates/values.yaml': template,
      });
      final FakeShell shell = searching(
        carrying: <String>[
          'docs/branching.md',
          'charts/shared/templates/ingress.yaml',
          'templates/values.yaml',
        ],
      );

      await stamp.apply(contextOn(shell: shell, files: files));
      expect(read(files, 'docs/branching.md'), doc);
      expect(read(files, 'charts/shared/templates/ingress.yaml'), template);
      expect(read(files, 'templates/values.yaml'), template);
      expect(files.written, isEmpty);
    });

    test('the content search runs first, and no other file is ever opened', () async {
      // Testing the first line of every tracked file instead costs one open per file: that ordering
      // took this from milliseconds to eight and a half seconds per call on Windows.
      final List<String> trace = <String>[];
      final FakeFiles inner = tree(<String, String>{
        'platform/values-dev.yaml': 'domain: example.invalid\n',
        'platform/values-prod.yaml': '#!/usr/bin/env bash\n',
        'apps/web/values-dev.yaml': 'nothing to see\n',
      });
      final FakeShell shell = searching(carrying: <String>['platform/values-dev.yaml']);

      await stamp.apply(
        StepContext(
          shell: _TracingShell(shell, trace),
          files: _TracingFiles(inner, trace),
          http: FakeHttp(),
          clock: FakeClock(),
          entropy: FakeEntropy(),
          log: const _SilentLog(),
          step: const StepName('under_test'),
          arguments: Arguments.none,
          answers: answers,
          facts: Facts.none,
        ),
      );

      final int searched = trace.indexWhere(
        (String e) => e.startsWith('run git -C $repository grep'),
      );
      final int firstRead = trace.indexWhere((String e) => e.startsWith('read'));
      expect(searched, isNot(-1));
      expect(firstRead, greaterThan(searched), reason: 'the search narrows the set first');
      expect(trace.where((String e) => e.startsWith('read')), <String>[
        'read $repository/platform/values-dev.yaml',
      ], reason: 'a file the search did not return is never asked what it is');
    });

    test('a second run finds nothing to do, and writes nothing', () async {
      final FakeFiles files = tree(<String, String>{
        'platform/values-dev.yaml': 'domain: example.invalid\n',
      });
      final FakeShell shell = searching(carrying: <String>['platform/values-dev.yaml']);
      final StepContext context = contextOn(shell: shell, files: files);

      await stamp.apply(context);
      final String once = read(files, 'platform/values-dev.yaml');
      files.written.clear();

      expect(await stamp.check(context), isA<Satisfied>());
      await stamp.apply(context);
      expect(files.written, isEmpty);
      expect(read(files, 'platform/values-dev.yaml'), once);
    });

    test('a tree carrying the placeholder only in excluded files is already stamped', () async {
      final FakeFiles files = tree(<String, String>{
        'install.sh': '#!/bin/sh\necho example.invalid\n',
        'docs/branching.md': 'example.invalid\n',
      });
      final FakeShell shell = searching(carrying: <String>['install.sh', 'docs/branching.md']);

      expect(await stamp.check(contextOn(shell: shell, files: files)), isA<Satisfied>());
    });

    test('a line carrying the keep marker keeps the placeholder too', () async {
      // The marker says the line is product every installation shares. It is read by every row of
      // this stamp, so a marked line is not one the domain row rewrites either.
      const String content =
          'domain: example.invalid\n'
          'domain: example.invalid # set-domain:keep\n';
      final FakeFiles files = tree(<String, String>{'platform/values-dev.yaml': content});
      final FakeShell shell = searching(carrying: <String>['platform/values-dev.yaml']);

      await stamp.apply(contextOn(shell: shell, files: files));
      final List<String> lines = read(files, 'platform/values-dev.yaml').split('\n');
      expect(lines[0], 'domain: $fqdn');
      expect(lines[1], 'domain: example.invalid # set-domain:keep');
    });

    test('the sourceBranch is refused, so no run can put a domain on it', () async {
      final FakeFiles files = tree(<String, String>{
        'platform/values-dev.yaml': 'domain: example.invalid\n',
      });
      final FakeShell shell = searching(
        carrying: <String>['platform/values-dev.yaml'],
        head: sourceBranch,
      );

      final CheckResult answer = await stamp.check(contextOn(shell: shell, files: files));
      expect((answer as Blocked).reason, contains('cut the branch first'));
      expect(read(files, 'platform/values-dev.yaml'), contains('example.invalid'));
    });

    test('a write that quietly did nothing fails the step rather than reporting success', () async {
      // The rule the shell learned the hard way: an in-place rewrite reports success whether or not
      // it matched, so the answer comes from reading the file back.
      final FakeFiles files = tree(<String, String>{
        'platform/values-dev.yaml': 'domain: example.invalid\n',
      });
      final FakeShell shell = searching(carrying: <String>['platform/values-dev.yaml']);
      final StepContext context = contextOn(shell: shell, files: _SwallowingFiles(files));

      await stamp.apply(context);
      expect(
        await stamp.check(context),
        isA<Ready>(),
        reason: 'nothing was written, so the work is still to do and the postcondition says so',
      );
    });
  });
}

/// A file system that answers every read and drops every write.
///
/// The failure it stands for is the one an exit code cannot see: the rewrite ran, returned zero and
/// changed nothing.
final class _SwallowingFiles implements Files {
  const _SwallowingFiles(this.inner);

  final Files inner;

  @override
  Future<bool> exists(String path, {bool elevated = false}) => inner.exists(path);

  @override
  Future<String> read(String path, {bool elevated = false}) => inner.read(path);

  @override
  Future<List<String>> list(String path, {bool elevated = false}) => inner.list(path);

  @override
  Future<void> write(
    String path,
    String content, {
    required int mode,
    bool elevated = false,
  }) async {}

  @override
  Future<void> delete(String path, {bool elevated = false}) async {}

  @override
  Future<void> createDirectory(String path, {required int mode, bool elevated = false}) async {}
}

/// A file system that writes down which files were opened, in order.
final class _TracingFiles implements Files {
  const _TracingFiles(this.inner, this.trace);

  final Files inner;
  final List<String> trace;

  @override
  Future<bool> exists(String path, {bool elevated = false}) => inner.exists(path);

  @override
  Future<String> read(String path, {bool elevated = false}) {
    trace.add('read $path');
    return inner.read(path);
  }

  @override
  Future<List<String>> list(String path, {bool elevated = false}) => inner.list(path);

  @override
  Future<void> write(String path, String content, {required int mode, bool elevated = false}) =>
      inner.write(path, content, mode: mode);

  @override
  Future<void> delete(String path, {bool elevated = false}) => inner.delete(path);

  @override
  Future<void> createDirectory(String path, {required int mode, bool elevated = false}) =>
      inner.createDirectory(path, mode: mode);
}

/// A shell that writes down what it ran into the same trace the file system writes to.
final class _TracingShell implements Shell {
  const _TracingShell(this.inner, this.trace);

  final Shell inner;
  final List<String> trace;

  @override
  Future<CommandResult> run(Command command) {
    trace.add('run ${command.argv.join(' ')}');
    return inner.run(command);
  }
}

final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
