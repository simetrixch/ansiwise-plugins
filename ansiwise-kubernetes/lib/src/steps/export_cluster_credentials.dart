import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Hands another machine's manager what it needs to drive THIS cluster: the address its API answers
/// on, the authority that signs its serving certificate, and one long-lived account token per named
/// account — one JSON file, readable by this account alone.
///
/// **Why a file and not output.** A run's record keeps output, and these tokens are standing
/// credentials into the cluster — one of them typically administrative. The caller reads the file,
/// carries the values on, and removes it; the file is the ONLY way they leave this step, exactly as
/// a minted network credential leaves its own step.
///
/// **Why the ADDRESS is an answer and never measured.** The address that matters is the one the
/// OTHER side dials, and this machine cannot know it: a machine on a private network has that
/// network's address and its public one, and picking between them here plants an unreachable
/// address that fails fifteen minutes later on the other machine, as a network fault. The caller —
/// who writes the same address into everything else that dials this cluster — states it, so both
/// sides hold ONE spelling.
///
/// **The token secrets are the legacy long-lived kind, populated by the cluster itself.** A token
/// minted per-request expires; what a standing registration needs is the token the cluster's own
/// controller writes into an annotated Secret, together with the cluster authority. That population
/// takes a moment after the Secret is applied, so the write waits for it, bounded.
final class ExportClusterCredentials extends ReversibleStep<bool> {
  /// Writes the credentials of the accounts behind [tokens] into the file at [filePath].
  const ExportClusterCredentials({
    required this.namespace,
    required this.tokens,
    required this.serverAnswer,
    required this.filePath,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory ExportClusterCredentials.fromArguments(Arguments arguments) => ExportClusterCredentials(
    namespace: arguments.text('namespace'),
    tokens: arguments.textList('tokens'),
    serverAnswer: arguments.text('server_answer'),
    filePath: arguments.text('file_path'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the long-lived token Secrets stand in',
    ),
    ArgumentSpec(
      name: 'tokens',
      kind: ArgumentKind.textList,
      describes:
          'each credential of the file as <field>=<secret name>: the field the file carries the '
          'token under, and the annotated service-account-token Secret the cluster populates it '
          'into. The file also always carries "server" and "caData" — the address the caller '
          'stated and the cluster authority the token controller writes beside every token',
    ),
    ArgumentSpec(
      name: 'server_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer that holds the address the OTHER side dials this cluster\'s API '
          'on, scheme and port included. Stated and never measured: a machine with a private '
          'address and a public one cannot know which of them the other side routes to, and a '
          'wrong pick fails on the other machine, minutes later, as a network fault',
    ),
    ArgumentSpec(
      name: 'file_path',
      kind: ArgumentKind.text,
      describes:
          'where the credentials are put for the caller, readable by this account alone — the '
          'caller reads it, carries the values on, and removes it; the file is the ONLY way the '
          'tokens leave this step',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The token Secrets this reads are applied by an earlier row of the same program, so in the two
  /// modes that change nothing this step reports what it would do rather than failing on Secrets
  /// nobody made yet.
  @override
  bool get restsOnAnEarlierStep => true;

  /// The namespace the token Secrets stand in.
  final String namespace;

  /// Each credential as `<field>=<secret name>`.
  final List<String> tokens;

  /// The name of the answer that holds the address the other side dials.
  final String serverAnswer;

  /// Where the credentials are put for the caller.
  final String filePath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// The file's mode: readable by its owner alone, because it holds standing credentials into the
  /// cluster.
  static const int _fileMode = 0x180;

  /// How long the write waits for the cluster's controller to populate a token Secret, and how
  /// often it looks. The population is seconds on a healthy cluster; a minute of it not happening
  /// is a controller that is not going to.
  static const int _populationAttempts = 30;

  /// The pause between two looks at an unpopulated Secret.
  static const Duration _populationPause = Duration(seconds: 2);

  @override
  Future<CheckResult> check(StepContext context) async {
    if (_malformedPair() case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? composed = await _composed(context, patient: false);
    if (composed == null) {
      return const CheckResult.ready();
    }
    if (await context.files.exists(filePath) && await context.files.read(filePath) == composed) {
      return CheckResult.satisfied(
        '$filePath already holds what the cluster hands out for these accounts',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // What the file would hold is left out of the plan. It is a set of standing credentials into
    // the cluster, and a plan is read by a person and reaches the record.
    final bool exists = await context.files.exists(filePath);
    return StepPlan.diff(
      filePath,
      before: exists ? '<the credentials that are there now>' : '',
      after: '<the address, the cluster authority, and one token per named account>',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    if (_malformedPair() case final String refusal) {
      throw StateError(refusal);
    }
    final String? composed = await _composed(context, patient: true);
    if (composed == null) {
      throw StateError(
        'a token Secret named in this row is still unpopulated after '
        '${_populationAttempts * _populationPause.inSeconds} seconds — the cluster\'s own '
        'controller writes the token, so read that controller\'s state; the Secrets themselves '
        'are applied by an earlier row',
      );
    }
    await context.files.write(filePath, composed, mode: _fileMode);
  }

  /// Whether the file was already there, read before the apply.
  ///
  /// A file that was there stays through an undo — this run did not put it there, and its content
  /// belongs to whoever did. One this run created is taken away, so an unwound run leaves no
  /// credential file lying around for nobody.
  @override
  Future<bool> capture(StepContext context) => context.files.exists(filePath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(filePath);
  }

  /// The whole file as it would be written, or null while a token is not there to be read.
  ///
  /// One composition for the check and the write alike, deterministic in its field order, which is
  /// what lets the check compare the file byte for byte. [patient] is the write's side: it waits,
  /// bounded, for the cluster's controller to populate a Secret the check would simply report as
  /// not ready yet.
  Future<String?> _composed(StepContext context, {required bool patient}) async {
    final String? server = context.answers.optionalText(serverAnswer);
    if (server == null || server.isEmpty) {
      return null;
    }
    final Map<String, String> fields = <String, String>{};
    String? authority;
    for (final String declared in tokens) {
      final int equals = declared.indexOf('=');
      if (equals <= 0) {
        // Unreachable: the pair refusal is answered before composing, by check and apply alike.
        return null;
      }
      final String field = declared.substring(0, equals).trim();
      final String secret = declared.substring(equals + 1).trim();
      final _TokenSecret? read = await _tokenSecret(context, secret, patient: patient);
      if (read == null) {
        return null;
      }
      fields[field] = read.token;
      authority ??= read.authority;
    }
    if (authority == null) {
      return null;
    }
    final Map<String, Object?> blob = <String, Object?>{
      'server': server,
      'caData': authority,
      ...fields,
    };
    return '${jsonEncode(blob)}\n';
  }

  /// Why the token declarations cannot be read, or null when every one is a pair.
  String? _malformedPair() {
    for (final String declared in tokens) {
      if (declared.indexOf('=') <= 0) {
        return '"$declared" is not a <field>=<secret name> pair';
      }
    }
    return null;
  }

  /// The decoded token and the still-encoded authority of the Secret [name], or null while the
  /// cluster's controller has not populated it.
  Future<_TokenSecret?> _tokenSecret(
    StepContext context,
    String name, {
    required bool patient,
  }) async {
    for (int attempt = 0; ; attempt++) {
      final CommandResult found = await context.shell.run(
        kubectl.observing(<String>['-n', namespace, 'get', 'secret', name, '-o', 'json']),
      );
      if (found.exitCode == 0) {
        final Object? decoded = _decoded(found.stdout);
        final Object? data = decoded is Map<String, Object?> ? decoded['data'] : null;
        if (data is Map<String, Object?>) {
          final Object? token = data['token'];
          final Object? authority = data['ca.crt'];
          if (token is String && token.isNotEmpty && authority is String && authority.isNotEmpty) {
            // The token is stored encoded and presented plain; the authority stays encoded,
            // because that is the form everything that trusts a cluster consumes it in.
            return _TokenSecret(
              token: utf8.decode(base64Decode(token)).trim(),
              authority: authority.replaceAll(RegExp(r'\s'), ''),
            );
          }
        }
      }
      if (!patient || attempt >= _populationAttempts) {
        return null;
      }
      await context.clock.sleep(_populationPause);
    }
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

/// What one populated token Secret hands out: the token, plain, and the authority, still encoded.
final class _TokenSecret {
  const _TokenSecret({required this.token, required this.authority});

  /// The account's long-lived token, decoded.
  final String token;

  /// The cluster authority, base64-encoded as every reader of it expects.
  final String authority;
}
