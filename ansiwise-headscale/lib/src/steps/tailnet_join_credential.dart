import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// Makes a join credential for one machine available to the caller, minting one only where the
/// coordinator holds none it would still redeem.
///
/// **The coordinator is the source of truth, and it is asked FIRST.** What this step promises its
/// caller is a credential that will get a machine onto the network, and a key is only that if the
/// coordinator is there to redeem it. So a coordinator that cannot be asked BLOCKS this step — it
/// never concludes "no key, mint one" from silence, because acting on silence is how a caller ends
/// up logging a machine out on the strength of a credential that turns out not to exist.
///
/// **One coordinator user per machine, named after it.** That is what makes a later removal exact:
/// destroying the user takes its pre-auth keys and its registered node with it and touches no other
/// machine. The coordinator runs no policy between members — membership IS the boundary — which is
/// also why a key must never be handed out wider than one machine, once.
///
/// **A key that is still redeemable is handed back, never replaced.** Minting a fresh one on every
/// run would leave the coordinator holding a growing set of live credentials nobody can account
/// for. Only a key the coordinator itself reports as used or expired is replaced — a dead key is
/// not a live credential, so replacing it rotates nothing and leaves nothing behind.
///
/// **The credential leaves this step through ONE channel: the file the row names.** Written
/// readable by its owner alone, for the caller to read and remove. It is never an output line — a
/// run's record keeps what a failed command printed, and a credential must have no way into a file
/// that outlives it — and it is never an argument, which every account on the machine can read in
/// the process listing.
final class TailnetJoinCredential extends IrreversibleStep {
  /// Mints or hands back the credential for the machine [userAnswer] names.
  const TailnetJoinCredential({
    required this.invocation,
    required this.needsRoot,
    required this.userAnswer,
    required this.ttl,
    required this.keyFile,
    required this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory TailnetJoinCredential.fromArguments(Arguments arguments) {
    final List<String> invocation = arguments.textList('headscale');
    if (invocation.isEmpty) {
      throw ArgumentError.value(
        invocation,
        'headscale',
        'names no word at all, so there is nothing to invoke the coordinator\'s admin surface with',
      );
    }
    return TailnetJoinCredential(
      invocation: invocation,
      needsRoot: arguments.has('headscale_needs_root') && arguments.flag('headscale_needs_root'),
      userAnswer: arguments.text('user_answer'),
      ttl: arguments.text('ttl'),
      keyFile: arguments.text('key_file'),
      runAnswer: arguments.optionalText('run_answer'),
    );
  }

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'headscale',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>['headscale'],
      describes:
          'the words the coordinator\'s admin surface is invoked with, in front of every '
          'subcommand — the default is the plain command on the path, and a coordinator that runs '
          'as a workload names every word of the invocation that reaches into it instead',
    ),
    ArgumentSpec(
      name: 'headscale_needs_root',
      kind: ArgumentKind.flag,
      required: false,
      describes:
          'whether that invocation has to run as root to reach the coordinator at all. Leave it '
          'off for an invocation this account may make',
    ),
    ArgumentSpec(
      name: 'user_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer that holds the machine\'s name at the coordinator — one '
          'coordinator user per machine, named after it, so a later removal is exact',
    ),
    ArgumentSpec(
      name: 'ttl',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: '24h',
      describes:
          'how long an unredeemed key stays usable. It only has to outlive the one run that '
          'carries it to the machine — an unused credential that lives longer is a standing key '
          'into the network',
    ),
    ArgumentSpec(
      name: 'key_file',
      kind: ArgumentKind.text,
      describes:
          'where the credential is put for the caller, readable by this account alone — the '
          'caller reads it and removes it, and the file is the ONLY way the value leaves this '
          'step. It may carry the slots the two named answers fill, so two machines\' credentials '
          'never share a file',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'invocation words and the key file path — write "stage" here and every "<stage>" in '
          'them is filled with this run\'s stage. Leave it off where nothing is marked. The '
          'answer user_answer names fills its own slot the same way',
    ),
  ];

  /// The words the admin surface is invoked with, before any slot is filled.
  final List<String> invocation;

  /// Whether the invocation runs as root.
  final bool needsRoot;

  /// The name of the answer that holds the machine's name at the coordinator.
  final String userAnswer;

  /// How long an unredeemed key stays usable.
  final String ttl;

  /// Where the credential is put for the caller, before any slot is filled.
  final String keyFile;

