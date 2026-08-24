import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Enables one auth method at one path in Vault.
///
/// The Vault API itself stays token-driven; a mount is how everything else proves who it is — an
/// operator through an identity provider, a workload's secret reader through the kubernetes mount
/// of its own cluster.
///
/// **A kubernetes mount carries its cluster's own path, and that is not decoration.** One Vault can
/// serve several clusters, so the path is what tells two of them apart — and it is also what every
/// policy templated on a login is written against. The path is read out of the profile, under the
/// layout's auth-path key, because whatever logs in through the mount reads that same key: a mount
/// created anywhere else is a mount nothing on the cluster reaches.
///
/// **ENABLING A MOUNT IS NOT THE SAME AS CONFIGURING IT, and one without the other is a mount that
/// refuses every login.** Vault answers `500 — could not load backend configuration` to anything
/// that tries, which says nothing about what is missing. A kubernetes mount needs to be told where
/// its cluster's API is before any workload can log in through it; an identity mount needs its
/// issuer and its client. WHAT those values are is one installation's business and arrives on the
/// row, so this step writes whatever it is given and knows none of it.
///
/// Measured: a run that enabled the mount and stopped there left every secret reader on the cluster
/// refused, which showed up as every workload holding a credential coming up Degraded at once.
///
/// **Disabling a mount is not the reverse of enabling one.** The mount's accessor is minted when it
/// is enabled and a new one is minted when it is enabled again, so every policy that interpolates
/// the old accessor resolves to nothing afterwards, silently. That is why the undo here is the last
/// resort it is and why nothing re-enables a mount by turning it off first.
final class VaultAuthMethod extends ReversibleStep<bool> {
  /// Enables an auth method of [type] at [path] in the Vault the profile in [repository] names.
  const VaultAuthMethod({
    required this.repository,
    required this.type,
    required this.path,
    required this.layout,
    this.configuration,
    this.configurationFromAnswers = const <String>[],
    this.configurationFromEntries = const <String>[],
    this.configurationDecoded = const <String>[],
    this.configurationWriteOnly = const <String>[],
  });

  /// Builds the step from what the program gave it.
  factory VaultAuthMethod.fromArguments(Arguments arguments) => VaultAuthMethod(
    repository: arguments.text('repository'),
    type: arguments.text('type'),
    path: arguments.text('path'),
    layout: VaultLayout.fromArguments(arguments),
    configuration: arguments.optionalText('configuration'),
    configurationFromAnswers: arguments.textList('configuration_from_answers'),
    configurationFromEntries: arguments.textList('configuration_from_entries'),
    configurationDecoded: arguments.textList('configuration_decoded'),
    configurationWriteOnly: arguments.textList('configuration_write_only'),
  );

  /// What the mount is told about itself, or null where it needs nothing.
  ///
  /// Written as it stands, with the placeholders every other row of this family uses filled from
  /// this run. Nothing here reads a key of it: which keys a mount takes is Vault's business and
  /// which values are right is the installation's.
  final String? configuration;

  /// The configuration keys written from an ANSWER of this run, each as `<key>=<answer>`.
  ///
  /// For the values a program file cannot hold and the profile does not know: a mount that
  /// validates logins against ANOTHER cluster is told that cluster's API address, its certificate
  /// authority and a reviewing credential, and all three are facts of one run — the credential a
  /// secret among them. An answer's value reaches Vault in the request body and nowhere else: never
  /// an argument, never a plan, never the record, which keeps method, address and status only.
  final List<String> configurationFromAnswers;

  /// The configuration keys written from an ENTRY of this Vault, each as `<key>=<mount>/<path>:<field>`.
  ///
  /// For the values that neither the program file nor the run holds because this Vault MINTED them.
  /// A browser login is the case: the identity provider's clients are registered with secrets an
  /// earlier row generates inside the store, so the value exists only there — it never was an
  /// answer and never may become one, since an answer travels through the operator's session.
  ///
  /// The mount stands in the reference because this row names none of its own. `vault_kv_entry`
  /// writes the same reference as `copy_from` and leaves the mount out, having stated it on the
  /// row; the same notation with the mount in front is the same idea where there is nothing to
  /// leave it out of.
  final List<String> configurationFromEntries;

