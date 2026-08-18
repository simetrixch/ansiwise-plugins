import 'package:ansiwise_core/ansiwise_core.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Enables one versioned key-value mount.
///
/// A mount has to exist before the first value is written on it, and it never moves. What separates
/// callers on a shared mount is the path and the policy templated on it, not the mount — one mount
/// per caller is a choice a program makes with several rows, not one this step makes for it.
///
/// **The second version and not the first.** It is what keeps the ten previous values of an entry,
/// and those ten are the only way back from a write that put the wrong thing in — a key-value write
/// has no transaction and nothing else undoes a value.
final class VaultKvMount extends IrreversibleStep {
  /// Enables a versioned key-value mount at [path] in the Vault the profile in [repository] names.
  const VaultKvMount({required this.repository, required this.path, required this.layout});

  /// Builds the step from what the program gave it.
  factory VaultKvMount.fromArguments(Arguments arguments) => VaultKvMount(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    layout: VaultLayout.fromArguments(arguments),
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
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the mount path the entries of this program are written under',
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

  /// The mount path.
  final String path;

  @override
  String get irreversibleReason =>
      'taking the mount away takes every value on it with it, and nothing here holds a copy of any '
      'of them';

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';

    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
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
        '$path/ is already a ${mount['type']} mount on this Vault, and this run addresses $path/ '
        'as versioned key-value',
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
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
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
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
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
