import 'package:ansiwise_api/ansiwise_api.dart';
import 'argument_text.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Writes one entry of the seed into Vault.
///
/// **No value is in the program file.** A program file names a field and the variable that holds its
/// value, and the values themselves live in the one hand-filled input of the installation. That is
/// what keeps a credential out of the tree, out of the run's own arguments and out of the plan an
/// operator reads before a run.
///
/// **This write is a plain put and not a create-only one, and the difference matters.** The seed
/// owns these paths and re-running it is how new values reach the workloads that read them. The
/// create-only writes of this platform belong to the cluster manager, on the paths a consumer or a
/// tenant owns, where a second write would rotate the keys of something already running. What this
/// program contributes there is the policy that makes that write possible without a read.
///
/// **A put of an empty object is a destructive write, not a no-op.** It replaces the entry with
/// nothing. So an entry left with no fields at all is skipped, and skipping it is the point: some of
/// these paths carry one field this program writes and one another writer owns, and writing what is
/// left would wipe the other writer's.
///
/// **A value that still carries the text marking it as unfilled is refused by name.** Every offender
/// at once, and never a prompt: reading a missing value from a terminal would put a credential
/// somewhere other than the file an operator fills, and a run started over a channel with no
/// terminal cannot answer at all.
final class VaultKvEntry extends IrreversibleStep {
  /// Writes the fields named in [fields] to [path] on [mount] of this installation's Vault.
  const VaultKvEntry({
    required this.repository,
    required this.mount,
    required this.path,
    required this.fields,
    required this.mint,
    required this.fieldsOwnedElsewhere,
  });

