import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts a checkout of one repository at a path on this machine, on a stated branch, and moves it to
/// that branch's published tip on every later run.
///
/// **Which repository, and with what right, are read off this machine and never written in a
/// program file.** A program file ships to every installation, so it carries the NAMES: which
/// settings file of this machine records the repository (as `owner/name`), which file holds the
/// read credential, and under which key each stands. Both files are written by an earlier program
/// of the same installation, which is also why a run that finds them missing is refused by file and
/// key rather than sent on to clone nothing.
///
/// **The credential travels in the environment and is at rest nowhere this step writes.** A
/// credential in a command's arguments is in the process listing and in the record; one written
/// into the checkout's own remote address is at rest in a file for as long as the checkout stands.
/// So the remote address this step stores carries no credential at all, and every command that
/// reaches the network is handed the credential through git's own configuration-by-environment,
/// as an authorization header — the environment of a command reaches neither the process listing
/// nor the record. A later run needs the credential again and brings it the same way, from the same
/// file this run read it from.
///
/// **A checkout that is already there is moved, not replaced.** The check reads what is there — is
/// it a checkout, does its remote point where this row says, is it on the branch, is it at the tip
/// the remote publishes — and only a difference makes work. The apply then corrects exactly the
/// difference: the remote address is set, the branch is fetched, and the local branch is placed on
/// the fetched tip. What that costs is stated in the irreversible reason: a position the checkout
/// stood on before is kept nowhere.
final class GitClone extends IrreversibleStep {
  /// Clones into [repository] the repository the machine's own settings name, on [branch].
  const GitClone({
    required this.repository,
    required this.host,
    required this.branch,
    required this.originFile,
    required this.originKey,
    required this.credentialFile,
    required this.credentialKey,
    required this.credentialUser,
    required this.runAnswer,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory GitClone.fromArguments(Arguments arguments) => GitClone(
    repository: arguments.text('repository'),
    host: arguments.text('host'),
    branch: arguments.text('branch'),
    originFile: arguments.text('origin_file'),
    originKey: arguments.text('origin_key'),
    credentialFile: arguments.text('credential_file'),
    credentialKey: arguments.text('credential_key'),
    credentialUser: arguments.text('credential_user'),
    runAnswer: arguments.optionalText('run_answer'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'where the checkout stands on this machine',
    ),
    ArgumentSpec(
      name: 'host',
      kind: ArgumentKind.text,
      describes:
          'the https host the repository is served from, which with the recorded owner/name '
          'composes the address the clone reads',
    ),
    ArgumentSpec(
      name: 'branch',
      kind: ArgumentKind.text,
      describes: 'the branch the checkout stands on, and the one every later run moves it to',
    ),
    // The names and never the values. The two files are one installation's own, written by an
    // earlier program of the same installation — a repository name or a credential written here
    // would ship one installation's to every installation.
    ArgumentSpec(
      name: 'origin_file',
      kind: ArgumentKind.text,
      describes:
          'the settings file of this machine that records which repository this checkout is '
          'cloned from, as owner/name. It may carry the slot named by run_answer',
    ),
    ArgumentSpec(
      name: 'origin_key',
      kind: ArgumentKind.text,
      describes: 'the key of that file the owner/name stands under',
    ),
    ArgumentSpec(
      name: 'credential_file',
      kind: ArgumentKind.text,
      describes:
          'the file of this machine that holds the credential the repository is read with. It may '
          'carry the slot named by run_answer',
    ),
    ArgumentSpec(
      name: 'credential_key',
      kind: ArgumentKind.text,
      describes: 'the key of that file the credential stands under',
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
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'two file paths — write "stage" here and every "<stage>" in them is filled with this '
          "run's stage. Leave it off where the paths carry no such axis",
      required: false,
    ),
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the checkout and the two files belong to root, so reading and writing them '
          'needs elevation. Leave it off for paths this account owns',
      required: false,
    ),
  ];

  /// Where the checkout stands.
  final String repository;

  /// The https host the repository is served from.
  final String host;

  /// The branch the checkout stands on.
  final String branch;

  /// The settings file recording the repository as owner/name, and its key.
  final String originFile;

  /// See [originFile].
  final String originKey;

  /// The file holding the read credential, and its key.
  final String credentialFile;

  /// See [credentialFile].
  final String credentialKey;

  /// The account name the credential is presented under.
  final String credentialUser;

  /// The name of the answer that fills the slot of the same name in the two file paths.
  final String? runAnswer;

  /// Whether the checkout and the two files belong to root.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'the checkout at $repository is placed on the published tip of $branch — where one already '
      'stood, the position it stood on is kept nowhere on this machine, and a machine that carried '
      'none gains a directory nothing here removes again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Reading source = await _read(context);
    if (source.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = source.url ?? '';

    if (!(await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--is-inside-work-tree',
    ])).ok) {
      return const CheckResult.ready();
    }

