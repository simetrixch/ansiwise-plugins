import 'dart:async';
import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// Exchanges one complete secret entry with a producer over private process input and output.
final class VaultKvEntryFromCommand extends IrreversibleStep {
  /// Names the producer, the complete entry it owns and optional answer inputs.
  const VaultKvEntryFromCommand({
    required this.repository,
    required this.mount,
    required this.path,
    required this.fields,
    required this.producer,
    required this.layout,
    this.fieldsFromAnswers = const <String>[],
    this.kubectl = const Kubectl(),
  });

  /// Builds the exchange from a program row.
  factory VaultKvEntryFromCommand.fromArguments(Arguments args) => VaultKvEntryFromCommand(
    repository: args.text('repository'),
    mount: args.text('mount'),
    path: args.text('path'),
    fields: args.textList('fields'),
    producer: args.text('producer'),
    fieldsFromAnswers: args.textList('fields_from_answers'),
    layout: VaultLayout.fromArguments(args),
    kubectl: Kubectl.fromArguments(args),
  );

  /// The row names fields and files, never credentials.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout holding the Vault profile and credential layout',
    ),
    ArgumentSpec(name: 'mount', kind: ArgumentKind.text, describes: 'the key-value mount'),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the complete entry this producer owns',
    ),
    ArgumentSpec(
      name: 'producer',
      kind: ArgumentKind.text,
      describes: 'the non-secret Bash script implementing check and apply exchanges',
    ),
    ArgumentSpec(
      name: 'fields',
      kind: ArgumentKind.textList,
      describes: 'every field the complete producer result must carry',
    ),
    ArgumentSpec(
      name: 'fields_from_answers',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes: 'optional inputs as field=answer; missing answers preserve existing credentials',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    ...VaultLayout.arguments,
  ];

  /// The checkout holding the Vault layout.
  final String repository;

  /// The key-value mount.
  final String mount;

  /// The entry before the layout fills its slots.
  final String path;

  /// The complete set of fields this producer owns.
  final List<String> fields;

  /// The non-secret application producer.
  final String producer;

  /// Optional inputs named field=answer.
  final List<String> fieldsFromAnswers;

  /// The existing Vault layout.
  final VaultLayout layout;

  /// The cluster invocation handed to the producer.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'Issued credentials may already be in use; no secret entry is retained in a checkpoint';

  @override
  Future<CheckResult> check(StepContext context) async {
    try {
      final _Entry entry = await _read(context);
      final Map<String, Object?> answer = await _exchange(context, entry, apply: false);
      if (answer['satisfied'] is! bool) {
        throw const _ExchangeRefused('the credential producer returned no check verdict');
      }
      if (answer['satisfied'] == false) return const CheckResult.ready();
      if (!_complete(entry.values) ||
          _inputs(context).entries.any(
            (MapEntry<String, String> field) => entry.values?[field.key] != field.value,
          )) {
        throw const _ExchangeRefused(
          'the credential producer reported satisfied without a complete matching entry',
        );
      }
      return CheckResult.satisfied('${entry.dataPath} holds the verified credential fields');
    } on CommandFailed catch (error) {
      return CheckResult.blocked(
        'the credential producer check failed with exit ${error.exitCode}',
      );
    } on _ExchangeRefused catch (error) {
      return CheckResult.blocked(error.message);
    } on Exception {
      return const CheckResult.blocked('the credential exchange could not read Vault or Forgejo');
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile profile = await vaultProfileFrom(context, repository, layout: layout);
    if (profile.refusal case final String refusal) return StepPlan.notKnownYet(refusal);
    final ArgumentText target = profile.forThisInstallation(context, path);
    if (target.refusal case final String refusal) return StepPlan.notKnownYet(refusal);
    return StepPlan.request(
      'POST',
      '${profile.url}/v1/$mount/data/${target.value}',
      body: 'the fields ${fields.join(', ')}',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Entry entry = await _read(context);
    final Map<String, Object?> result = await _exchange(context, entry, apply: true);
    if (!_complete(result)) {
      throw const _ExchangeRefused('the credential producer returned an invalid complete entry');
    }
    if (!_same(entry.values, result)) {
      final HttpAnswer written = await context.http.send(
        vaultWrite(
          entry.url,
          entry.dataPath,
          token: entry.token,
          body: <String, Object?>{
            'data': result,
            'options': <String, int>{'cas': entry.version},
          },
        ),
      );
      if (!written.ok) {
        throw _ExchangeRefused(
          'writing ${entry.dataPath} answered HTTP ${written.status}; response withheld',
        );
      }
    }
    final _Entry verified = await _read(context);
    if (!_same(verified.values, result)) {
      throw _ExchangeRefused('${entry.dataPath} did not retain the complete credential entry');
    }
  }

  Map<String, String> _inputs(StepContext context) {
    final Map<String, String> inputs = <String, String>{};
    for (final String mapping in fieldsFromAnswers) {
      final int equals = mapping.indexOf('=');
      if (equals <= 0 ||
          equals == mapping.length - 1 ||
          !fields.contains(mapping.substring(0, equals))) {
        throw const _ExchangeRefused(
          'fields_from_answers must name a declared field and an answer',
        );
      }
      final String field = mapping.substring(0, equals);
      final String? value = context.answers.optionalText(mapping.substring(equals + 1));
      if (value != null) {
        if (value.isEmpty) throw _ExchangeRefused('the answer for $field is empty');
        inputs[field] = value;
      }
    }
    return inputs;
  }

  bool _complete(Map<String, Object?>? values) =>
      values != null &&
      values.length == fields.length &&
      fields.every(
        (String field) => values[field] is String && (values[field]! as String).isNotEmpty,
      );

  bool _same(Map<String, Object?>? left, Map<String, Object?> right) =>
      _complete(left) && fields.every((String field) => left![field] == right[field]);

  Future<Map<String, Object?>> _exchange(
    StepContext context,
    _Entry entry, {
    required bool apply,
  }) async {
    final List<String> argv = <String>[
      'bash',
      producer,
      apply ? '--apply' : '--check',
      '--',
      ...kubectl.argv(const <String>[]),
    ];
    final CommandResult result;
    try {
      result = await context.shell.run(
        Command.detailed(
          argv.first,
          arguments: argv.sublist(1),
          stdin: jsonEncode(<String, Object?>{'entry': entry.values, 'inputs': _inputs(context)}),
          observes: !apply,
          elevated: kubectl.elevated,
          secretOutput: true,
          timeout: const Duration(seconds: 120),
        ),
      );
    } on TimeoutException {
      throw const _ExchangeRefused('the credential producer exceeded its 120 second deadline');
    }
    if (!result.ok) throw CommandFailed.withheldOutput(argv: argv, exitCode: result.exitCode);
    final Map<String, Object?>? decoded = decodedObject(result.stdout);
    if (decoded == null) {
      throw const _ExchangeRefused(
        'the credential producer returned no JSON object; output withheld',
      );
    }
    return decoded;
  }

  Future<_Entry> _read(StepContext context) async {
    if (fields.isEmpty ||
        fields.any((String field) => field.isEmpty) ||
        fields.toSet().length != fields.length) {
      throw const _ExchangeRefused('the credential exchange requires distinct nonempty fields');
    }
    final VaultProfile profile = await vaultProfileFrom(context, repository, layout: layout);
    if (profile.refusal case final String refusal) throw _ExchangeRefused(refusal);
    final ArgumentText target = profile.forThisInstallation(context, path);
    if (target.refusal case final String refusal) throw _ExchangeRefused(refusal);
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) throw _ExchangeRefused(refusal);
    final String dataPath = '$mount/data/${target.value}';
    final VaultReading read = readingOf(
      await context.http.send(vaultRead(profile.url!, dataPath, token: token.value)),
      path: dataPath,
    );
    if (read case final VaultUnreadable refused) throw _ExchangeRefused(refused.because);
    Map<String, Object?>? values;
    int version = 0;
    if (read is VaultHeld) {
      final Object? data = read.data['data'], metadata = read.data['metadata'];
      if (data is! Map<String, Object?> ||
          metadata is! Map<String, Object?> ||
          metadata['version'] is! int ||
          (metadata['version']! as int) < 1) {
        throw _ExchangeRefused('$dataPath returned no readable versioned entry');
      }
      values = data;
      version = metadata['version']! as int;
    } else {
      // A deleted latest version reads as absent, yet Vault keeps its number and refuses a write
      // checked against 0 for as long as the entry's metadata stands. Only no metadata is no entry.
      final String metadataPath = '$mount/metadata/${target.value}';
      final VaultReading kept = readingOf(
        await context.http.send(vaultRead(profile.url!, metadataPath, token: token.value)),
        path: metadataPath,
      );
      if (kept case final VaultUnreadable refused) throw _ExchangeRefused(refused.because);
      if (kept is VaultHeld) {
        final Object? current = kept.data['current_version'];
        if (current is! int || current < 1) {
          throw _ExchangeRefused('$metadataPath returned no readable current version');
        }
        version = current;
      }
    }
    return _Entry(profile.url!, dataPath, token.value!, values, version);
  }
}

final class _Entry {
  const _Entry(this.url, this.dataPath, this.token, this.values, this.version);
  final String url, dataPath, token;
  final Map<String, Object?>? values;
  final int version;
}

final class _ExchangeRefused implements Exception {
  const _ExchangeRefused(this.message);
  final String message;
  @override
  String toString() => message;
}
