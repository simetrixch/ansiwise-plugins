import 'package:ansiwise_api/ansiwise_api.dart';
import 'microk8s.dart';
import 'preflight_docker_mirror_credential.dart';

/// Sends this cluster's public-registry pulls through the registry of the cluster that builds.
///
/// **Why there is a mirror at all, in one measured number.** The public registry allows a hundred
/// pulls every six hours from one address when nobody is signed in, and bringing a cluster up spends
/// more than that. A cluster that runs out sits there with images it cannot fetch.
///
/// **The file is read again on every pull, so nothing has to be restarted.** The container runtime
/// looks for a file of this name under a directory the snap already points it at, which is why this
/// is one write and no service management at all.
///
/// **The public registry stays in the file as the fallback, and dropping that line is the failure
/// worth naming.** With it, a mirror that is down or refuses makes a pull slower; without it, the
/// same mirror makes every pull impossible.
///
/// **The registry refuses anonymous pulls, so an unauthenticated mirror is pointless.** It is
/// therefore never written without a credential — the step before this one is what refuses a machine
/// whose credential is fillable and unfilled.
///
/// The file holds a live credential and is readable by its owner alone.
final class WriteContainerdDockerMirror extends ReversibleStep<String?> {
  /// Writes the mirror from the checkout at [repository].
  const WriteContainerdDockerMirror({required this.repository, required this.certsDirectory});

  /// Builds the step from what the program gave it.
  factory WriteContainerdDockerMirror.fromArguments(Arguments arguments) =>
      WriteContainerdDockerMirror(
        repository: arguments.text('repository'),
        certsDirectory: arguments.text('certs_directory'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation is generated in, which carries the cluster's own "
          'profile and its secrets',
    ),
    ArgumentSpec(
      name: 'certs_directory',
      kind: ArgumentKind.text,
      describes: 'the directory the container runtime reads per-registry configuration from',
      required: false,
      defaultValue: defaultCertsDirectory,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The same three the gate in front of it reads, by its names, so the two cannot come to
  /// different conclusions about which machine this is.
  static const List<String> answers = PreflightDockerMirrorCredential.answers;

  /// Where the container runtime looks for per-registry configuration.
  static const String defaultCertsDirectory = '$microk8sArgumentsDirectory/certs.d';

  /// The registry whose pulls are mirrored.
  static const String mirrored = 'docker.io';

  /// Where its pulls go when the mirror does not answer.
  static const String fallback = 'https://registry-1.docker.io';

  /// `0600` — the file carries a live credential.
  static const int mode = 0x180;

  /// The checkout this installation is generated in.
  final String repository;

  /// The directory the container runtime reads.
  final String certsDirectory;

  /// The file this step writes.
  String get path => '$certsDirectory/$mirrored/hosts.toml';

  @override
  Future<CheckResult> check(StepContext context) async {
    final PreflightDockerMirrorCredential preflight = _preflight;
    if (PreflightDockerMirrorCredential.hostsTheRegistry(context)) {
      return const CheckResult.satisfied(
        'this cluster hosts the registry itself, so nothing here pulls through a mirror',
      );
    }

    final String? host = await PreflightDockerMirrorCredential.registryHost(
      context,
      preflight.profilePath,
    );
    if (host == null) {
      return CheckResult.satisfied(
        "the registry's address is not readable from ${preflight.profilePath}, so there is no mirror "
        'to write',
      );
    }
    if (!await context.files.exists(certsDirectory)) {
      context.log.warn(
        '$certsDirectory is not there, so the container runtime has nowhere to read a mirror from '
        'and every pull goes to the rate-limited public path',
      );
      return const CheckResult.satisfied(
        'the container runtime reads no per-registry configuration here',
      );
    }
    if (!await context.files.exists(preflight.secretsPathIn(context))) {
      context.log.warn(
        '${preflight.secretsPathIn(context)} is not on this machine, so no mirror is written and every pull '
        'goes to the rate-limited public path. Fill the file in and run this program again — nothing '
        'else comes back to write it.',
      );
      return const CheckResult.satisfied('there is no secrets file on this machine yet');
    }

    // The same guard as the step before the install, asked again here so that running this program
    // on its own keeps it.
    final PullCredential credential = await PreflightDockerMirrorCredential.readCredential(
      context,
      preflight.secretsPathIn(context),
      host,
    );
    if (credential.refusal case final String refusal) {
      return CheckResult.blocked('${preflight.secretsPathIn(context)}: $refusal');
    }
    if (credential.blob case final String blob) {
      if (!await context.files.exists(path)) {
        return const CheckResult.ready();
      }
      return await context.files.read(path) == hostsToml(host, blob)
          ? CheckResult.satisfied('$path already sends $mirrored pulls through $host')
          : const CheckResult.ready();
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String before = await context.files.exists(path) ? await context.files.read(path) : '';
    final String? host = await PreflightDockerMirrorCredential.registryHost(
      context,
      _preflight.profilePath,
    );
    // The credential is left out of the plan on purpose. A plan is read by a person and reaches the
    // record; what it has to say is which registry the pulls go through, not what they go with.
    return StepPlan.diff(
      path,
      before: before,
      after: host == null ? before : hostsToml(host, '<the pull credential>'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? host = await PreflightDockerMirrorCredential.registryHost(
      context,
      _preflight.profilePath,
    );
    if (host == null) {
      return;
    }
    final PullCredential credential = await PreflightDockerMirrorCredential.readCredential(
      context,
      _preflight.secretsPathIn(context),
      host,
    );
    if (credential.blob case final String blob) {
      context.log.info('$mirrored pulls now go through $host, falling back to $fallback');
      await context.files.write(path, hostsToml(host, blob), mode: mode);
    }
  }

  /// What the file held before, or null when it was not there.
  ///
  /// A machine whose pulls already went through a mirror gets that file back, credential and all,
  /// with the same permission bits; deleting it there would put every pull on the rate-limited
  /// public path instead of where it was.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(path) ? context.files.read(path) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Deleting it puts the pulls back on the public path, which is where they were before.
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }

  /// The configuration sending [mirrored] pulls through [host] with [blob].
  static String hostsToml(String host, String blob) =>
      '# $mirrored pulls go through $host, which caches them.\n'
      '#\n'
      '# The line below keeps the public registry as the fallback: a mirror that is down or refuses\n'
      '# makes a pull slower, never impossible. Removing it turns an outage of the mirror into an\n'
      '# outage of every pull.\n'
      'server = "$fallback"\n'
      '\n'
      '[host."https://$host"]\n'
      'capabilities = ["pull", "resolve"]\n'
      '\n'
      '# The registry refuses anonymous pulls, so an unauthenticated mirror would answer every pull\n'
      '# with a refusal and fall back to the public path anyway.\n'
      '[host."https://$host".header]\n'
      'authorization = "Basic $blob"\n';

  /// The gate this step keeps, so both read one answer and one file rather than two of each.
  PreflightDockerMirrorCredential get _preflight =>
      PreflightDockerMirrorCredential(repository: repository);
}