  /// The name of the answer whose value fills the slot of the same name, or null.
  final String? runAnswer;

  /// The key file's mode: readable by its owner alone (0600, in the hexadecimal Dart can spell),
  /// because it holds a credential that puts a machine of the holder's choosing on the network.
  static const int _keyFileMode = 0x180;

  /// How long any one admin call may take: the surface answers from memory, so what this bound
  /// cuts short is only a coordinator that accepted the connection and then hung.
  static const Duration _callBudget = Duration(seconds: 60);

  @override
  String get irreversibleReason =>
      'a pre-auth key is live at the coordinator from the moment it is minted — removing the file '
      'this wrote would not take the credential itself back, and expiring it early is the '
      'removal\'s act, not an unwind\'s';

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Coordinator? coordinator = await _users(context);
    if (coordinator == null) {
      return CheckResult.blocked(
        'the coordinator\'s admin surface did not answer its own user listing — a credential can '
        'only be promised where the coordinator is there to redeem it, so nothing is minted on '
        'silence. Asked with: ${_filled(context, invocation).join(' ')}',
      );
    }
    final String? uid = coordinator.idOf(_name(context));
    if (uid == null) {
      return const CheckResult.ready();
    }
    final List<String>? usable = await _usableKeys(context, uid);
    if (usable == null) {
      return const CheckResult.blocked(
        'the coordinator\'s admin surface did not answer its key listing, so whether a stored '
        'credential is still redeemable cannot be known — and doubt must never be read as "the '
        'key is dead": that would mint on every hiccup and leave live credentials behind',
      );
    }
    final String file = _filled(context, <String>[keyFile]).single;
    if (usable.isNotEmpty && await context.files.exists(file)) {
      final String held = (await context.files.read(file)).trim();
      // BY PREFIX, because the listing does not carry credentials. What it prints under `key` is
      // the key's opening — 27 characters where the credential is 88 — and only `create` ever
      // answers with the whole of one. Compared for equality this could never match, so a run
      // could never find its own key standing and would mint another on every retry.
      if (_isWholeKey(held, usable)) {
        return CheckResult.satisfied(
          'the coordinator still redeems the credential standing at $file — handed back, '
          'never replaced',
        );
      }
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>[
    ..._filled(context, invocation),
    'preauthkeys',
    'create',
    '--user',
    _name(context),
    '--expiration',
    ttl,
    '-o',
    'json',
  ]);

  @override
  Future<void> apply(StepContext context) async {
    final List<String> admin = _filled(context, invocation);
    final String name = _name(context);

    _Coordinator? coordinator = await _users(context);
    if (coordinator == null) {
      throw StateError('the coordinator\'s admin surface stopped answering its user listing');
    }
    String? uid = coordinator.idOf(name);
    if (uid == null) {
      await _mustRun(context, <String>[...admin, 'users', 'create', name]);
      coordinator = await _users(context);
      uid = coordinator?.idOf(name);
      if (uid == null) {
        throw StateError(
          'the coordinator created the user "$name" without refusing, and its listing still does '
          'not carry it — read the coordinator\'s own log',
        );
      }
    }

    final List<String>? usable = await _usableKeys(context, uid);
    if (usable == null) {
      throw StateError('the coordinator\'s admin surface stopped answering its key listing');
    }
    // WHAT THE LISTING SAYS AND WHAT IT CANNOT GIVE. It says which keys the coordinator would still
    // redeem, by their opening; it never carries a credential. So the only place a whole key lives
    // is the file this step wrote, and a standing key is handed back only when THAT file holds it.
    //
    // Taken out of the listing instead, what reached the machine was 28 bytes of a key's opening
    // and tailscale refused it: "failed to parse auth-key: key too short, expected at least 77
    // chars after prefix, got 16" (apps4, 2026-08-29).
    final String keyPath = _filled(context, <String>[keyFile]).single;
    final String standing = await context.files.exists(keyPath)
        ? (await context.files.read(keyPath)).trim()
        : '';
    String key;
    if (_isWholeKey(standing, usable)) {
      // The coordinator still redeems the one this machine was already told to use — handed back
      // rather than replaced, so a retry carries the SAME credential.
      key = standing;
    } else {
      final CommandResult minted = await context.shell.run(
        Command.detailed(
          admin.first,
          arguments: <String>[
            ...admin.sublist(1),
            'preauthkeys',
            'create',
            '--user',
            uid,
            '--expiration',
            ttl,
            '-o',
            'json',
          ],
          elevated: needsRoot,
          timeout: _callBudget,
        ),
      );
      final Object? answer = minted.exitCode == 0 ? _decoded(minted.stdout) : null;
      final Object? value = answer is Map<String, Object?> ? answer['key'] : null;
      key = value is String ? value.trim() : '';
      if (key.isEmpty) {
        // Deliberately without the output: a failed mint prints an error, but nothing here may
        // gamble a credential into an exception message that outlives the run.
        throw StateError(
          'the coordinator did not return a pre-auth key for user "$name" (exit '
          '${minted.exitCode}) — read the coordinator\'s own log',
        );
      }
    }

    final String file = _filled(context, <String>[keyFile]).single;
    await context.files.write(file, '$key\n', mode: _keyFileMode);
  }

