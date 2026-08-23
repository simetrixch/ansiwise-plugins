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
    required this.runAnswer,
    this.branch,
    this.branchAnswer,
    this.originFile,
    this.originKey,
    this.originAnswer,
    this.credentialFile,
    this.credentialKey,
    this.credentialUser,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory GitClone.fromArguments(Arguments arguments) => GitClone(
    repository: arguments.text('repository'),
    host: arguments.text('host'),
    branch: arguments.optionalText('branch'),
    branchAnswer: arguments.optionalText('branch_answer'),
    originFile: arguments.optionalText('origin_file'),
    originKey: arguments.optionalText('origin_key'),
    originAnswer: arguments.optionalText('origin_answer'),
    credentialFile: arguments.optionalText('credential_file'),
    credentialKey: arguments.optionalText('credential_key'),
    credentialUser: arguments.optionalText('credential_user'),
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
    // THE BRANCH IS EITHER WRITTEN OR ANSWERED, for the same reason the origin is. A checkout of
    // one product's own tree stands on a branch that tree defines, and the row writes it. A
    // checkout of an INSTALLATION's tree stands on that installation's branch, which no program
    // file may name — so branch_answer names the answer holding it. Writing one installation's
    // branch here would move every other installation's checkout onto it.
    ArgumentSpec(
      name: 'branch',
      kind: ArgumentKind.text,
      describes:
          'the branch the checkout stands on, and the one every later run moves it to. Give this '
          'or branch_answer, never both',
      required: false,
    ),
    ArgumentSpec(
      name: 'branch_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding that branch, where it is one installation\'s own and '
          'cannot be written into a file that ships to every installation',
      required: false,
    ),
    // The names and never the values. The two files are one installation's own, written by an
    // earlier program of the same installation — a repository name or a credential written here
    // would ship one installation's to every installation.
    //
    // TWO WAYS TO SAY WHICH REPOSITORY, AND EXACTLY ONE OF THEM PER ROW. Reading it out of a
    // settings file is the ordinary way and stays the ordinary way: the file is written by an
    // earlier program, so the value is the machine's own and the row carries only names. But the
    // FIRST checkout of an installation has no earlier program — the programs live in a checkout
    // that does not exist yet — so there is no file to read, and origin_answer names the answer
    // holding owner/name instead. That is still a NAME in the program file; the value comes from
    // the installation's answers, which is where an installation's own facts live.
    //
    // A ROW GIVING NEITHER, OR BOTH, IS REFUSED. Neither leaves nothing to clone from; both are two
    // answers to one question, and the day they disagree the checkout points wherever the reader
    // happened to look first.
    ArgumentSpec(
      name: 'origin_file',
      kind: ArgumentKind.text,
      describes:
          'the settings file of this machine that records which repository this checkout is '
          'cloned from, as owner/name. It may carry the slot named by run_answer. Give this with '
          'origin_key, or give origin_answer instead — never both',
      required: false,
    ),
    ArgumentSpec(
      name: 'origin_key',
      kind: ArgumentKind.text,
      describes: 'the key of that file the owner/name stands under',
      required: false,
    ),
    ArgumentSpec(
      name: 'origin_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding owner/name, for a checkout made before any file of this '
          'machine records it — the first one of an installation. Give this or the origin_file '
          'pair, never both',
      required: false,
    ),
    // THE CREDENTIAL IS A GROUP AND IT IS OPTIONAL AS A GROUP. A public repository is read with
    // none, and handing one over anyway would put a credential on the network for a server that
    // never asked. A row giving some of the three and not the others is refused rather than read
    // as either: a credential with no account name is a credential nothing can present.
    ArgumentSpec(
      name: 'credential_file',
      kind: ArgumentKind.text,
      describes:
          'the file of this machine that holds the credential the repository is read with. It may '
          'carry the slot named by run_answer. Leave the three credential arguments off together '
          'for a repository that is served to anybody',
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
      required: false,
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

  /// The branch the checkout stands on, where the row writes it.
  final String? branch;

  /// The answer holding that branch, where it is one installation's own.
  final String? branchAnswer;

  /// The settings file recording the repository as owner/name, and its key.
  final String? originFile;

  /// See [originFile].
  final String? originKey;

  /// The answer holding owner/name, where no file of this machine records it yet.
  final String? originAnswer;

  /// The file holding the read credential, and its key.
  final String? credentialFile;

  /// See [credentialFile].
  final String? credentialKey;

  /// The account name the credential is presented under.
  final String? credentialUser;

  /// The name of the answer that fills the slot of the same name in the two file paths.
  final String? runAnswer;

  /// Whether the checkout and the two files belong to root.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'the checkout at $repository is placed on the published tip of the branch this row names '
      '— where one already '
      'stood, the position it stood on is kept nowhere on this machine, and a machine that carried '
      'none gains a directory nothing here removes again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Reading source = await _read(context);
    if (source.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = source.url ?? '';
    final String standsOn = source.branch ?? '';

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
    if (head.trimmed != standsOn) {
      return const CheckResult.ready();
    }

    // The remote is asked where the branch stands, which is the only way "current" means anything:
    // deciding on the local tip alone would report a checkout that fell behind as finished forever.
    final CommandResult published = await _observe(context, <String>[
      'ls-remote',
      '--heads',
      url,
      standsOn,
    ], environment: source.credentialEnvironment(host));
    if (!published.ok) {
      return CheckResult.blocked(
        'the repository at $url could not be asked where $standsOn stands — the credential '
        'under $credentialKey of ${source.credentialPath} is what it was asked with, so it is that '
        'or the network: ${published.stderr.trim()}',
      );
    }
    final String tip = published.trimmed.split(RegExp(r'\s+')).first;
    if (tip.isEmpty) {
      return CheckResult.blocked(
        '$url publishes no branch called $standsOn, and that is the branch this checkout '
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
    return CheckResult.satisfied('$repository stands on the published tip of $standsOn');
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Reading source = await _read(context);
    if (source.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final String standsOn = source.branch ?? '';
    // The address without the credential, which is also the address the command really carries —
    // the credential rides the environment precisely so no plan and no record hold it.
    return StepPlan.argv(<String>[
      'git',
      'clone',
      '--branch',
      standsOn,
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
    final String standsOn = source.branch ?? '';
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
        standsOn,
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
      standsOn,
    ], environment: reaching);
    // The local branch is PLACED on the fetched tip rather than merged onto it. This checkout is
    // read by what runs from it and written by nobody, so a divergence is drift to correct — and
    // the irreversible reason above is where that policy is priced.
    await _mustRun(context, <String>[
      '-C',
      repository,
      'checkout',
      '-B',
      standsOn,
      'origin/$standsOn',
    ]);
  }

  /// What the machine's own settings say this checkout is, or why they cannot be read.
  ///
  /// THE ROW'S OWN SHAPE IS ANSWERED FIRST, before this machine is asked anything. A row naming
  /// neither origin source, or both, or part of the credential group, is wrong wherever it runs —
  /// so it is refused without a file being opened, and the refusal names the row rather than the
  /// machine.
  Future<_Reading> _read(StepContext context) async {
    if (_shapeRefusal case final String refusal) {
      return _Reading.unreadable(refusal);
    }

    final String? standsOn = branch ?? context.answers.optionalText(branchAnswer!);
    if (standsOn == null) {
      return _Reading.unreadable(
        'this run holds no value under the answer "${branchAnswer!}", and that answer is the '
        'branch this checkout stands on — an installation states its own, because a branch written '
        'into a program file would be the branch of one installation moved onto every other',
      );
    }

    final String? ownerName = await _ownerName(context);
    if (ownerName == null) {
      return _Reading.unreadable(_originRefusal(context));
    }
    final String url = 'https://$host/$ownerName.git';

    // NO CREDENTIAL IS A STATE AND NOT AN OMISSION. A repository served to anybody is read with
    // none, and the row said so by leaving all three off — which the shape check above has already
    // held it to.
    if (credentialFile == null) {
      return _Reading.open(url: url, branch: standsOn);
    }

    final String? credentialPath = _filled(context, credentialFile!);
    if (credentialPath == null) {
      return const _Reading.unreadable(
        'a path of this row still carries a slot nothing filled — the row names run_answer for '
        'the answer that fills it, and this run holds no value under that name',
      );
    }
    final String? credential = await _recorded(context, credentialPath, credentialKey!);
    if (credential == null) {
      return _Reading.unreadable(
        '${credentialKey!} of $credentialPath is what the repository is read with, and it is not '
        'there — it is obtained once, from whoever serves the repository, and filled into that '
        'file',
      );
    }
    return _Reading.of(
      url: url,
      branch: standsOn,
      credentialUser: credentialUser!,
      credential: credential,
      credentialPath: credentialPath,
    );
  }

  /// Why this ROW cannot be read, whatever machine it runs on, or null when it can.
  String? get _shapeRefusal {
    if (branch != null && branchAnswer != null) {
      return 'this row names both branch and branch_answer, which are two answers to which branch '
          'this checkout stands on';
    }
    if (branch == null && branchAnswer == null) {
      return 'this row names neither branch nor branch_answer, so nothing says which branch this '
          'checkout stands on';
    }
    final bool byFile = originFile != null || originKey != null;
    final bool byAnswer = originAnswer != null;
    if (byFile && byAnswer) {
      return 'this row names both origin_file and origin_answer, which are two answers to which '
          'repository this checkout is cloned from. Whichever a reader took first would be the one '
          'that decided, and the other would sit there looking like it had been read';
    }
    if (!byFile && !byAnswer) {
      return 'this row names neither origin_file with origin_key nor origin_answer, so nothing '
          'says which repository this checkout is cloned from';
    }
    if (byFile && (originFile == null || originKey == null)) {
      return 'this row names one of origin_file and origin_key and not the other, and a file with '
          'no key names no value in it';
    }
    final int credentialParts = <String?>[
      credentialFile,
      credentialKey,
      credentialUser,
    ].where((String? each) => each != null).length;
    if (credentialParts != 0 && credentialParts != 3) {
      return 'this row names $credentialParts of the three credential arguments. They are a group: '
          'all three for a repository read with a credential, none for one served to anybody. A '
          'credential with no account name is one nothing can present, and an account name with no '
          'credential is a word with nothing behind it';
    }
    return null;
  }

  /// The owner/name this checkout is cloned from, out of whichever source the row named.
  Future<String?> _ownerName(StepContext context) async {
    if (originAnswer case final String name) {
      return context.answers.optionalText(name);
    }
    final String? originPath = _filled(context, originFile!);
    return originPath == null ? null : _recorded(context, originPath, originKey!);
  }

  /// Why the owner/name could not be read, said in terms of where this row looked for it.
  String _originRefusal(StepContext context) {
    if (originAnswer case final String name) {
      return 'this run holds no value under the answer "$name", and that answer is which '
          'repository this checkout is cloned from — a first checkout is made before any file of '
          'this machine records it, so the answer is the only place it stands';
    }
    final String? originPath = _filled(context, originFile!);
    if (originPath == null) {
      return 'a path of this row still carries a slot nothing filled — the row names run_answer '
          'for the answer that fills it, and this run holds no value under that name';
    }
    return '${originKey!} of $originPath is which repository this checkout is cloned from, and it '
        'is not there — the program that generates this installation writes it';
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
    required String this.branch,
    required String this.credentialUser,
    required String this.credential,
    required String this.credentialPath,
  }) : refusal = null;

  /// A repository served to anybody: an address and no credential at all.
  const _Reading.open({required String this.url, required String this.branch})
    : credentialUser = null,
      credential = null,
      credentialPath = null,
      refusal = null;

  const _Reading.unreadable(String this.refusal)
    : url = null,
      branch = null,
      credentialUser = null,
      credential = null,
      credentialPath = null;

  /// The address of the repository, with no credential in it.
  final String? url;

  /// The branch this checkout stands on, out of whichever source the row named.
  final String? branch;

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
  /// EMPTY WHERE THERE IS NO CREDENTIAL, which is not the same as an empty one. A header carrying
  /// `null:null` would be sent to a server that never asked for one and would be refused by some
  /// of them; no header at all is what a public repository is read with.
  Map<String, String> credentialEnvironment(String host) => credential == null
      ? const <String, String>{}
      : <String, String>{
          'GIT_CONFIG_COUNT': '1',
          'GIT_CONFIG_KEY_0': 'http.https://$host/.extraHeader',
          'GIT_CONFIG_VALUE_0':
              'Authorization: Basic ${base64Encode(utf8.encode('$credentialUser:$credential'))}',
        };
}
