import 'package:ansiwise_core/ansiwise_core.dart';

import 'install_authorized_key.dart';

/// The one machine and the one key a row means, or why it means none.
///
/// **Both reach the row as ANSWERS, and nothing here looks a key up.** A scan of the machine would
/// record whatever answered, and a key nobody proved is exactly what a host key check exists to
/// refuse. The caller holds the proof, because it only got this key out of a connection that was
/// refused unless the key matched what it had recorded, and it hands the result over.
///
/// **A public key is not a secret.** It is what a machine hands to everybody who connects, so
/// nothing here is redacted and the value may stand in a plan an operator reads.
final class KnownHost {
  /// Records the machine [host] and its key, as the one `<type> <base64>` pair a file line carries.
  const KnownHost.of({
    required String this.host,
    required String this.keyType,
    required String this.keyBlob,
  }) : refusal = null;

  /// Records that the answers name no machine and key, because [refusal].
  const KnownHost.unnamed(String this.refusal) : host = null, keyType = null, keyBlob = null;

  /// Reads the machine and the key out of the answers [hostAnswer] and [keyAnswer] name.
  factory KnownHost.fromAnswers(
    StepContext context, {
    required String hostAnswer,
    required String keyAnswer,
  }) {
    final String? host = context.answers.optionalText(hostAnswer)?.trim();
    if (host == null || host.isEmpty) {
      return KnownHost.unnamed(
        'this run holds no answer "$hostAnswer", and the machine is read from it',
      );
    }
    if (!_hostName.hasMatch(host)) {
      return KnownHost.unnamed(
        'the answer "$hostAnswer" is "$host", which is not a plain host name — a known_hosts line '
        'reads a comma, a star, a question mark or a leading bang as a pattern, and a pattern would '
        'trust this key for machines nobody named',
      );
    }
    final String? held = context.answers.optionalText(keyAnswer)?.trim();
    if (held == null || held.isEmpty) {
      return KnownHost.unnamed(
        'this run holds no answer "$keyAnswer", and the key is read from it',
      );
    }
    final List<String> fields = held.split(RegExp(r'\s+'));
    if (held.contains('\n') ||
        fields.length < 2 ||
        !_keyType.hasMatch(fields[0]) ||
        !_base64.hasMatch(fields[1])) {
      return KnownHost.unnamed(
        'the answer "$keyAnswer" is not one public key line — it is "<type> <base64>", the first two '
        'fields of what the machine\'s own .pub file holds',
      );
    }
    return KnownHost.of(host: host, keyType: fields[0], keyBlob: fields[1]);
  }

  static final RegExp _hostName = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$');
  static final RegExp _keyType = RegExp(r'^[a-z][a-z0-9@.-]*$');
  static final RegExp _base64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

  /// The machine's name, as a client dials it, or null where the answers name none.
  final String? host;

  /// The key's algorithm, as the first field of its public line, or null where there is none.
  final String? keyType;

  /// The key itself, base64, as the second field of its public line, or null where there is none.
  final String? keyBlob;

  /// Why the answers name no machine and key, or null when they do.
  final String? refusal;

  /// The line a `known_hosts` file carries for this machine and key.
  String get line => '$host $keyType $keyBlob';
}

/// What `known_hosts` held before this step, as far as the step could look.
///
/// A record naming its own refusal, because an undo is told what to do by this value and a reading
/// that could not be taken must not look like a file that was not there: the first leaves the file
/// as it stands, the second makes the undo delete it.
final class KnownHostsBefore {
  /// Records a reading that was taken: [content] is the file, or null where it was not there.
  const KnownHostsBefore.read(this.content) : measured = true;

  /// Records a reading that could not be taken.
  const KnownHostsBefore.unread() : content = null, measured = false;

  /// What the file held, or null where it was not there or the reading was not taken.
  final String? content;

  /// Whether the reading was taken at all.
  final bool measured;
}

