import 'package:ansiwise_api/ansiwise_api.dart';

/// Puts a pod range into the network manifest Calico creates its address pool from.
///
/// **The value is not on the line that names it.** The manifest declares an environment variable as
/// a name on one line and its value on the NEXT, so a rewrite that looks for the range on the same
/// line as [variable] matches nothing, writes nothing, and reports success. That is why this reads
/// the file back afterwards rather than trusting the write.
///
/// **What this file decides, and what it does not.** Calico reads it once, when it creates the pool.
/// It never mutates an existing pool from it. So a machine can carry a perfectly stamped manifest
/// and run on the old pool, and the question "has the conversion happened" is asked of the live pool
/// rather than of this file.
///
/// A copy of the file goes to a timestamped backup before each real change. What an undo puts back
/// is the text read before the change; the backups stay on the machine, and whatever applies the
/// manifest to the cluster is what names one of them.
final class StampCalicoPoolCidrInCniManifest extends ReversibleStep<String?> {
  /// Puts [podCidr] into the manifest at [manifestPath].
  const StampCalicoPoolCidrInCniManifest({
    required this.podCidr,
    required this.manifestPath,
    required this.fileMode,
  });

  /// The manifest is written by whatever installs the cluster, which is an earlier row of the same
  /// program — so before that row has run there is no file to read and none to change.
  ///
  /// Without this, a dry run of a program that installs a cluster and then configures it stops here,
  /// at its first configuring step, on a machine where nothing has been installed yet. That is
  /// exactly the machine a dry run is pointed at, and a real run is admitted only where a dry one
  /// came back green.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Builds the step from what the program gave it.
  factory StampCalicoPoolCidrInCniManifest.fromArguments(Arguments arguments) =>
      StampCalicoPoolCidrInCniManifest(
        podCidr: arguments.text('pod_cidr'),
        manifestPath: arguments.text('manifest_path'),
        fileMode: arguments.integer('file_mode'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the network manifest Calico creates its address pool from — where whatever installed '
          'the cluster keeps it, which is a fact of that installation and not of Calico',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the manifest and its backup are written with, as the number the machine '
          'stores — 384 is the owner-only mode a file read by a privileged service wants',
    ),
  ];

  /// The environment variable whose value is the pool's range.
  ///
  /// Calico's own name for it, the same in every manifest that installs it.
  static const String variable = 'CALICO_IPV4POOL_CIDR';

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The manifest holding the pool's declaration.
  final String manifestPath;

  /// The permissions the manifest is written with.
  final int fileMode;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath)) {
      return CheckResult.blocked(
        '$manifestPath is not there — whatever installed the cluster writes it, so this ran before '
        'that install or against a machine it was removed from',
      );
    }
    final String current = await context.files.read(manifestPath);
    final String? stamped = stamp(current, podCidr);
    if (stamped == null) {
      return CheckResult.blocked(
        '$manifestPath declares no $variable, so nothing here decides the pool and Calico would '
        'create it on the shipped default — the manifest is not the one this cluster ships',
      );
    }
    if (stamped == current) {
      return CheckResult.satisfied('the manifest already declares $variable as $podCidr');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(manifestPath, before: current, after: stamp(current, podCidr) ?? current);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    final String? stamped = stamp(current, podCidr);
    if (stamped == null || stamped == current) {
      return;
    }
    final String backup = '$manifestPath.bak.${_stampOfNow(context)}';
    await context.files.write(backup, current, mode: fileMode);
    context.log.info('the manifest as it was is at $backup');
    await context.files.write(manifestPath, stamped, mode: fileMode);

    // The write is reported the same way whether the rewrite matched anything or not, so what the
    // file holds now is read rather than assumed. This is the failure the same-line expression
    // produced: a stamp that took nothing, and a phase that carried on.
    final String written = await context.files.read(manifestPath);
    if (stamp(written, podCidr) != written) {
      throw CommandFailed(
        argv: <String>['write', manifestPath],
        exitCode: 1,
        stdout: '',
        stderr: 'the manifest was written and still does not declare $variable as $podCidr',
      );
    }
  }

  /// The manifest as it was, or null when it was not there.
  ///
  /// The backups accumulate under names carrying the moment they were made, so the newest one at
  /// undo time can be the copy a later run wrote — and putting that back would stamp a range this
  /// run never had.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(manifestPath) ? context.files.read(manifestPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Whatever installed the cluster writes this file. There was none, so there is nothing to put
      // back.
      return;
    }
    await context.files.write(manifestPath, captured, mode: fileMode);
  }

  /// [manifest] with the value under [variable] replaced by [podCidr], or null when it declares none.
  ///
  /// The value is taken from the line FOLLOWING the one naming the variable, and only the value on
  /// that line is replaced — the indentation and the quoting it was written with stay as they are.
  static String? stamp(String manifest, String podCidr) {
    final List<String> lines = manifest.split('\n');
    int stamped = 0;
    for (int i = 0; i < lines.length - 1; i++) {
      if (!lines[i].contains(variable)) {
        continue;
      }
      final RegExpMatch? value = _value.firstMatch(lines[i + 1]);
      if (value == null) {
        continue;
      }
      lines[i + 1] = '${value.group(1)}${value.group(2)}$podCidr${value.group(2)}';
      stamped++;
    }
    return stamped == 0 ? null : lines.join('\n');
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(manifestPath) ? context.files.read(manifestPath) : '';

  /// The moment this run is at, in a shape that sorts and carries no separator a path dislikes.
  static String _stampOfNow(StepContext context) => context.clock
      .now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '')
      .split('Z')
      .first;

  /// The leading whitespace and `value:` of a value line, and the quote it is written with.
  static final RegExp _value = RegExp(r'''^(\s*(?:-\s+)?value:\s*)(["']?)[^"']*\2\s*$''');
}
