import 'package:ansiwise_api/ansiwise_api.dart';
import 'argument_text.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Enables one auth method at one path in Vault.
///
/// Two of these exist on a cluster and they answer two different questions. The browser mount is how
/// an operator logs into the Vault interface through the identity provider; the cluster mount is how
/// every workload's secret reader proves which namespace it is calling from. The Vault API itself
/// stays token-driven and neither of them changes that.
///
/// **The cluster mount carries the cluster's own short name, and that is not decoration.** One Vault
/// can serve several clusters, so the path is what tells two of them apart — and it is also what
/// every policy templated on a login is written against. The path it is created under is read out of
/// the profile, under [kubernetesAuthPathKey], because that is the key every rendered secret store
/// logs in through: a mount created anywhere else is a mount nothing on the cluster reaches.
///
/// **Disabling a mount is not the reverse of enabling one.** The mount's accessor is minted when it
/// is enabled and a new one is minted when it is enabled again, so every policy that interpolates
/// the old accessor resolves to nothing afterwards, silently. That is why the undo here is the last
/// resort it is and why nothing re-enables a mount by turning it off first.
final class VaultAuthMethod extends ReversibleStep {
  /// Enables an auth method of [type] at [path] in the Vault the profile in [repository] names.
  const VaultAuthMethod({required this.repository, required this.type, required this.path});

  /// Builds the step from what the program gave it.
  factory VaultAuthMethod.fromArguments(Arguments arguments) => VaultAuthMethod(
    repository: arguments.text('repository'),
    type: arguments.text('type'),
    path: arguments.text('path'),
  );

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
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = vaultAnswers;

  /// The checkout this installation runs from.
  final String repository;

  /// The kind of method.
  final String type;

  /// The mount path.
  final String path;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';
    final String at = mount.value ?? '';

    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (token.value case final String held) {
      final Object? mounted = await _mountedType(context, url, held, at);
      if (mounted == null) {
        return const CheckResult.ready();
      }
      return mounted == type
          ? CheckResult.satisfied('$at/ is a $type auth mount on this Vault')
          : CheckResult.blocked(
              '$at/ is already a $mounted auth mount and this run wants a $type one. Changing it '
              'means disabling the mount, which mints a new accessor and leaves every policy '
              'templated on the old one resolving to nothing',
            );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/sys/auth/${mount.value}',
      body: 'a $type auth mount',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final String url = vault.url ?? '';
    final String at = vault.forThisInstallation(context, path).value ?? '';
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    final String held = token.value ?? '';
    final HttpAnswer answer = await context.http.send(
      vaultWrite(url, 'sys/auth/$at', token: held, body: <String, Object?>{'type': type}),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/sys/auth/$at',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final ArgumentText mount = vault.forThisInstallation(context, path);
    if (mount.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
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