/// Puts one machine's host key into the `known_hosts` of the account the run names, so that account's
/// `ssh` to that machine passes its host key check instead of refusing the key.
///
/// **The file ends up holding exactly one trusted key for the machine: the one the row names.** A
/// machine that was rebuilt presents a new key, and an old line left beside the new one would keep
/// trusting a key nobody can prove any more. Every other line is kept byte for byte.
///
/// **Which lines belong to the machine is `ssh-keygen`'s to say, and the file is rewritten here.**
/// `known_hosts` may hold a name in plain form or hashed (`|1|salt|hash`), and only the tool that
/// hashed it can tell whether a hashed line is this machine. It runs as `-F`, which only reads and
/// names the matching line numbers; `-R` would do the removing itself and leave a `known_hosts.old`
/// beside the file on every run, and it would be a command that a dry run has to refuse. A plain
/// name matches port 22 only: a `[name]:port` line is another machine's entry and is not touched.
///
/// **A marker line (`@revoked`, `@cert-authority`) is somebody's deliberate statement and is left
/// alone**, and it does not count as the machine's key either.
///
/// **The account is the one running this step, and nothing is elevated.** The file is the
/// account's own. A run that is neither the account nor root cannot read `.ssh`, which is `0700`,
/// and says so rather than reading the file as absent.
final class InstallKnownHost extends ReversibleStep<KnownHostsBefore> {
  /// Installs the key of the machine the two answers name.
  const InstallKnownHost({required this.hostAnswer, required this.keyAnswer});

