import 'package:ansiwise_core/ansiwise_core.dart';

import 'recorded_value.dart';

/// Makes a checkout able to write to its remote, by putting the credential where git's own store
/// helper reads it and pointing this checkout's helper at that file.
///
/// **This is the step the two steps around it each say is not theirs.** The step that clones stores
/// a remote address with no credential in it, deliberately. The step that pushes says how the
/// machine is allowed to write is arranged before any program runs — "a key, a helper, an agent" —
/// and nothing in this platform ever put one there. So the gate that offers a push and the push
/// itself both ask a remote for a write right that nobody granted, and both are refused with a
/// message about the remote.
///
/// **Why the credential is not written into the remote address.** One that is, is at rest in the
/// checkout's own configuration for as long as the checkout stands, and `git remote -v` prints it
/// to anybody who can read the tree. The store file this step writes is one file inside the git
/// directory, at mode `0600`, and git is the only thing that reads it.
///
/// **What it costs.** The credential IS at rest on this machine, in that
/// one owner-only file, for as long as the checkout stands, and a rotated credential reaches it
/// only by this row running again. It is a second copy of a value that is already at rest on the
/// same machine, at the same mode, in the settings file an earlier program of this installation
/// wrote — which is what makes the second copy a cost worth paying rather than a new exposure.
///
/// **The file lives under the git directory and never in the working tree.** So it is never a
/// tracked path, it never makes the tree dirty before a branch is cut, and it goes when the
/// checkout goes.
///
/// **The credential comes from an ANSWER or from a FILE, and the row says which.** A run that is
/// making an installation for the first time holds it as an answer and no file of the machine
/// records it yet; a run over a machine that already stands reads the file, because the value that
/// is correct there is the one somebody may have rotated by hand. Both, or neither, is refused
/// before this machine is asked anything.
final class GitPushCredential extends ReversibleStep<GitPushCredentialBefore> {
  /// Makes the checkout at [repository] able to push to [remote].
  const GitPushCredential({
    required this.repository,
    required this.remote,
    required this.credentialUser,
    this.credentialAnswer,
    this.credentialFile,
    this.credentialKey,
    this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory GitPushCredential.fromArguments(Arguments arguments) => GitPushCredential(
    repository: arguments.text('repository'),
    remote: arguments.text('remote'),
    credentialAnswer: arguments.optionalText('credential_answer'),
    credentialFile: arguments.optionalText('credential_file'),
    credentialKey: arguments.optionalText('credential_key'),
    credentialUser: arguments.text('credential_user'),
    runAnswer: arguments.optionalText('run_answer'),
  );

  /// What this step accepts.
  ///
  /// NO ELEVATION ARGUMENT, and that is a decision rather than an omission. Both paths this step
  /// touches belong to the account the run is: the settings file an earlier program of this
  /// installation wrote as that account, and the git directory of a checkout git refuses to any
  /// other account outright. There is nothing here for root to reach, and an elevation this step
  /// could not honestly apply to both would be a claim the run cannot keep.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout a push is made from, and whose own configuration is set',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      describes:
          'the name this checkout holds the remote under. Stated rather than known: a clone calls '
          'it "origin" and a checkout made another way carries whatever name was chosen',
    ),
    // TWO WAYS TO SAY WHERE THE CREDENTIAL COMES FROM, AND EXACTLY ONE OF THEM PER ROW. Both are
    // two answers to one question, and the day they disagree the checkout presents whichever the
    // reader happened to look at first.
    ArgumentSpec(
      name: 'credential_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the credential, for the run that has it before any file '
          'of this machine records it. Give this or the credential_file pair, never both',
      required: false,
    ),
    ArgumentSpec(
      name: 'credential_file',
      kind: ArgumentKind.text,
      describes:
          'the file of this machine that holds the credential a push is made with. It may carry '
          'the slot named by run_answer. Give this with credential_key, or give credential_answer '
          'instead — never both',
      required: false,
    ),
    ArgumentSpec(
      name: 'credential_key',
      kind: ArgumentKind.text,
      describes: 'the key of that file the credential stands under',
      required: false,
    ),
    ArgumentSpec(
      name: 'credential_user',
      kind: ArgumentKind.text,
      describes:
          'the account name the credential is presented under. What the host wants here is the '
          "host's own convention, so it is stated by the row rather than known by this step",
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in '
          'credential_file — write "stage" here and every "<stage>" in it is filled with this '
          "run's stage. Leave it off where the path carries no such axis",
      required: false,
    ),
  ];