  /// The machine's name at the coordinator, read out of the run under the name the row gave.
  String _name(StepContext context) => context.answers.text(userAnswer).trim();

  /// [words] with the slots of the two named answers filled: the one [runAnswer] names and the
  /// one [userAnswer] names, each where the slot spelled with its own name marks it.
  ///
  /// Derived from the names rather than declared beside them, so a slot and its answer cannot come
  /// apart: a program that renames the answer renames the slot in the same act. Words carrying no
  /// slot, a row naming no answer, and a run not holding one all come back unchanged — the last so
  /// the slot stays visible in whatever refusal reports the words, rather than being replaced by
  /// an empty string nobody could see.
  List<String> _filled(StepContext context, List<String> words) {
    List<String> filled = words;
    for (final String? answer in <String?>[runAnswer, userAnswer]) {
      if (answer == null || !context.answers.has(answer)) {
        continue;
      }
      final String slot = '<$answer>';
      final String value = context.answers.text(answer);
      filled = <String>[for (final String word in filled) word.replaceAll(slot, value)];
    }
    return filled;
  }

  /// The coordinator's users, or null when the surface did not answer.
  Future<_Coordinator?> _users(StepContext context) async {
    final List<String> admin = _filled(context, invocation);
    final CommandResult listed = await context.shell.run(
      Command.observing(
        admin.first,
        arguments: <String>[...admin.sublist(1), 'users', 'list', '-o', 'json'],
        elevated: needsRoot,
      ),
    );
    if (listed.exitCode != 0) {
      return null;
    }
    final List<Object?>? rows = _rowsOf(listed.stdout);
    if (rows == null) {
      return null;
    }
    final Map<String, String> ids = <String, String>{};
    for (final Object? entry in rows) {
      if (entry is Map<String, Object?>) {
        final Object? name = entry['name'];
        final Object? id = entry['id'];
        if (name is String && id != null) {
          ids[name] = id.toString();
        }
      }
    }
    return _Coordinator(ids);
  }

