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
  });

  /// Builds the step from what the program gave it.
  factory VaultAuthMethod.fromArguments(Arguments arguments) => VaultAuthMethod(
    repository: arguments.text('repository'),
    type: arguments.text('type'),
    path: arguments.text('path'),
    layout: VaultLayout.fromArguments(arguments),
    configuration: arguments.optionalText('configuration'),
  );

  /// What the mount is told about itself, or null where it needs nothing.
  ///
  /// Written as it stands, with the placeholders every other row of this family uses filled from
  /// this run. Nothing here reads a key of it: which keys a mount takes is Vault's business and
  /// which values are right is the installation's.
  final String? configuration;

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
        final ArgumentText wanted = vault.forThisInstallation(context, configuration ?? '');
        if (wanted.refusal case final String refusal) {
          return CheckResult.blocked(refusal);
        }
        if (configuration == null) {
          return CheckResult.satisfied('$at/ is a $type auth mount on this Vault');
        }
        return await _configured(context, url, held, at, wanted.value ?? '')
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
      body: configuration == null
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

    if (configuration case final String written) {
      final ArgumentText filled = vault.forThisInstallation(context, written);
      if (filled.refusal case final String refusal) {
        throw StateError(refusal);
      }
      final Map<String, Object?>? body = decodedObject(filled.value ?? '');
      if (body == null) {
        throw StateError(
          'the configuration this row gives $at/ is not a JSON object, and Vault takes one — a '
          'mount whose fields arrive as text is refused with a message about types rather than '
          'about this row',
        );
      }
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

  /// Whether the mount already holds every value this run tells it.
  ///
  /// Only the keys this run writes are compared. Vault answers a config with defaults filled in and
  /// with fields it derives itself, so demanding the whole object match would report a difference on
  /// every run — and a mount that is rewritten on every run is one nothing can ever call finished.
  Future<bool> _configured(
    StepContext context,
    String url,
    String token,
    String at,
    String written,
  ) async {
    final Map<String, Object?>? wanted = decodedObject(written);
    if (wanted == null) {
      return false;
    }
    final HttpAnswer answer = await context.http.send(
      vaultRead(url, 'auth/$at/config', token: token),
    );
    final Map<String, Object?>? held = decodedData(answer.body);
    if (held == null) {
      return false;
    }
    for (final MapEntry<String, Object?> field in wanted.entries) {
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
