import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'recorded_value.dart';

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
    this.ownerAnswer,
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
    ownerAnswer: arguments.optionalText('owner_answer'),
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
    // WHO OWNS THE CHECKOUT DECIDES WHO CAN USE IT AFTERWARDS, and git enforces that itself: it
    // refuses a repository owned by another account outright — "detected dubious ownership" — so a
    // tree cloned as root is a tree every later step running as the operator is locked out of.
    //
    // The directory usually cannot be MADE by that account either: a checkout under /srv sits in a
    // directory only root may write. So it is created elevated and handed over, and everything git
    // does afterwards runs as its owner. That is one act and belongs to the row that makes the
    // checkout, not to a second row somebody has to remember.
    ArgumentSpec(
      name: 'owner_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the account this checkout belongs to. Given, the '
          'directory is created for that account with elevation and git is run as it; left off, '
          'the checkout belongs to whoever the run is',
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

  /// The answer holding the account this checkout belongs to, where it is not the run's own.
  final String? ownerAnswer;

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

    // WHO OWNS IT IS ASKED FIRST, because git refuses a repository owned by another account before
    // it answers anything else — "detected dubious ownership" — so every question below would come
    // back as a failure that says nothing about the checkout.
    final ({String? owner, String? refusal}) ownership = await _ownedByAnother(context);
    if (ownership.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (ownership.owner case final String owner) {
      context.log.info(
        '$repository belongs to $owner and this run is not it, so git will not read it at all — '
        'the directory is handed over before anything else is asked of it',
      );
      return const CheckResult.ready();
    }

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

    // THE DIRECTORY IS MADE AND HANDED OVER BEFORE GIT IS ASKED ANYTHING. A checkout under a path
    // only root may write cannot be created by the account that has to use it, and one created as
    // root is one git then refuses to that account. Both are the same act from the machine's side:
    // make it with elevation, own it as the answer says, and every git command afterwards is an
    // ordinary one.
    //
    // `-R` because this also corrects a tree that is ALREADY there under the wrong owner, which is
    // what a machine left by an earlier shape of this row looks like.
    if (ownerAnswer case final String name) {
      if (context.answers.optionalText(name) case final String account) {
        await _mustRunAs(context, <String>[
          'install',
          '-d',
          '-o',
          account,
          '-g',
          account,
          repository,
        ], elevated: true);
      }
    }

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
      await _handOver(context);
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
    await _handOver(context);
  }

  /// Hands the checkout to the account the row names, AFTER git has written into it.
  ///
  /// **THE ORDER IS THE WHOLE OF IT, and it used to be the other way round.** The directory is made
  /// and handed over before git is asked anything, because a checkout under a path only root may
  /// write cannot be created by the account that has to use it — that part is right and stays. What
  /// was wrong is that the hand-over ALSO ran there and nowhere else: git then wrote the repository
  /// into a directory that had just been handed over, and every file it made — the whole of `.git`
  /// among them — came out belonging to whoever ran it. Which is root: a program of this kind is
  /// started elevated, so a row that asks for no elevation of its own is still a root process.
  ///
  /// So the account was given an empty directory and root kept the repository inside it, on every
  /// machine, from the first install. Nothing met it while only elevated programs drove that
  /// checkout; the first caller that was not root was refused by git outright, four programs and one
  /// run kind later.
  ///
  /// `-R` and unconditional: it also corrects a tree left under the wrong owner by an earlier shape
  /// of this row, and it costs one command over a tree this row has just written anyway.
  Future<void> _handOver(StepContext context) async {
    if (ownerAnswer case final String name) {
      if (context.answers.optionalText(name) case final String account) {
        await _mustRunAs(context, <String>[
          'chown',
          '-R',
          '$account:$account',
          repository,
        ], elevated: true);
      }
    }
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

    final String? credentialPath = filledPath(context, credentialFile!, runAnswer);
    if (credentialPath == null) {
      return const _Reading.unreadable(
        'a path of this row still carries a slot nothing filled — the row names run_answer for '
        'the answer that fills it, and this run holds no value under that name',
      );
    }
    final String? credential = await recordedValue(
      context,
      credentialPath,
      credentialKey!,
      elevated: elevated,
    );
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
    final String? originPath = filledPath(context, originFile!, runAnswer);
    return originPath == null
        ? null
        : recordedValue(context, originPath, originKey!, elevated: elevated);
  }

  /// Why the owner/name could not be read, said in terms of where this row looked for it.
  String _originRefusal(StepContext context) {
    if (originAnswer case final String name) {
      return 'this run holds no value under the answer "$name", and that answer is which '
          'repository this checkout is cloned from — a first checkout is made before any file of '
          'this machine records it, so the answer is the only place it stands';
    }
    final String? originPath = filledPath(context, originFile!, runAnswer);
    if (originPath == null) {
      return 'a path of this row still carries a slot nothing filled — the row names run_answer '
          'for the answer that fills it, and this run holds no value under that name';
    }
    return '${originKey!} of $originPath is which repository this checkout is cloned from, and it '
        'is not there — the program that generates this installation writes it';
  }

  /// What every git command here says before anything else: this checkout is trusted.
  ///
  /// **git refuses a repository owned by another account outright**, before it answers any question
  /// asked of it — `detected dubious ownership in repository at ...`. That refusal is not an answer
  /// about the checkout, but it comes back on the same channel as one, and a caller reading it as
  /// one concludes there is no checkout and clones onto the one that is standing. That is what
  /// happened: an elevated row met a checkout belonging to the operating account, its
  /// `rev-parse --is-inside-work-tree` came back not-ok, and the clone that followed died on a
  /// directory that was not empty.
  ///
  /// **It is not dubious, and this says so rather than working around it.** The row declares who
  /// the directory belongs to — `owner_answer` — and hands it to that account where it does not. A
  /// platform that places a checkout and prescribes its owner knows the one thing git cannot: that
  /// the account owning it is the intended one.
  ///
  /// **`-c` and never `git config --global`.** It is said for this command and no other. Written
  /// into an account's configuration it would outlive the run that needed it, about a path that may
  /// not be there tomorrow.
  /// **Said only to a command that reads the checkout.** `clone` lands on a path that holds no
  /// repository yet and `ls-remote` asks a remote; neither can meet a dubious owner, and a
  /// statement about a local path in front of them would stand in the record saying nothing.
  List<String> _trusting(List<String> arguments) =>
      arguments.length >= 2 && arguments.first == '-C' && arguments[1] == repository
      ? <String>['-c', 'safe.directory=$repository', ...arguments]
      : arguments;

  Future<CommandResult> _observe(
    StepContext context,
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
  }) => context.shell.run(
    Command.detailed(
      'git',
      arguments: _trusting(arguments),
      environment: environment,
      observes: true,
      elevated: elevated,
    ),
  );

  /// The account [repository] belongs to where it is not the one this run is, or why that could not
  /// be read.
  ///
  /// Read with `stat` rather than by asking git, because git is the thing that refuses: a
  /// repository owned by another account makes every one of its commands fail with the same
  /// message, and a check that learned the ownership from that failure would be reading a symptom.
  ///
  /// **BOTH THE WORKTREE AND ITS `.git`, because git decides on the SECOND one.** Reading only the
  /// outer directory is what let a checkout pass this check while git went on refusing it: a tree
  /// whose worktree had been handed to the account while the `.git` inside it was left with the
  /// account that made it. This row then reported the hand-over already done, [apply] never ran, and
  /// every caller but the one that owns the `.git` met `fatal: detected dubious ownership` — on a
  /// machine whose install had reported success. The account also has to own the worktree to write
  /// in it, so a mismatch on EITHER is a hand-over that has to happen.
  ///
  /// **ASKED AS ROOT, and not at this row's elevation.** The row's flag says whether the checkout
  /// and the two settings files are root's to read; this question is a different one, and the two
  /// commands that answer it in [apply] — `install -d` and `chown -R` — are already elevated
  /// whatever the row said. A checkout inside a directory only root may enter answers `stat` with
  /// "Permission denied" to anybody else, and that empty answer used to read here as "no other
  /// owner": the one reading that makes this step skip the hand-over it exists to perform. Nothing
  /// new is asked of the machine by this — a row naming an owner already needs the elevation those
  /// two commands run at.
  ///
  /// A path that is not there yet is "no other owner": there is nothing to hand over, and the clone
  /// below makes it. That is now a MEASURED answer rather than an assumed one — root can stat
  /// anything that is there, so `stat` answering nothing over a path the files port still finds is a
  /// reading that could not be taken, and it is refused as one. An ABSENT `.git` beside a worktree
  /// that IS there is that same "nothing to hand over": a directory that is not a repository yet is
  /// what the clone below turns into one.
  Future<({String? owner, String? refusal})> _ownedByAnother(StepContext context) async {
    if (ownerAnswer case final String name) {
      if (context.answers.optionalText(name) case final String account) {
        // The worktree first, then the directory git actually decides on. A mismatch on either is a
        // hand-over, and the `.git` is asked SECOND so that its answer is the one reported when both
        // disagree — that is the one whose refusal an operator meets.
        for (final String path in <String>[repository, '$repository/.git']) {
          final CommandResult owner = await context.shell.run(
            Command.observing('stat', arguments: <String>['-c', '%U', path], elevated: true),
          );
          if (owner.ok && owner.trimmed.isNotEmpty) {
            if (owner.trimmed != account) {
              return (owner: owner.trimmed, refusal: null);
            }
            continue;
          }
          if (await context.files.exists(path, elevated: true)) {
            return (
              owner: null,
              refusal:
                  'who $path belongs to could not be read, and it is there — so this row can '
                  'say neither that it has to be handed to "$account" nor that it does not, and git '
                  'refuses a repository owned by another account outright: '
                  '${owner.stderr.trim().isEmpty ? 'stat answered nothing' : owner.stderr.trim()}',
            );
          }
        }
      }
    }
    return (owner: null, refusal: null);
  }

  /// One command that is NOT git, run for its effect on the machine.
  ///
  /// Separate from [_mustRun] because that one always starts `git` and always at this row's own
  /// elevation, and the two commands that hand a directory over are neither: they are `install` and
  /// `chown`, and they are elevated whatever the row said about the files it reads.
  Future<void> _mustRunAs(StepContext context, List<String> argv, {required bool elevated}) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: elevated),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }

  Future<void> _mustRun(
    StepContext context,
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
  }) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        'git',
        arguments: _trusting(arguments),
        environment: environment,
        elevated: elevated,
      ),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>['git', ..._trusting(arguments)],
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
