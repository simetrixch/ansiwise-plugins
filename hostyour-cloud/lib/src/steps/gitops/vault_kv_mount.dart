import 'package:ansiwise_api/ansiwise_api.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Enables the one versioned key-value mount every secret on this platform lives on.
///
/// One mount and not one per tenant or one per stage: what separates callers here is the path and
/// the policy templated on it, not the mount. Everything a workload ever reads is under this, so it
/// has to exist before the first value is written and it never moves.
///
/// **The second version and not the first.** It is what keeps the ten previous values of an entry,
/// and those ten are the only way back from a write that put the wrong thing in — this phase has no
/// transaction and nothing else undoes a value.
final class VaultKvMount extends IrreversibleStep {
  /// Enables a versioned key-value mount at [path] in the Vault the profile in [repository] names.
  const VaultKvMount({required this.repository, required this.path});

  /// Builds the step from what the program gave it.
  factory VaultKvMount.fromArguments(Arguments arguments) =>
      VaultKvMount(repository: arguments.text('repository'), path: arguments.text('path'));

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
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the mount path every secret of this platform is written under',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = vaultAnswers;

  /// The checkout this installation runs from.
  final String repository;

  /// The mount path.
  final String path;

  @override
  String get irreversibleReason =>
      'taking the mount away takes every value on it with it, and this mount is where every secret '
      'on the platform lives — there is no copy of them anywhere else';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';

    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final HttpAnswer answer = await context.http.send(
      vaultRead(url, 'sys/mounts', token: token.value ?? ''),
    );
    final Map<String, Object?>? mounts = decodedData(answer.body) ?? decodedObject(answer.body);
    final Object? mount = mounts?['$path/'];
    if (mount is! Map<String, Object?>) {
      return const CheckResult.ready();
    }

    final Object? options = mount['options'];
    final Object? version = options is Map<String, Object?> ? options['version'] : null;
    if (mount['type'] != 'kv') {
      return CheckResult.blocked(
        '$path/ is already a ${mount['type']} mount on this Vault, and every secret this platform '
        'writes is addressed under $path/ as versioned key-value',
      );
    }
    return version == '2'
        ? CheckResult.satisfied('$path/ is a versioned key-value mount')
        : CheckResult.blocked(
            '$path/ is a key-value mount at version $version, and the ten previous values of an '
            'entry that the second version keeps are the only way back from a wrong write here',
          );
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/sys/mounts/$path',
      body: 'a versioned key-value mount',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    final HttpAnswer answer = await context.http.send(
      vaultWrite(
        url,
        'sys/mounts/$path',
        token: token.value ?? '',
        body: const <String, Object?>{
          'type': 'kv',
          'options': <String, Object?>{'version': '2'},
        },
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/sys/mounts/$path',
        status: answer.status,
        body: answer.body,
      );
    }
  }
}
