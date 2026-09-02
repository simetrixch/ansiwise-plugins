import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Puts a certificate authority the cluster holds in a Secret into the machine's own trust store, so
/// that everything on this machine which speaks https to an address this cluster serves verifies it
/// the ordinary way.
///
/// **WHY THIS EXISTS AT ALL.** An installation that has not yet asked a public authority for its
/// certificates still has to be installable: the store mounts its certificate as a FILE and a pod
/// whose volume names a missing Secret never starts, so "no certificate" is not a weaker
/// installation, it is no installation. Such a cluster issues from an authority of its own — and
/// then every step that reaches one of its addresses is refused by a root the machine does not
/// have. Measured on a real machine with the engine at 0.7.4: against a certificate signed by
/// an authority present nowhere but that machine, a run ended `exit 1, 0 proven`; with the same
/// authority in `/etc/ssl/certs/ca-certificates.crt` and nothing else changed, `exit 0, 1 proven`.
/// The engine follows the machine, so putting the root there is the whole of what is needed, and no
/// row anywhere has to be told to accept anything.
///
/// **WHY NOT A FLAG ON THE ROWS INSTEAD.** The alternative is to let the rows that dial this
/// installation accept whatever certificate they are shown while it has no public one. There are
/// about fifty of them, the flag would have to come off every one of them again the day the
/// installation gets its real certificates, and a flag left behind is a row that never checks
/// anything and says nothing about it. Trusting one named authority is the same guarantee with an
/// end: the machine trusts exactly what its own cluster issues, and it stops trusting it when the
/// root is taken back out.
///
/// **THE BUNDLE IS READ, NOT ASSUMED.** Writing the root into the directory a machine collects roots
/// from does nothing by itself — a separate program rebuilds the bundle everything else reads, and
/// on a machine where that program is absent or refuses, the file lands and nothing trusts it. So
/// [bundlePath] is read back and has to carry the authority before this step is satisfied. Without
/// that the step would report a machine as trusting an authority it does not, which is the one
/// failure it exists to prevent.
final class TrustClusterAuthority extends ReversibleStep<bool> {
  /// Puts the authority in [field] of the Secret [secret] into [path] and rebuilds the trust store.
  const TrustClusterAuthority({
    required this.namespace,
    required this.secret,
    required this.field,
    required this.path,
    required this.refresh,
    required this.bundlePath,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory TrustClusterAuthority.fromArguments(Arguments arguments) => TrustClusterAuthority(
    namespace: arguments.text('namespace'),
    secret: arguments.text('secret'),
    field: arguments.text('field'),
    path: arguments.text('path'),
    refresh: arguments.textList('refresh'),
    bundlePath: arguments.text('bundle'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the Secret holding the authority stands in',
    ),
    ArgumentSpec(
      name: 'secret',
      kind: ArgumentKind.text,
      describes: 'the Secret the cluster keeps its own certificate authority in',
    ),
    ArgumentSpec(
      name: 'field',
      kind: ArgumentKind.text,
      describes:
          'which key of that Secret carries the authority, in the encoding a Secret stores values '
          'in. A Secret holding an issued certificate carries the authority beside it rather than '
          'as the certificate itself, and naming the wrong one puts a leaf where a root belongs',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'where on the machine the authority is put, which has to be inside the directory the '
          'machine collects roots from — the file itself is not what anything reads',
    ),
    ArgumentSpec(
      name: 'refresh',
      kind: ArgumentKind.textList,
      describes:
          'the command that rebuilds the bundle everything on this machine reads, run after the '
          'file is written and after it is taken away again',
    ),
    ArgumentSpec(
      name: 'bundle',
      kind: ArgumentKind.text,
      describes:
          'the file that command writes, read back so that this step is satisfied only where the '
          'machine actually trusts the authority and not merely where the file was placed',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The Secret is written by the certificate service after an earlier row applied the objects that
  /// ask for it, so in the two modes that change nothing this reports what it would do rather than
  /// failing on a Secret nobody has made yet.
  @override
  bool get restsOnAnEarlierStep => true;

  /// The namespace the Secret stands in.
  final String namespace;

  /// The Secret holding the authority.
  final String secret;

  /// Which key of it carries the authority.
  final String field;

  /// Where the authority is put on the machine.
  final String path;

  /// The command that rebuilds the machine's bundle.
  final List<String> refresh;

  /// The file that command writes.
  final String bundlePath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Readable by everything, because a root is what everything on the machine has to be able to
  /// read, and it is a public certificate and no part of a key.
  static const int _fileMode = 0x1A4;

  /// How long the write waits for the certificate service to put the authority in the Secret, and
  /// how often it looks. Issuing from an authority the cluster holds itself is immediate; a minute
  /// of it not happening is a service that is not going to.
  static const int _issueAttempts = 30;

  /// The pause between two looks at a Secret that is not there yet.
  static const Duration _issuePause = Duration(seconds: 2);

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? authority = await _authority(context, patient: false);
    if (authority == null) {
      return const CheckResult.ready();
    }
    if (!await _machineHolds(context, authority)) {
      return const CheckResult.ready();
    }
    return CheckResult.satisfied(
      'this machine trusts the authority $secret holds: it stands in $path and in $bundlePath',
    );
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final bool exists = await context.files.exists(path, elevated: kubectl.elevated);
    return StepPlan.diff(
      path,
      before: exists ? '<the authority that is there now>' : '',
      after: '<the authority $namespace/$secret holds, and $bundlePath rebuilt from it>',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? authority = await _authority(context, patient: true);
    if (authority == null) {
      throw StateError(
        '$namespace/$secret still carries no $field after '
        '${_issueAttempts * _issuePause.inSeconds} seconds — the certificate service writes it '
        'once the objects an earlier row applied ask it to, so read that service\'s state',
      );
    }
    await context.files.write(path, authority, mode: _fileMode, elevated: kubectl.elevated);
    await _rebuild(context);
    if (!await _machineHolds(context, authority)) {
      throw StateError(
        '$path was written and ${refresh.join(' ')} ran, and $bundlePath still does not carry the '
        'authority — everything on this machine that speaks to this cluster would go on refusing '
        'its certificate, so this is reported here rather than fifty steps later as a network fault',
      );
    }
  }

  /// Whether the authority was already on the machine, read before the apply.
  ///
  /// One that was there stays through an undo — this run did not put it there. One this run placed
  /// is taken away and the bundle rebuilt without it, because a machine left trusting an authority
  /// after the run that installed it was unwound trusts something nobody can account for.
  @override
  Future<bool> capture(StepContext context) =>
      context.files.exists(path, elevated: kubectl.elevated);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(path, elevated: kubectl.elevated);
    await _rebuild(context);
  }

  /// Runs the command that rebuilds the machine's bundle.
  Future<void> _rebuild(StepContext context) async {
    final CommandResult rebuilt = await context.shell.run(
      Command.detailed(
        refresh.first,
        arguments: refresh.skip(1).toList(),
        elevated: kubectl.elevated,
      ),
    );
    if (rebuilt.exitCode != 0) {
      throw StateError(
        '${refresh.join(' ')} ended ${rebuilt.exitCode}: ${rebuilt.stderr.trim()}\n'
        'the file at $path is placed and nothing reads it until that command succeeds',
      );
    }
  }

  /// The authority as it would stand on the machine, or null while the Secret does not carry it.
  ///
  /// [patient] is the write's side: it waits, bounded, for the certificate service to put the
  /// authority there, where the check simply reports it as not ready yet.
  Future<String?> _authority(StepContext context, {required bool patient}) async {
    for (int attempt = 0; ; attempt++) {
      final CommandResult found = await context.shell.run(
        kubectl.observing(<String>['-n', namespace, 'get', 'secret', secret, '-o', 'json']),
      );
      if (found.exitCode == 0) {
        if (_fieldOf(found.stdout) case final String stored) {
          // Stored encoded and put on the machine plain: the trust store is read by programs that
          // expect certificates the way a certificate is written, and one trailing newline is what
          // separates two of them in the bundle.
          final String decoded = utf8.decode(base64Decode(stored.replaceAll(RegExp(r'\s'), '')));
          return decoded.endsWith('\n') ? decoded : '$decoded\n';
        }
      }
      if (!patient || attempt >= _issueAttempts) {
        return null;
      }
      await context.clock.sleep(_issuePause);
    }
  }

  /// The still-encoded value of [field], or null where the Secret does not carry it.
  String? _fieldOf(String json) {
    final Object? decoded = _decoded(json);
    final Object? data = decoded is Map<String, Object?> ? decoded['data'] : null;
    if (data is! Map<String, Object?>) {
      return null;
    }
    final Object? stored = data[field];
    return stored is String && stored.isNotEmpty ? stored : null;
  }

  /// Whether the machine trusts [authority]: the file carries it AND the rebuilt bundle does.
  ///
  /// Both, because either one alone is a machine that reports trust it does not have — a file in
  /// the collection directory that no rebuild has taken up, or a bundle carrying an authority whose
  /// source file is gone and which the next rebuild therefore drops.
  Future<bool> _machineHolds(StepContext context, String authority) async {
    if (!await context.files.exists(path, elevated: kubectl.elevated)) {
      return false;
    }
    if (await context.files.read(path, elevated: kubectl.elevated) != authority) {
      return false;
    }
    if (!await context.files.exists(bundlePath, elevated: kubectl.elevated)) {
      return false;
    }
    final String bundle = await context.files.read(bundlePath, elevated: kubectl.elevated);
    return bundle.contains(authority.trim());
  }

  /// [json] as a map, or null where the cluster answered something that is not one.
  Object? _decoded(String json) {
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }
}