  /// Builds the step from what the program gave it.
  factory InstallKnownHost.fromArguments(Arguments arguments) => InstallKnownHost(
    hostAnswer: arguments.text('host_answer'),
    keyAnswer: arguments.text('host_public_key_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'host_answer',
      kind: ArgumentKind.answerName,
      describes: 'the name of the answer holding the machine, as the account\'s ssh dials it',
    ),
    ArgumentSpec(
      name: 'host_public_key_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the machine\'s public host key, as "<type> <base64>" — a '
          'key the caller proved, never one this step fetches',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares: the account alone.
  /// The machine and the key are the row's to name, so they are arguments of kind
  /// [ArgumentKind.answerName] and the program is held to declaring what it writes there.
  static const List<String> answers = InstallAuthorizedKey.answers;

  /// The name of the answer holding the machine.
  final String hostAnswer;

  /// The name of the answer holding the machine's key.
  final String keyAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Reading reading = await _read(context);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (reading.content == null) {
      return const CheckResult.ready();
    }
    return reading.holdsKey && reading.removed.isEmpty
        ? CheckResult.satisfied('${reading.path} already holds the key of ${reading.wanted.host}')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Reading reading = await _read(context);
    if (reading.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.diff(reading.path, before: reading.content ?? '', after: reading.after);
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Reading reading = await _read(context);
    if (reading.refusal case final String refusal) {
      throw StateError(refusal);
    }
    await context.files.createDirectory(reading.directory, mode: _sshDirectory);
    await context.files.write(reading.path, reading.after, mode: _knownHostsFile);
  }

  @override
  Future<KnownHostsBefore> capture(StepContext context) async {
    final _Reading reading = await _read(context);
    return reading.refusal == null
        ? KnownHostsBefore.read(reading.content)
        : const KnownHostsBefore.unread();
  }

  @override
  Future<void> undo(StepContext context, KnownHostsBefore captured) async {
    if (!captured.measured) {
      context.log.warn(
        'what this account\'s known_hosts held before could not be read, so an undo leaves it as it '
        'stands rather than put back a file this run never saw',
      );
      return;
    }
    final ({String? home, String? refusal}) account = await InstallAuthorizedKey.homeOf(context);
    if (account.refusal case final String refusal) {
      context.log.warn(
        'known_hosts was left as it stands, because the account could not be read: $refusal',
      );
      return;
    }
    final String path = '${account.home!}/.ssh/known_hosts';
    if (captured.content case final String content) {
      await context.files.write(path, content, mode: _knownHostsFile);
    } else if (await context.files.exists(path)) {
      await context.files.delete(path);
    }
  }

  /// What the account's `known_hosts` holds for the machine, and what it has to become, or why it
  /// could not be read.
  Future<_Reading> _read(StepContext context) async {
    final KnownHost wanted = KnownHost.fromAnswers(
      context,
      hostAnswer: hostAnswer,
      keyAnswer: keyAnswer,
    );
    if (wanted.refusal case final String refusal) {
      return _Reading.refused(refusal);
    }
    final ({String? home, String? refusal}) account = await InstallAuthorizedKey.homeOf(context);
    if (account.refusal case final String refusal) {
      return _Reading.refused(refusal);
    }
    final String directory = '${account.home!}/.ssh';
    final String path = '$directory/known_hosts';
    final ({List<String>? names, String? refusal}) listed = await InstallAuthorizedKey.namesIn(
      context,
      directory,
      elevated: false,
    );
    if (listed.refusal case final String refusal) {
      return _Reading.refused(refusal);
    }
    if (listed.names == null || !listed.names!.contains('known_hosts')) {
      return _Reading.settled(
        wanted: wanted,
        directory: directory,
        content: null,
        lines: const <int>[],
      );
    }
    final CommandResult found = await context.shell.run(
      Command.observing('ssh-keygen', arguments: <String>['-F', wanted.host!, '-f', path]),
    );
    // Exit 1 is "no line names this machine"; anything else is a question it could not answer, and
    // a file it could not read must not be taken for one with no entry.
    if (!found.ok && found.exitCode != _notFound) {
      return _Reading.refused(
        '$path could not be searched for ${wanted.host}, so what it holds for that machine was not '
        'measured — ssh-keygen exited ${found.exitCode}${InstallAuthorizedKey.said(found)}',
      );
    }
    return _Reading.settled(
      wanted: wanted,
      directory: directory,
      content: await context.files.read(path),
      lines: found.ok ? _lineNumbers(found.stdout) : const <int>[],
    );
  }

  /// The line numbers `ssh-keygen -F` names, one `# Host <name> found: line <n>` header per match.
  static List<int> _lineNumbers(String output) => <int>[
    for (final RegExpMatch match in _foundHeader.allMatches(output)) int.parse(match.group(1)!),
  ];

  static final RegExp _foundHeader = RegExp(r'^# Host .* found: line (\d+)\b', multiLine: true);

  /// What `ssh-keygen -F` exits with when no line names the machine.
  static const int _notFound = 1;

  /// `0700` — the directory ssh keeps its files in, which it refuses to share.
  static const int _sshDirectory = 0x1c0;

  /// `0600` — the account is the only one that reads its own `known_hosts`, so the narrowest mode
  /// is never wrong for it and no other account is let in by a write of this step.
  static const int _knownHostsFile = 0x180;
}

/// What one reading of `known_hosts` found, and the file it makes of it.
final class _Reading {
  const _Reading.refused(String this.refusal)
    : wanted = const KnownHost.unnamed(''),
      directory = '',
      content = null,
      removed = const <int>{},
      holdsKey = false,
      heldLines = const <String>[];

  /// Judges [lines], the numbers `ssh-keygen -F` named in [content], against [wanted].
  factory _Reading.settled({
    required KnownHost wanted,
    required String directory,
    required String? content,
    required List<int> lines,
  }) {
    final List<String> held = _split(content ?? '');
    final Set<int> removed = <int>{};
    bool holdsKey = false;
    for (final int number in lines) {
      if (number > held.length) {
        return _Reading.refused(
          '$directory/known_hosts changed while it was searched for ${wanted.host}: ssh-keygen named '
          'line $number and the file has ${held.length}',
        );
      }
      final String line = held[number - 1].trim();
      // A marker line is another party's statement about the machine, never this step's to remove.
      if (line.startsWith('@')) {
        continue;
      }
      final List<String> fields = line.split(RegExp(r'\s+'));
      if (fields.length >= 3 && fields[1] == wanted.keyType && fields[2] == wanted.keyBlob) {
        holdsKey = true;
      } else {
        removed.add(number);
      }
    }
    return _Reading._(
      wanted: wanted,
      directory: directory,
      content: content,
      removed: removed,
      holdsKey: holdsKey,
      heldLines: held,
    );
  }

  const _Reading._({
    required this.wanted,
    required this.directory,
    required this.content,
    required this.removed,
    required this.holdsKey,
    required this.heldLines,
  }) : refusal = null;

  /// The lines of the file, without the empty one a final newline leaves.
  static List<String> _split(String content) {
    final List<String> lines = content.split('\n');
    if (lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  /// Why the file could not be read or the answers named no machine, or null.
  final String? refusal;

  /// The machine and the key the row means.
  final KnownHost wanted;

  /// The account's `.ssh` directory.
  final String directory;

  /// What the file holds, or null where it is not there.
  final String? content;

  /// The numbers of the lines that name the machine with another key, which the file loses.
  final Set<int> removed;

  /// Whether a line already names the machine with the wanted key.
  final bool holdsKey;

  /// The lines of the file, without the empty one a final newline leaves.
  final List<String> heldLines;

  /// The file's path.
  String get path => '$directory/known_hosts';

  /// The file once the old keys are gone and the wanted one stands: every other line untouched.
  String get after {
    final List<String> kept = <String>[
      for (int i = 0; i < heldLines.length; i++)
        if (!removed.contains(i + 1)) heldLines[i],
      if (!holdsKey) wanted.line,
    ];
    return kept.isEmpty ? '' : '${kept.join('\n')}\n';
  }
}