  /// The OPENINGS of the keys the coordinator would still redeem for user [uid], or null when it
  /// did not answer.
  ///
  /// **OPENINGS AND NOT KEYS.** The listing prints `key` as the credential's first characters —
  /// 27 where the whole is 88 — and only `create` ever answers with the whole of one. So what comes
  /// back here decides WHETHER a key still stands, never WHAT it is: the only place a credential
  /// lives is the file this step wrote, and it is matched against these by its opening.
  ///
  /// Redeemable means listed, not yet used, and not past its expiration. An expiration that cannot
  /// be read counts as NOT past — doubt about a timestamp must never be read as "the key is dead",
  /// because a dead reading here is what makes a run mint a second live credential beside the
  /// first.
  Future<List<String>?> _usableKeys(StepContext context, String uid) async {
    final List<String> admin = _filled(context, invocation);
    final CommandResult listed = await context.shell.run(
      Command.observing(
        admin.first,
        // NO USER FLAG. The coordinator's `preauthkeys list` takes none — it lists every key there
        // is, and which user each belongs to is a field of the entry. Asked with one it answers
        // "unknown flag: --user" and exits 1, which this step then reports as the surface having
        // stopped answering (measured against headscale v0.29.2 on 2026-08-29, on the first slave
        // an installation ever added). `create` below still takes it; only the listing lost it.
        arguments: <String>[...admin.sublist(1), 'preauthkeys', 'list', '-o', 'json'],
        elevated: needsRoot,
      ),
    );
    if (listed.exitCode != 0) {
      return null;
    }
    final List<Object?>? rows = _rowsOf(listed.stdout);
    if (rows == null) {
      return null;
    }
    final List<String> usable = <String>[];
    for (final Object? entry in rows) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      // WHOSE KEY IT IS, read off the entry — the listing carries every user's, so a step that took
      // them all would hand one machine the credential minted for another.
      final Object? owner = entry['user'];
      final Object? ownerId = owner is Map<String, Object?> ? owner['id'] : null;
      if (ownerId == null || ownerId.toString() != uid) {
        continue;
      }
      final Object? key = entry['key'];
      if (key is! String || key.isEmpty || entry['used'] == true) {
        continue;
      }
      final DateTime? until = _instant(entry['expiration']);
      if (until != null && !until.isAfter(context.clock.now().toUtc())) {
        continue;
      }
      usable.add(key);
    }
    return usable;
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        argv.first,
        arguments: argv.sublist(1),
        elevated: needsRoot,
        timeout: _callBudget,
      ),
    );
    if (answer.exitCode != 0) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }

  /// The rows of a listing, or null where the surface did not answer at all.
  ///
  /// **AN EMPTY LISTING IS AN ANSWER, AND IT IS THE FIRST ONE EVERY INSTALLATION GIVES.** The
  /// coordinator writes JSON `null` for a listing with nothing in it — a fresh installation's user
  /// list and a fresh user's key list alike — so reading that as silence reads "there is nobody
  /// yet" as "there is nothing there". Measured on apps3 (2026-08-29): `users list -o json` answered
  /// `null` at exit 0, and the run stopped saying the admin surface had not answered, on the very
  /// first slave an installation ever adds.
  ///
  /// **ONE READING FOR BOTH LISTINGS.** The key listing had learned this and the user listing had
  /// not, which is how a step comes to believe two different things about one surface.
  ///
  /// Silence is a non-zero exit — the caller's to judge — or output that is neither a list nor that
  /// empty answer.
  static List<Object?>? _rowsOf(String stdout) {
    final String body = stdout.trim();
    if (body.isEmpty || body == 'null') {
      return const <Object?>[];
    }
    final Object? decoded = _decoded(stdout);
    return decoded is List<Object?> ? decoded : null;
  }

  /// A moment the coordinator states, or null where it states none this can read.
  ///
  /// **IT WRITES A PAIR AND NOT A TIMESTAMP**: `{"seconds": …, "nanos": …}`, seconds since the
  /// epoch — the shape its protocol carries. Read as a string this is not a string at all, so the
  /// check simply did not run, and an EXPIRED key was handed back as one the coordinator would
  /// still redeem (headscale v0.29.2, measured 2026-08-29). A string is still accepted, because a
  /// coordinator that states one is stating the same fact.
  ///
  /// Nanoseconds are dropped: what this decides is whether a moment has passed, and no key's life
  /// is measured that finely.
  static DateTime? _instant(Object? stated) {
    if (stated is String && stated.isNotEmpty) {
      return DateTime.tryParse(stated);
    }
    if (stated is Map<String, Object?>) {
      final Object? seconds = stated['seconds'];
      final int? epoch = seconds is int ? seconds : int.tryParse(seconds?.toString() ?? '');
      if (epoch != null) {
        return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      }
    }
    return null;
  }

  /// [text] as JSON, or null when it is not.
  static Object? _decoded(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// The coordinator's users, as the one lookup every admin verb starts from: the id is what every
/// other subcommand takes, and the name is only the lookup key.
final class _Coordinator {
  const _Coordinator(this._ids);

  final Map<String, String> _ids;

  /// The user id standing under [name], or null when the coordinator holds no such user.
  String? idOf(String name) => _ids[name];
}

/// Whether [held] is a WHOLE key the coordinator still redeems, told from the openings it lists.
///
/// **LONGER THAN THE OPENING IT MATCHES, and that is the whole of the distinction.** The listing
/// prints a key's first characters; a credential is that and much more. An opening trivially begins
/// with itself, so a file that came to hold one — written by a run that took the listing for a
/// credential — would be handed back for ever, and the machine refused every time with "key too
/// short". Length is what tells the two apart, and it is the coordinator's own: it refuses anything
/// under 77 characters after the prefix.
bool _isWholeKey(String held, Iterable<String> openings) =>
    held.isNotEmpty && openings.any((String o) => held.length > o.length && held.startsWith(o));