  /// Builds the step from what the program gave it.
  factory VaultKvEntry.fromArguments(Arguments arguments) => VaultKvEntry(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    fields: arguments.textList('fields'),
    mint: arguments.textList('mint'),
    fieldsOwnedElsewhere: arguments.textList('fields_owned_elsewhere'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile, the "
          "credential file Vault's root token was written to, and the hand-filled input the values "
          'are read out of',
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes: 'the key-value mount this entry is written on',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the entry, below the mount — beginning "$stagePlaceholder/" where the entry belongs to '
          "one stage's tree rather than to the stage-free build tier",
    ),
    ArgumentSpec(
      name: 'fields',
      kind: ArgumentKind.textList,
      describes:
          'each field of the entry as <field>=<VARIABLE>, naming the variable of the hand-filled '
          'input that holds its value — never the value',
    ),
    ArgumentSpec(
      name: 'mint',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the fields this run generates when the hand-filled input leaves them empty, so a value '
          'nobody can be asked for comes into being here and nowhere else',
    ),
    ArgumentSpec(
      name: 'fields_owned_elsewhere',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the fields another writer owns, which are left out rather than refused when their '
          'variable is still unfilled',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = vaultAnswers;

  /// The checkout this installation runs from.
  final String repository;

  /// The key-value mount.
  final String mount;

  /// The entry below it.
  final String path;

  /// Each field as `<field>=<VARIABLE>`.
  final List<String> fields;

  /// The fields this run generates when nothing supplies them.
  ///
  /// A credential nobody can be asked for — an OIDC client secret, the first administrator's
  /// password — has to come into being somewhere, and the answers template already says where: its
  /// own heading calls these values written back from what the install produced. This is that
  /// place, and there is only one of it, so a value that two components need is one value.
  final List<String> mint;

  /// The fields another writer owns.
  final List<String> fieldsOwnedElsewhere;

  @override
  String get irreversibleReason =>
      'a write here becomes the current value and pushes the previous one into a history ten deep; '
      'past that there is nothing to go back to, and removing the entry altogether destroys every '
      'version of it with no way to undelete';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';
    final String dataPath = _dataPath(entry.value ?? '');

    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final _Body wanted = await _wanted(context, dataPath);
    if (wanted.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (wanted.isEmpty) {
      return CheckResult.satisfied(
        'every field of $dataPath is owned by another writer and none of them is filled in here, '
        'so this writes nothing — an entry written with no fields replaces what is there with '
        'nothing',
      );
    }

    final HttpAnswer answer = await context.http.send(
      vaultRead(url, dataPath, token: token.value ?? ''),
    );
    if (isAbsent(answer)) {
      return const CheckResult.ready();
    }
    final Object? current = decodedData(answer.body)?['data'];
    if (current is! Map<String, Object?>) {
      return const CheckResult.ready();
    }

    for (final MapEntry<String, String> field in wanted.values.entries) {
      if (current[field.key] != field.value) {
        // The field, never the value. What is different is what an operator needs; what it is
        // different to is the credential.
        context.log.debug('$dataPath holds a different ${field.key}');
        return const CheckResult.ready();
      }
    }
    for (final String field in wanted.mint) {
      // A generated field is compared against nothing: there is no value to compare it to until
      // this run makes one, and making one to compare would BE the rotation this must not perform.
      // What is asked is only whether the entry already carries it.
      final Object? held = current[field];
      if (held is! String || held.isEmpty) {
        context.log.debug('$dataPath carries no $field yet');
        return const CheckResult.ready();
      }
    }
    return CheckResult.satisfied('$dataPath already holds what this run writes');
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final String dataPath = _dataPath(entry.value ?? '');
    final _Body wanted = await _wanted(context, dataPath);
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/$dataPath',
      body: wanted.isEmpty
          ? 'nothing — every field of this entry is owned elsewhere and unfilled here'
          : 'the fields ${<String>[...wanted.values.keys, ...wanted.mint].join(', ')}',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final String url = vault.url ?? '';
    final String dataPath = _dataPath(vault.forThisInstallation(context, path).value ?? '');
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    final _Body wanted = await _wanted(context, dataPath);
    if (wanted.isEmpty) {
      return;
    }

    // A write to this store replaces the whole entry, so what is already there has to be carried
    // forward. That is what makes a generated field create-only: a value the entry already holds is
    // written back unchanged, and only a field it does not hold is made.
    final Map<String, String> writing = <String, String>{...wanted.values};
    if (wanted.mint.isNotEmpty) {
      final HttpAnswer held = await context.http.send(
        vaultRead(url, dataPath, token: token.value ?? ''),
      );
      final Object? current = isAbsent(held) ? null : decodedData(held.body)?['data'];
      final Map<String, Object?> standing = current is Map<String, Object?>
          ? current
          : const <String, Object?>{};
      for (final String field in wanted.mint) {
        final Object? already = standing[field];
        writing[field] = already is String && already.isNotEmpty
            ? already
            : context.entropy.hex(mintedBytes);
      }
    }

    final HttpAnswer answer = await context.http.send(
      vaultWrite(url, dataPath, token: token.value ?? '', body: <String, Object?>{'data': writing}),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/$dataPath',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  /// How many bytes a generated field holds before it is written as hexadecimal.
  ///
  /// Thirty-two, which is the length this organisation's other minter settled on and recorded its
  /// reason for: two hundred and fifty-six bits in a form that needs escaping inside no connection
  /// string, no environment variable and no SQL statement.
  static const int mintedBytes = 32;

  /// Where the entry [at] has its data, under Vault's version one API.
  String _dataPath(String at) => '$mount/data/$at';

  /// What this entry would hold, or why it cannot be composed.
  Future<_Body> _wanted(StepContext context, String dataPath) async {
    final String secretsPath = vaultSecretsPath(context, repository);
    if (!await context.files.exists(secretsPath)) {
      return _Body.unwritable(
        '$secretsPath is not on this host, and it is the one file an operator fills in — every '
        'value of the seed is read out of it',
      );
    }
    final String content = await context.files.read(secretsPath);
    final String? crlf = carriageReturnRefusal(secretsPath, content);
    if (crlf != null) {
      return _Body.unwritable(crlf);
    }

    final Map<String, String> assignments = shellAssignments(content);
    final Map<String, String> values = <String, String>{};
    final List<String> toMint = <String>[];
    final List<String> wrong = <String>[];

    for (final String declared in fields) {
      final int equals = declared.indexOf('=');
      if (equals <= 0) {
        wrong.add('"$declared" is not a <field>=<VARIABLE> pair');
        continue;
      }
      final String field = declared.substring(0, equals).trim();
      final String variable = declared.substring(equals + 1).trim();
      final String value = assignments[variable] ?? '';
      final bool ownedElsewhere = fieldsOwnedElsewhere.contains(field);

      if (value.isEmpty) {
        if (mint.contains(field)) {
          toMint.add(field);
        } else if (!ownedElsewhere) {
          wrong.add('$variable is empty in $secretsPath, and $field of $dataPath is read from it');
        }
        continue;
      }
      if (isUnfilled(value)) {
        if (ownedElsewhere) {
          context.log.debug(
            '$field is left out of $dataPath: $variable still holds the text that marks it '
            'unfilled, and another writer owns that field',
          );
          continue;
        }
        wrong.add('$variable in $secretsPath still holds the text that marks it unfilled');
        continue;
      }
      values[field] = value;
    }

    // Everything wrong at once. An operator told about one variable per run is an operator running
    // the whole seed five times to learn five things, and every one of those runs writes.
    return wrong.isEmpty ? _Body.values(values, mint: toMint) : _Body.unwritable(wrong.join('; '));
  }
}

/// What one entry would hold, or why it cannot be composed.
final class _Body {
  const _Body.values(this.values, {this.mint = const <String>[]}) : refusal = null;

  const _Body.unwritable(this.refusal) : values = const <String, String>{}, mint = const <String>[];

  /// The fields whose value the hand-filled input supplies.
  final Map<String, String> values;

  /// The fields nothing supplies, which this run generates — but only where the entry does not
  /// already hold them. Generating over a value already in use locks out whatever is using it.
  final List<String> mint;

  final String? refusal;

  /// Whether this entry would write nothing at all.
  bool get isEmpty => values.isEmpty && mint.isEmpty;
}