  /// What the store file is called, inside the checkout's own git directory.
  static const String fileName = 'push-credentials';

  /// `0600` — the whole file is a credential, and git reads it as the account that owns the
  /// checkout.
  static const int fileMode = 384;

  /// The setting whose values decide which helper answers for this checkout.
  static const String helperKey = 'credential.helper';

  /// The checkout a push is made from.
  final String repository;

  /// The name the checkout holds the remote under.
  final String remote;

  /// The answer holding the credential, where no file of this machine records it yet.
  final String? credentialAnswer;

  /// The file holding the credential, and the key it stands under.
  final String? credentialFile;

  /// See [credentialFile].
  final String? credentialKey;

  /// The account name the credential is presented under.
  final String credentialUser;

  /// The name of the answer that fills the slot of the same name in [credentialFile].
  final String? runAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Wanted wanted = await _read(context);
    if (wanted.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    // The two constructors of _Wanted are the whole of it: one carries a refusal and no values, the
    // other carries every value and no refusal. Past the test above, these three are there.
    final String file = wanted.file!;
    final bool written =
        await context.files.exists(file) && await context.files.read(file) == wanted.line;
    return written && _pointsAtOnly(await _helpers(context), wanted.helper!)
        ? CheckResult.satisfied(
            '$repository presents a credential to $remote out of $file, and nothing outside this '
            'checkout decides which',
          )
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // The change is named and the value never is. A plan is read out of the run record, and the
    // whole content of this file is a credential — so a diff of it, which is what a step writing a
    // file would ordinarily produce, would put the credential into the plan. The redactor cannot
    // help here either: where the row reads the value out of a FILE it is neither a declared-secret
    // answer nor a declared-secret argument, so nothing would hide it.
    final CommandResult directory = await _ask(context, <String>[
      'rev-parse',
      '--absolute-git-dir',
    ]);
    final String where = directory.ok && directory.trimmed.isNotEmpty
        ? '${directory.trimmed}/$fileName'
        : "$repository's own git directory";
    return StepPlan.nothing(
      'would write the credential a push from $repository to $remote is made with into $where, '
      "and point this checkout's own credential helper at that file",
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Wanted wanted = await _read(context);
    if (wanted.refusal case final String refusal) {
      throw StateError(refusal);
    }
    // THE FILE FIRST AND THE HELPER SECOND. A run that dies between the two leaves a helper
    // pointing at a file that is not there, which is the state the machine was already in; the
    // other order would leave a credential at rest that nothing reads.
    await context.files.write(wanted.file!, wanted.line!, mode: fileMode);
    // THE EMPTY VALUE FIRST IS GIT'S OWN RESET OF THE HELPER LIST. Local configuration is read
    // after system and global, so an empty entry discards whatever helper the ACCOUNT configured
    // and this checkout's own credential is what decides. Local and never global: a machine may
    // hold several checkouts and only one of them is this installation's, and reaching into the
    // account's own configuration is a decision about their machine that a deployment has no
    // business making.
    await _mustRun(context, <String>['config', '--replace-all', helperKey, '']);
    await _mustRun(context, <String>['config', '--add', helperKey, wanted.helper!]);
  }

  /// What stood in the checkout before this run, so the undo can put exactly that back.
  @override
  Future<GitPushCredentialBefore> capture(StepContext context) async {
    final CommandResult directory = await _ask(context, <String>[
      'rev-parse',
      '--absolute-git-dir',
    ]);
    if (!directory.ok || directory.trimmed.isEmpty) {
      return const GitPushCredentialBefore(file: null, helpers: <String>[]);
    }
    final String path = '${directory.trimmed}/$fileName';
    return GitPushCredentialBefore(
      file: await context.files.exists(path) ? await context.files.read(path) : null,
      helpers: await _helpers(context),
    );
  }

  /// Puts back exactly the credential and the helpers the checkout carried.
  ///
  /// A checkout that already carried either keeps what it carried, because it is somebody's own and
  /// this run did not create it. An undo runs while the engine is cleaning up after a failure
  /// somewhere else in the program, which is the worst possible moment to take away a credential
  /// this step found rather than wrote.
  @override
  Future<void> undo(StepContext context, GitPushCredentialBefore captured) async {
    final CommandResult directory = await _ask(context, <String>[
      'rev-parse',
      '--absolute-git-dir',
    ]);
    if (directory.ok && directory.trimmed.isNotEmpty) {
      final String path = '${directory.trimmed}/$fileName';
      if (captured.file case final String held) {
        await context.files.write(path, held, mode: fileMode);
      } else if (await context.files.exists(path)) {
        await context.files.delete(path);
      }
    }
    // Not checked for success: git answers a non-zero exit for unsetting a key that is not set,
    // and a checkout that carried no helper is exactly the ordinary case here.
    await context.shell.run(
      Command.detailed(
        'git',
        arguments: <String>['-C', repository, 'config', '--unset-all', helperKey],
      ),
    );
    for (final String helper in captured.helpers) {
      await _mustRun(context, <String>['config', '--add', helperKey, helper]);
    }
  }

  /// What this row and this machine say together, or why they say nothing.
  ///
  /// THE ROW'S OWN SHAPE IS ANSWERED FIRST, before this machine is asked anything: a row naming
  /// both credential sources, or neither, or half of the file pair, is wrong wherever it runs.
  Future<_Wanted> _read(StepContext context) async {
    if (_shapeRefusal case final String refusal) {
      return _Wanted.unreadable(refusal);
    }

    final CommandResult directory = await _ask(context, <String>[
      'rev-parse',
      '--absolute-git-dir',
    ]);
    if (!directory.ok || directory.trimmed.isEmpty) {
      return _Wanted.unreadable(
        'there is no git checkout at $repository: ${directory.stderr.trim()}',
      );
    }
    // A helper is one configuration value that git splits on whitespace and reads as a command
    // followed by its arguments, so a store helper naming a path with a space in it is a helper
    // git tries to run as a program plus that many arguments.
    if (_whitespace.hasMatch(directory.trimmed)) {
      return _Wanted.unreadable(
        'the git directory of $repository is "${directory.trimmed}", and git splits a credential '
        'helper on whitespace — a helper naming that path is one git reads as a command and the '
        'words after it, so nothing there would ever be asked for a credential',
      );
    }

    final CommandResult stored = await _ask(context, <String>['remote', 'get-url', remote]);
    if (!stored.ok) {
      return _Wanted.unreadable(
        'this checkout has no remote called "$remote", so there is nothing a credential would be '
        'presented to: ${stored.stderr.trim()}',
      );
    }
    final Uri? address = Uri.tryParse(stored.trimmed);
    if (address == null || address.scheme != 'https' || address.host.isEmpty) {
      return _Wanted.unreadable(
        '$remote of $repository is ${stored.trimmed}, and a credential helper answers an https '
        'address and nothing else — configuring one here would leave this checkout exactly as '
        'unpushable while this row reported success',
      );
    }
    if (address.userInfo.isNotEmpty) {
      return _Wanted.unreadable(
        '$remote of $repository already carries a credential inside its own address, and this row '
        'will not put a second copy of one beside it — that address is at rest in the checkout\'s '
        'configuration for as long as the checkout stands, and every "git remote -v" prints it',
      );
    }

    final ({String? credential, String? refusal}) held = await _credential(context);
    if (held.refusal case final String refusal) {
      return _Wanted.unreadable(refusal);
    }

    final String host = address.hasPort ? '${address.host}:${address.port}' : address.host;
    final String file = '${directory.trimmed}/$fileName';
    // ENCODED, because git's store helper reads each line as a URL. A credential carrying an "@"
    // or a ":" written raw would split the userinfo somewhere else and quietly become part of a
    // host name, and what git then presents is a credential nobody typed.
    return _Wanted.of(
      file: file,
      line:
          'https://${Uri.encodeComponent(credentialUser)}:'
          '${Uri.encodeComponent(held.credential!)}@$host\n',
      helper: 'store --file=$file',
    );
  }

  /// Why this ROW cannot be read, whatever machine it runs on, or null when it can.
  String? get _shapeRefusal {
    final bool byFile = credentialFile != null || credentialKey != null;
    final bool byAnswer = credentialAnswer != null;
    if (byFile && byAnswer) {
      return 'this row names both credential_answer and credential_file, which are two answers to '
          'where the credential a push is made with comes from. Whichever a reader took first '
          'would be the one that decided, and the other would sit there looking like it had been '
          'read';
    }
    if (!byFile && !byAnswer) {
      return 'this row names neither credential_answer nor credential_file with credential_key, so '
          'nothing says where the credential a push is made with comes from';
    }
    if (byFile && (credentialFile == null || credentialKey == null)) {
      return 'this row names one of credential_file and credential_key and not the other, and a '
          'file with no key names no value in it';
    }
    return null;
  }

  /// The credential itself, out of whichever source the row named, or why there is none.
  Future<({String? credential, String? refusal})> _credential(StepContext context) async {
    if (credentialAnswer case final String name) {
      final String? held = context.answers.optionalText(name);
      if (held == null || held.isEmpty) {
        return (
          credential: null,
          refusal:
              'this run holds no value under the answer "$name", and that answer is the credential '
              'a push from $repository is made with — the run is given it, because a credential '
              'written into a program file would be the same credential on every installation',
        );
      }
      return (credential: held, refusal: null);
    }
    final String? path = filledPath(context, credentialFile!, runAnswer);
    if (path == null) {
      return (
        credential: null,
        refusal:
            'a path of this row still carries a slot nothing filled — the row names run_answer for '
            'the answer that fills it, and this run holds no value under that name',
      );
    }
    final String? held = await recordedValue(context, path, credentialKey!, elevated: false);
    if (held == null) {
      return (
        credential: null,
        refusal:
            '${credentialKey!} of $path is the credential a push from $repository is made with, '
            'and it is not there — an earlier program of this installation writes it into that '
            'file, and it is obtained once from whoever serves the repository',
      );
    }
    return (credential: held, refusal: null);
  }

  /// The values this checkout's own configuration holds for the helper setting, in git's order.
  ///
  /// An empty value prints as an empty line and IS a value — it is the first of the two this step
  /// writes — so only the terminating newline's own empty entry is dropped and nothing else.
  Future<List<String>> _helpers(StepContext context) async {
    final CommandResult answer = await _ask(context, <String>[
      'config',
      '--local',
      '--get-all',
      helperKey,
    ]);
    if (!answer.ok) {
      return const <String>[];
    }
    final List<String> values = answer.stdout.split('\n');
    if (values.isNotEmpty && values.last.isEmpty) {
      values.removeLast();
    }
    return values;
  }

  /// Whether [helpers] is the reset followed by [helper], and holds nothing else.
  bool _pointsAtOnly(List<String> helpers, String helper) =>
      helpers.length == 2 && helpers.first.isEmpty && helpers[1] == helper;

  Future<CommandResult> _ask(StepContext context, List<String> arguments) => context.shell.run(
    Command.observing('git', arguments: <String>['-C', repository, ...arguments]),
  );

  Future<void> _mustRun(StepContext context, List<String> arguments) async {
    final Command command = Command.detailed(
      'git',
      arguments: <String>['-C', repository, ...arguments],
    );
    final CommandResult answer = await context.shell.run(command);
    if (!answer.ok) {
      throw CommandFailed(
        argv: command.argv,
        exitCode: answer.exitCode,
        stdout: '',
        stderr: answer.stderr,
      );
    }
  }
}

/// Anything git would split a helper value on.
final RegExp _whitespace = RegExp(r'\s');

/// What this row would write, or why nothing can be written.
final class _Wanted {
  const _Wanted.of({
    required String this.file,
    required String this.line,
    required String this.helper,
  }) : refusal = null;

  const _Wanted.unreadable(String this.refusal) : file = null, line = null, helper = null;

  /// Where the store file stands, inside the checkout's own git directory.
  final String? file;

  /// The one line that file holds, which is the whole of the credential.
  final String? line;

  /// The helper value that points at that file.
  final String? helper;

  /// Why nothing can be written, or null when it can.
  final String? refusal;
}

/// What a checkout carried before this run, which is what the undo puts back.
final class GitPushCredentialBefore {
  /// Records the store [file]'s content and the [helpers] that stood in the checkout, the first
  /// null where there was no such file.
  const GitPushCredentialBefore({required this.file, required this.helpers});

  /// What the store file held, or null where the checkout carried none.
  final String? file;

  /// The helper values the checkout's own configuration held, in git's order.
  final List<String> helpers;
}