    final CommandResult remote = await _observe(context, <String>[
      '-C',
      repository,
      'remote',
      'get-url',
      'origin',
    ]);
    if (!remote.ok || remote.trimmed != url) {
      return const CheckResult.ready();
    }

    final CommandResult head = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    if (head.trimmed != branch) {
      return const CheckResult.ready();
    }

    // The remote is asked where the branch stands, which is the only way "current" means anything:
    // deciding on the local tip alone would report a checkout that fell behind as finished forever.
    final CommandResult published = await _observe(context, <String>[
      'ls-remote',
      '--heads',
      url,
      branch,
    ], environment: source.credentialEnvironment(host));
    if (!published.ok) {
      return CheckResult.blocked(
        'the repository at $url could not be asked where $branch stands — the credential '
        'under $credentialKey of ${source.credentialPath} is what it was asked with, so it is that '
        'or the network: ${published.stderr.trim()}',
      );
    }
    final String tip = published.trimmed.split(RegExp(r'\s+')).first;
    if (tip.isEmpty) {
      return CheckResult.blocked(
        '$url publishes no branch called $branch, and that is the branch this checkout '
        'stands on',
      );
    }

    final CommandResult standing = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      'HEAD',
    ]);
    if (standing.trimmed != tip) {
      return const CheckResult.ready();
    }
    return CheckResult.satisfied('$repository stands on the published tip of $branch');
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Reading source = await _read(context);
    if (source.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    // The address without the credential, which is also the address the command really carries —
    // the credential rides the environment precisely so no plan and no record hold it.
    return StepPlan.argv(<String>[
      'git',
      'clone',
      '--branch',
      branch,
      source.url ?? '',
      repository,
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Reading source = await _read(context);
    if (source.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String url = source.url ?? '';
    final Map<String, String> reaching = source.credentialEnvironment(host);

    if (!(await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--is-inside-work-tree',
    ])).ok) {
      await _mustRun(context, <String>[
        'clone',
        '--branch',
        branch,
        url,
        repository,
      ], environment: reaching);
      return;
    }

    final CommandResult remote = await _observe(context, <String>[
      '-C',
      repository,
      'remote',
      'get-url',
      'origin',
    ]);
    if (!remote.ok) {
      await _mustRun(context, <String>['-C', repository, 'remote', 'add', 'origin', url]);
    } else if (remote.trimmed != url) {
      await _mustRun(context, <String>['-C', repository, 'remote', 'set-url', 'origin', url]);
    }
    await _mustRun(context, <String>[
      '-C',
      repository,
      'fetch',
      'origin',
      branch,
    ], environment: reaching);
    // The local branch is PLACED on the fetched tip rather than merged onto it. This checkout is
    // read by what runs from it and written by nobody, so a divergence is drift to correct — and
    // the irreversible reason above is where that policy is priced.
    await _mustRun(context, <String>['-C', repository, 'checkout', '-B', branch, 'origin/$branch']);
  }

  /// What the machine's own settings say this checkout is, or why they cannot be read.
  Future<_Reading> _read(StepContext context) async {
    final String? originPath = _filled(context, originFile);
    final String? credentialPath = _filled(context, credentialFile);
    if (originPath == null || credentialPath == null) {
      return const _Reading.unreadable(
        'a path of this row still carries a slot nothing filled — the row names run_answer for '
        'the answer that fills it, and this run holds no value under that name',
      );
    }
    final String? ownerName = await _recorded(context, originPath, originKey);
    if (ownerName == null) {
      return _Reading.unreadable(
        '$originKey of $originPath is which repository this checkout is cloned from, and it is '
        'not there — the program that generates this installation writes it',
      );
    }
    final String? credential = await _recorded(context, credentialPath, credentialKey);
    if (credential == null) {
      return _Reading.unreadable(
        '$credentialKey of $credentialPath is what the repository is read with, and it is not '
        'there — it is obtained once, from whoever serves the repository, and filled into that '
        'file',
      );
    }
    return _Reading.of(
      url: 'https://$host/$ownerName.git',
      credentialUser: credentialUser,
      credential: credential,
      credentialPath: credentialPath,
    );
  }

  /// [text] with the run's own value in its slot, or null while a slot stands unfilled.
  String? _filled(StepContext context, String text) {
    String written = text;
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        written = filledSlots(written, <String, String>{name: value});
      }
    }
    return leftoverSlotIn(written) == null ? written : null;
  }

  /// The value [file] records under [key], or null where it records none worth reading.
  ///
  /// The file is `KEY=value` lines, which is the shape both settings files of an installation are
  /// written in. A value still carrying angle brackets is the text that marks it unfilled, and it
  /// is refused like an absent one: sent onward it would become part of an address.
  Future<String?> _recorded(StepContext context, String file, String key) async {
    if (!await context.files.exists(file, elevated: elevated)) {
      return null;
    }
    final String content = await context.files.read(file, elevated: elevated);
    final RegExp line = RegExp('^[ \\t]*${RegExp.escape(key)}[ \\t]*=[ \\t]*(.*)\$');
    for (final String each in content.split('\n')) {
      final RegExpMatch? match = line.firstMatch(each.trimRight());
      if (match == null) {
        continue;
      }
      String value = match.group(1)!.trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isEmpty || (value.contains('<') && value.contains('>'))) {
        return null;
      }
      return value;
    }
    return null;
  }

  Future<CommandResult> _observe(
    StepContext context,
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
  }) => context.shell.run(
    Command.detailed(
      'git',
      arguments: arguments,
      environment: environment,
      observes: true,
      elevated: elevated,
    ),
  );

  Future<void> _mustRun(
    StepContext context,
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
  }) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed('git', arguments: arguments, environment: environment, elevated: elevated),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>['git', ...arguments],
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}

/// What the machine's settings say about this checkout, or why they cannot be read.
final class _Reading {
  const _Reading.of({
    required String this.url,
    required String this.credentialUser,
    required String this.credential,
    required String this.credentialPath,
  }) : refusal = null;

  const _Reading.unreadable(String this.refusal)
    : url = null,
      credentialUser = null,
      credential = null,
      credentialPath = null;

  /// The address of the repository, with no credential in it.
  final String? url;

  /// The account name the credential is presented under.
  final String? credentialUser;

  /// The credential itself, which reaches only the environment of a command.
  final String? credential;

  /// Where the credential was read from, for a refusal that has to name it.
  final String? credentialPath;

  /// Why nothing can be read, or null when it can.
  final String? refusal;

  /// The credential as git takes it without it appearing in any argument: an authorization header,
  /// set through git's configuration-by-environment for every address on [host].
  Map<String, String> credentialEnvironment(String host) => <String, String>{
    'GIT_CONFIG_COUNT': '1',
    'GIT_CONFIG_KEY_0': 'http.https://$host/.extraHeader',
    'GIT_CONFIG_VALUE_0':
        'Authorization: Basic ${base64Encode(utf8.encode('$credentialUser:$credential'))}',
  };
}
