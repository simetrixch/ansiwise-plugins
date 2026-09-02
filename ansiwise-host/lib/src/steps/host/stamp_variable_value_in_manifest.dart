import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts a value into a manifest that writes a variable's NAME on one line and its VALUE on the next.
///
/// **The value is not on the line that names it, and that is the whole shape.** A rewrite looking
/// for the value on the same line as the name matches nothing, writes nothing, and reports success —
/// which is why this reads the file back afterwards rather than trusting the write.
///
/// **WHICH variable, and what reads it afterwards, is the row's to say.** Both arrive as arguments:
/// this knows a file of that shape, and nothing about what the value means to whatever consumes it.
/// Naming one here — the address pool of one network plugin, say — would put a product's fact in a
/// package that has to serve any of them.
///
/// **What this file decides, and what it does not.** Whatever reads a manifest ONCE, at creation,
/// never mutates what it already made from a later edit. So a machine can carry a perfectly stamped
/// manifest and still run on the old value, and "has it taken effect" is a question for the live
/// thing rather than for this file. A row that stamps such a manifest belongs beside a row that asks
/// the live one.
///
/// A copy of the file goes to a timestamped backup before each real change. What an undo puts back
/// is the text read before the change; the backups stay on the machine, and whatever applies the
/// manifest is what names one of them.
final class StampVariableValueInManifest extends ReversibleStep<String?> {
  /// Puts [value] on the line below [variable] in the manifest at [manifestPath].
  const StampVariableValueInManifest({
    required this.variable,
    required this.value,
    required this.manifestPath,
    required this.fileMode,
    this.elevated = false,
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
  factory StampVariableValueInManifest.fromArguments(Arguments arguments) =>
      StampVariableValueInManifest(
        variable: arguments.text('variable'),
        value: arguments.text('value'),
        manifestPath: arguments.text('manifest_path'),
        fileMode: arguments.integer('file_mode'),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'variable',
      kind: ArgumentKind.text,
      describes:
          'the name written on the line ABOVE the value this stamps — whatever reads the manifest '
          'calls it that, and this package is not one of them',
    ),
    ArgumentSpec(name: 'value', kind: ArgumentKind.text, describes: 'what the variable is to hold'),
    ArgumentSpec(
      name: 'manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the manifest carrying that variable — where whatever wrote it keeps it, which is a fact '
          'of one installation and not of this step',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the manifest and its backup are written with, as the number the machine '
          'stores — 384 is the owner-only mode a file read by a privileged service wants',
    ),
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row. A step deciding it for every caller
    // would be a tool package knowing something about the product that pointed it.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so reading and writing it need elevation. Leave it '
          'off for a path this account owns',
      required: false,
    ),
  ];

  /// The name written on the line above the value this stamps.
  final String variable;

  /// What that name is to hold.
  final String value;

  /// The manifest holding the pool's declaration.
  final String manifestPath;

  /// The permissions the manifest is written with.
  final int fileMode;

  /// Whether the manifest belongs to root, so every read and write of it is elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath, elevated: elevated)) {
      return CheckResult.blocked(
        '$manifestPath is not there — whatever installed the cluster writes it, so this ran before '
        'that install or against a machine it was removed from',
      );
    }
    final String current = await context.files.read(manifestPath, elevated: elevated);
    final String? stamped = stamp(current, value);
    if (stamped == null) {
      return CheckResult.blocked(
        '$manifestPath declares no $variable, so nothing here decides that value and whatever reads '
        'the manifest would take the one it shipped with — this is not the manifest the row meant',
      );
    }
    if (stamped == current) {
      return CheckResult.satisfied('the manifest already declares $variable as $value');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(manifestPath, before: current, after: stamp(current, value) ?? current);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    final String? stamped = stamp(current, value);
    if (stamped == null || stamped == current) {
      return;
    }
    final String backup = '$manifestPath.bak.${_stampOfNow(context)}';
    await context.files.write(backup, current, mode: fileMode, elevated: elevated);
    context.log.info('the manifest as it was is at $backup');
    await context.files.write(manifestPath, stamped, mode: fileMode, elevated: elevated);

    // The write is reported the same way whether the rewrite matched anything or not, so what the
    // file holds now is read rather than assumed. This is the failure the same-line expression
    // produced: a stamp that took nothing, and a phase that carried on.
    final String written = await context.files.read(manifestPath, elevated: elevated);
    if (stamp(written, value) != written) {
      throw CommandFailed(
        argv: <String>['write', manifestPath],
        exitCode: 1,
        stdout: '',
        stderr: 'the manifest was written and still does not declare $variable as $value',
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
      await context.files.exists(manifestPath, elevated: elevated)
      ? context.files.read(manifestPath, elevated: elevated)
      : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Whatever installed the cluster writes this file. There was none, so there is nothing to put
      // back.
      return;
    }
    await context.files.write(manifestPath, captured, mode: fileMode, elevated: elevated);
  }

  /// [manifest] with the value under [variable] replaced by [value], or null when it declares none.
  ///
  /// The value is taken from the line FOLLOWING the one naming the variable, and only the value on
  /// that line is replaced — the indentation and the quoting it was written with stay as they are.
  String? stamp(String manifest, String written) {
    final List<String> lines = manifest.split('\n');
    int stamped = 0;
    for (int i = 0; i < lines.length - 1; i++) {
      if (!lines[i].contains(variable)) {
        continue;
      }
      final RegExpMatch? match = _value.firstMatch(lines[i + 1]);
      if (match == null) {
        continue;
      }
      lines[i + 1] = '${match.group(1)}${match.group(2)}$written${match.group(2)}';
      stamped++;
    }
    return stamped == 0 ? null : lines.join('\n');
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(manifestPath, elevated: elevated)
      ? context.files.read(manifestPath, elevated: elevated)
      : '';

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