  /// The keys of [configurationFromAnswers] whose answer arrives base64-encoded and whose mount
  /// takes the decoded text.
  ///
  /// A certificate is the case: it has line breaks, and a value with a line break in it cannot
  /// travel as one answer — so it travels encoded, and the row says which keys to decode rather
  /// than the step guessing from the shape of a value.
  final List<String> configurationDecoded;

  /// The configuration keys Vault accepts and never returns.
  ///
  /// A reviewing credential is the case: Vault takes it and its config read omits it, so a step
  /// that compared it against the read would find it missing on every run, rewrite the mount, ask
  /// again, still find it missing — and a step whose post-apply check never answers satisfied is a
  /// step that fails while having done its work. Keys named here are written and not compared.
  final List<String> configurationWriteOnly;

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile "
          "and the credential file Vault's root token was written to",
    ),
    ArgumentSpec(
      name: 'type',
      kind: ArgumentKind.text,
      describes: 'the kind of auth method, as Vault names it',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the mount path, which is what every role and every templated policy is written '
          'against — "$kubernetesMountPlaceholder" for the mount this cluster\'s own workloads log '
          'in through, which the profile names',
    ),
    ArgumentSpec(
      name: 'configuration',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'what the mount is told about itself, as one JSON object, written to its own config path '
          'after it is enabled. A mount that needs none is left without one; a mount that needs one '
          'and is not given it refuses every login with a message about a backend configuration '
          'rather than about what is missing',
    ),
    ArgumentSpec(
      name: 'configuration_from_answers',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the configuration keys written from an answer of this run, each as <key>=<answer> — for '
          'a value no program file can hold and the profile does not know, such as the API address, '
          'the certificate authority and the reviewing credential of ANOTHER cluster this mount '
          'validates logins against. The value reaches Vault in the request body and nowhere else',
    ),
    ArgumentSpec(
      name: 'configuration_from_entries',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the configuration keys written from an entry of this Vault, each as '
          '<key>=<mount>/<path>:<field> — for a value this store minted itself, such as the secret '
          'a client of the identity provider was registered with, which never was an answer of any '
          'run and cannot become one',
    ),
    ArgumentSpec(
      name: 'configuration_decoded',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the keys of configuration_from_answers whose answer arrives base64-encoded and whose '
          'mount takes the decoded text — a certificate has line breaks and cannot travel as one '
          'answer otherwise',
    ),
    ArgumentSpec(
      name: 'configuration_write_only',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the configuration keys Vault accepts and never returns, such as a reviewing credential '
          '— written and not compared, because comparing a key the read omits would rewrite the '
          'mount on every run and never call it finished',
    ),
    ...VaultLayout.arguments,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// None by name. What this step reads out of the run is whichever answer the row's `run_answer`
  /// names, and that is a value of a program rather than of this package — so there is no name here
  /// that a resolver could hold a program to, and an answer the run does not carry leaves the slot
  /// standing and is refused by name where the text is used.
  static const List<String> answers = <String>[];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The kind of method.
  final String type;

  /// The mount path.
  final String path;

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';
    final String at = mount.value ?? '';

    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (token.value case final String held) {
      final Object? mounted = await _mountedType(context, url, held, at);
      if (mounted == null) {
        return const CheckResult.ready();
      }
      if (mounted == type) {
        // THE MOUNT BEING THERE IS NOT THE POSTCONDITION. A mount that is enabled and not told
        // where its cluster is refuses every login, so a check that stopped at the type would
        // report finished about a mount nothing can use.
        final _Configuration wanted = await _wantedConfiguration(context, vault, url, held);
        if (wanted.refusal case final String refusal) {
          return CheckResult.blocked(refusal);
        }
        final Map<String, Object?>? body = wanted.body;
        if (body == null) {
          return CheckResult.satisfied('$at/ is a $type auth mount on this Vault');
        }
        return await _configured(context, url, held, at, body)
            ? CheckResult.satisfied('$at/ is a $type auth mount and holds what this run tells it')
            : const CheckResult.ready();
      }
      return CheckResult.blocked(
        '$at/ is already a $mounted auth mount and this run wants a $type one. Changing it '
        'means disabling the mount, which mints a new accessor and leaves every policy '
        'templated on the old one resolving to nothing',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/sys/auth/${mount.value}',
      body:
          configuration == null &&
              configurationFromAnswers.isEmpty &&
              configurationFromEntries.isEmpty
          ? 'a $type auth mount'
          : 'a $type auth mount, and what it is told about itself',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final String url = vault.url ?? '';
    final String at = vault.forThisInstallation(context, path).value ?? '';
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    final String held = token.value ?? '';
    final HttpAnswer answer = await context.http.send(
      vaultWrite(url, 'sys/auth/$at', token: held, body: <String, Object?>{'type': type}),
    );
    // A mount that is already there answers that it exists rather than being made again, and the
    // configuration below still has to be written: the two are separate acts and only one of them
    // is what a repeat run has left to do.
    if (!answer.ok && await _mountedType(context, url, held, at) != type) {
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/sys/auth/$at',
        status: answer.status,
        body: answer.body,
      );
    }

    final _Configuration wanted = await _wantedConfiguration(context, vault, url, held);
    if (wanted.refusal case final String refusal) {
      throw StateError(refusal);
    }
    if (wanted.body case final Map<String, Object?> body) {
      final HttpAnswer told = await context.http.send(
        vaultWrite(url, 'auth/$at/config', token: held, body: body),
      );
      if (!told.ok) {
        throw RequestRefused(
          method: 'POST',
          url: '$url/v1/auth/$at/config',
          status: told.status,
          body: told.body,
        );
      }
    }
  }

  /// What this mount would be told about itself, or why it cannot be composed.
  ///
  /// The file's part and the answers' part in one object, because Vault takes one write: a key both
  /// supply is a contradiction somebody sees rather than a silent precedence rule, and a key whose
  /// answer this run does not hold is refused by the answer's name.
  Future<_Configuration> _wantedConfiguration(
    StepContext context,
    VaultProfile vault,
    String url,
    String token,
  ) async {
    final Map<String, Object?> body = <String, Object?>{};
    bool anything = false;

    if (configuration case final String written) {
      final ArgumentText filled = vault.forThisInstallation(context, written);
      if (filled.refusal case final String refusal) {
        return _Configuration.unwritable(refusal);
      }
      final Map<String, Object?>? decoded = decodedObject(filled.value ?? '');
      if (decoded == null) {
        return const _Configuration.unwritable(
          'the configuration this row gives the mount is not a JSON object, and Vault takes one — '
          'a mount whose fields arrive as text is refused with a message about types rather than '
          'about this row',
        );
      }
      body.addAll(decoded);
      anything = true;
    }

    for (final String declared in configurationFromAnswers) {
      final int equals = declared.indexOf('=');
      if (equals <= 0) {
        return _Configuration.unwritable('"$declared" is not a <key>=<answer> pair');
      }
      final String key = declared.substring(0, equals).trim();
      final String answer = declared.substring(equals + 1).trim();
      if (body.containsKey(key)) {
        return _Configuration.unwritable(
          '$key of the mount configuration is written from the file AND from the answer '
          '"$answer", and one key holds one value',
        );
      }
      final String? held = context.answers.optionalText(answer);
      if (held == null || held.isEmpty) {
        return _Configuration.unwritable(
          'this run holds no answer "$answer", and $key of the mount configuration is written '
          'from it',
        );
      }
      if (configurationDecoded.contains(key)) {
        try {
          body[key] = utf8.decode(base64Decode(held.trim()));
        } on FormatException {
          return _Configuration.unwritable(
            'the answer "$answer" does not decode as base64, and $key is declared decoded — the '
            'value that travels under that answer is the encoded form of a text with line breaks',
          );
        }
      } else {
        body[key] = held;
      }
      anything = true;
    }

    for (final String declared in configurationFromEntries) {
      final int equals = declared.indexOf('=');
      final int colon = declared.lastIndexOf(':');
      final int slash = declared.indexOf('/', equals + 1);
      if (equals <= 0 || slash <= equals || colon <= slash) {
        return _Configuration.unwritable(
          '"$declared" is not a <key>=<mount>/<path>:<field> reference',
        );
      }
      final String key = declared.substring(0, equals).trim();
      final String mount = declared.substring(equals + 1, slash).trim();
      final String field = declared.substring(colon + 1).trim();
      if (body.containsKey(key)) {
        return _Configuration.unwritable(
          '$key of the mount configuration is written twice — once from the row and once from '
          '$mount/$field — and one key holds one value',
        );
      }
      final ArgumentText entry = vault.forThisInstallation(
        context,
        declared.substring(slash + 1, colon).trim(),
      );
      if (entry.refusal case final String refusal) {
        return _Configuration.unwritable(refusal);
      }
      final String at = entry.value ?? '';
      final HttpAnswer held = await context.http.send(
        vaultRead(url, '$mount/data/$at', token: token),
      );
      final Object? data = decodedData(held.body)?['data'];
      final Object? value = data is Map<String, Object?> ? data[field] : null;
      if (value is! String || value.isEmpty) {
        return _Configuration.unwritable(
          '$field of $mount/data/$at is what $key of the mount configuration is written from, and '
          'it is not there. The entry that owns that value is written by an earlier row, so a run '
          'reaching this one without it has skipped that row rather than failed it',
        );
      }
      body[key] = value;
      anything = true;
    }

    return anything ? _Configuration.of(body) : const _Configuration.none();
  }

  /// Whether the mount already holds every value this run tells it.
  ///
  /// Only the keys this run writes are compared, minus the ones declared write-only. Vault answers
  /// a config with defaults filled in and with fields it derives itself, so demanding the whole
  /// object match would report a difference on every run — and a mount that is rewritten on every
  /// run is one nothing can ever call finished. A write-only key is the same trap from the other
  /// side: the read omits it, so comparing it can never converge.
  Future<bool> _configured(
    StepContext context,
    String url,
    String token,
    String at,
    Map<String, Object?> wanted,
  ) async {
    final HttpAnswer answer = await context.http.send(
      vaultRead(url, 'auth/$at/config', token: token),
    );
    final Map<String, Object?>? held = decodedData(answer.body);
    if (held == null) {
      return false;
    }
    for (final MapEntry<String, Object?> field in wanted.entries) {
      if (configurationWriteOnly.contains(field.key)) {
        continue;
      }
      if (!sameJsonValue(held[field.key], field.value)) {
        context.log.debug('$at/ differs from this run in ${field.key}');
        return false;
      }
    }
    return true;
  }

  /// Whether Vault already holds an auth mount at this path.
  ///
  /// Read before the enable, because disabling a mount is not the reverse of enabling one: a mount
  /// enabled again carries a new accessor, and every policy templated on the old one then resolves
  /// to nothing, with no error anywhere and every caller refused about its own token. So the undo
  /// disables only a mount this run created.
  ///
  /// A mount path this run cannot read out of the profile, and a Vault it cannot ask, are answered
  /// as already there: neither is a mount it may disable.
  @override
  Future<bool> capture(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal == null) {
      final RootToken token = await rootTokenFrom(
        context,
        vaultCredentialsPath(context, repository, layout: layout),
      );
      if (token.value case final String held) {
        return await _mountedType(context, vault.url ?? '', held, mount.value ?? '') != null;
      }
    }
    return true;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.value case final String held) {
      await context.http.send(vaultDelete(vault.url ?? '', 'sys/auth/${mount.value}', token: held));
    }
  }

  /// The type Vault holds at the mount path [at], or null when it holds nothing there.
  Future<Object?> _mountedType(StepContext context, String url, String token, String at) async {
    final HttpAnswer answer = await context.http.send(vaultRead(url, 'sys/auth', token: token));
    final Map<String, Object?>? mounts = decodedData(answer.body) ?? decodedObject(answer.body);
    final Object? mount = mounts?['$at/'];
    return mount is Map<String, Object?> ? mount['type'] : null;
  }
}

/// What one mount would be told about itself, or why it cannot be composed.
final class _Configuration {
  /// Holds the whole configuration as it reaches Vault.
  const _Configuration.of(Map<String, Object?> this.body) : refusal = null;

  /// Records that the mount is told nothing at all.
  const _Configuration.none() : body = null, refusal = null;

  /// Records that it cannot be composed, because [refusal].
  const _Configuration.unwritable(String this.refusal) : body = null;

  /// The configuration, or null where the mount is told nothing or nothing can be composed.
  final Map<String, Object?>? body;

  /// Why it cannot be composed, or null when it can.
  final String? refusal;
}
