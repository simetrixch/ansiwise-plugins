import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry_mirror.dart';

/// Sends this machine's pulls of one registry through a mirror of it.
///
/// **Why there is a mirror at all, in one measured number.** A public registry allows a limited
/// number of pulls in a window from one address when nobody is signed in, and bringing a machine up
/// spends more than that. A machine that runs out sits there with images it cannot fetch.
///
/// **The file is read again on every pull, so nothing has to be restarted.** The container runtime
/// looks for a file of this name under a directory it is already pointed at, which is why this is
/// one write and no service management at all.
///
/// **The mirrored registry stays in the file as the fallback, and dropping that line is the failure
/// worth naming.** With it, a mirror that is down or refuses makes a pull slower; without it, the
/// same mirror makes every pull impossible.
///
/// **A mirror that refuses anonymous pulls is pointless without a credential.** It is therefore
/// never written without one — the gate in front of this is what refuses a machine whose credential
/// is fillable and unfilled, and this asks the same question again so running it alone keeps the
/// guard.
///
/// The file holds a live credential and is readable by its owner alone.
final class WriteContainerdRegistryMirror extends ReversibleStep<String?> {
  /// Writes the mirror [layout] describes into [certsDirectory].
  const WriteContainerdRegistryMirror({
    required this.layout,
    required this.certsDirectory,
    required this.fallback,
    required this.fileMode,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory WriteContainerdRegistryMirror.fromArguments(Arguments arguments) =>
      WriteContainerdRegistryMirror(
        layout: RegistryMirror.fromArguments(arguments),
        certsDirectory: arguments.text('certs_directory'),
        fallback: arguments.text('fallback'),
        fileMode: arguments.integer('file_mode'),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...RegistryMirror.arguments,
    ArgumentSpec(
      name: 'certs_directory',
      kind: ArgumentKind.text,
      describes:
          'the directory the container runtime reads per-registry configuration from, which is a '
          'fact of how that runtime was installed on this machine',
    ),
    ArgumentSpec(
      name: 'fallback',
      kind: ArgumentKind.text,
      describes:
          'where pulls go when the mirror does not answer, which is the mirrored registry itself. '
          'Leaving it out would turn an outage of the mirror into an outage of every pull',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the file is written with, as the number the machine stores — the file '
          'carries a live credential, so 384 is the owner-only mode it wants',
    ),
    elevationArgument,
  ];

  /// Where the mirror is written down and what it is reached with.
  final RegistryMirror layout;

  /// The directory the container runtime reads.
  final String certsDirectory;

  /// Where pulls go when the mirror does not answer.
  final String fallback;

  /// The permissions the file is written with.
  final int fileMode;

  /// The file this step writes.
  ///
  /// The directory and the file name below it are the container runtime's own convention: one
  /// directory per registry, named for the registry, holding a file of that name.
  String get path => '$certsDirectory/${layout.mirroredRegistry}/hosts.toml';

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (layout.answerRefusalIn(context) case final String why) {
      return CheckResult.blocked(why);
    }
    if (layout.hostsTheMirror(context)) {
      return const CheckResult.satisfied(
        'this machine is the one the mirror runs on, so nothing here pulls through a mirror',
      );
    }

    final String? host = await layout.mirrorHostIn(context, elevated: elevated);
    if (host == null) {
      return CheckResult.satisfied(
        "the mirror's address is not readable from ${layout.profile}, so there is no mirror to "
        'write',
      );
    }
    if (!await context.files.exists(certsDirectory, elevated: elevated)) {
      context.log.warn(
        '$certsDirectory is not there, so the container runtime has nowhere to read a mirror from '
        'and every pull goes to the rate-limited public path',
      );
      return const CheckResult.satisfied(
        'the container runtime reads no per-registry configuration here',
      );
    }
    final String secrets = layout.secretsIn(context);
    if (!await context.files.exists(secrets, elevated: elevated)) {
      context.log.warn(
        '$secrets is not on this machine, so no mirror is written and every pull goes to the '
        'rate-limited public path. Fill the file in and run this program again — nothing else comes '
        'back to write it.',
      );
      return const CheckResult.satisfied('there is no credential file on this machine yet');
    }

    // The same guard the gate before the install keeps, asked again here so that running this
    // program on its own keeps it.
    final PullCredential credential = await layout.readCredential(
      context,
      secrets,
      host,
      elevated: elevated,
    );
    if (credential.refusal case final String refusal) {
      return CheckResult.blocked('$secrets: $refusal');
    }
    if (credential.blob case final String blob) {
      if (!await context.files.exists(path, elevated: elevated)) {
        return const CheckResult.ready();
      }
      return await context.files.read(path, elevated: elevated) == hostsToml(host, blob)
          ? CheckResult.satisfied('$path sends ${layout.mirroredRegistry} pulls through $host')
          : const CheckResult.ready();
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String before = await context.files.exists(path, elevated: elevated)
        ? await context.files.read(path, elevated: elevated)
        : '';
    if (layout.answerRefusalIn(context) case final String why) {
      return StepPlan.nothing(why);
    }
    final String? host = await layout.mirrorHostIn(context, elevated: elevated);
    // BOTH SIDES ARE REDACTED. A plan is read by a person and it reaches the record, so what it may
    // say is which registry the pulls go through — never what they go with.
    //
    // Redacting only the side this step composes left the OTHER one carrying the real value: on a
    // re-run `before` is the file read off the machine, and that file states the credential
    // verbatim. The record writes `before` out, and the redactor hides the values of declared-secret
    // ANSWERS — this one comes out of a file, so nothing hid it.
    return StepPlan.diff(
      path,
      before: _redacted(before),
      after: host == null ? _redacted(before) : hostsToml(host, redactedCredential),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    if (layout.answerRefusalIn(context) != null) {
      return;
    }
    final String? host = await layout.mirrorHostIn(context, elevated: elevated);
    if (host == null) {
      return;
    }
    final PullCredential credential = await layout.readCredential(
      context,
      layout.secretsIn(context),
      host,
    );
    if (credential.blob case final String blob) {
      context.log.info(
        '${layout.mirroredRegistry} pulls now go through $host, falling back to $fallback',
      );
      await context.files.write(path, hostsToml(host, blob), mode: fileMode);
    }
  }

  /// What the file held before, or null when it was not there.
  ///
  /// A machine whose pulls already went through a mirror gets that file back, credential and all,
  /// with the same permission bits; deleting it there would put every pull on the rate-limited
  /// public path instead of where it was.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(path, elevated: elevated)
      ? context.files.read(path, elevated: elevated)
      : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Deleting it puts the pulls back on the public path, which is where they were before.
      await context.files.delete(path, elevated: elevated);
      return;
    }
    await context.files.write(path, captured, mode: fileMode, elevated: elevated);
  }

  /// What stands in the plan where the credential stands in the file.
  ///
  /// Named rather than written inline, so a test can assert that the plan carries this and the
  /// credential carries nothing of it.
  static const String redactedCredential = '<the pull credential>';

  /// [text] with whatever stands after `Basic ` replaced by [redactedCredential].
  ///
  /// Applied to the file as it was FOUND, not only to the text this step composes. The found file
  /// states the credential in full, and a plan carrying it reaches the record — where the redactor
  /// cannot help, because it hides the values of declared-secret answers and this one came off a
  /// machine.
  ///
  /// It replaces rather than removes, so the plan still shows that the line is there and what it is
  /// for. A line taken out would read as a line the file does not have.
  static String _redacted(String text) =>
      text.replaceAll(_basicCredential, 'authorization = "Basic $redactedCredential"');

  /// The one line of this file that carries a secret, matched however it is spaced.
  static final RegExp _basicCredential = RegExp(
    r'authorization\s*=\s*"Basic [^"]*"',
    caseSensitive: false,
  );

  /// The configuration sending pulls of the mirrored registry through [host] with [blob].
  String hostsToml(String host, String blob) =>
      '# ${layout.mirroredRegistry} pulls go through $host, which caches them.\n'
      '#\n'
      '# The line below keeps the mirrored registry itself as the fallback: a mirror that is down\n'
      '# or refuses makes a pull slower, never impossible. Removing it turns an outage of the\n'
      '# mirror into an outage of every pull.\n'
      'server = "$fallback"\n'
      '\n'
      '[host."https://$host"]\n'
      'capabilities = ["pull", "resolve"]\n'
      '\n'
      '# A mirror that refuses anonymous pulls would answer every pull with a refusal and fall back\n'
      '# to the public path anyway, so it is reached with the credential the pull configuration\n'
      '# holds for it.\n'
      '[host."https://$host".header]\n'
      'authorization = "Basic $blob"\n';
}
