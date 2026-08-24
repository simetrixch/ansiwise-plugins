import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Materializes one field of one entry into a file on this machine.
///
/// **Why this exists rather than a step that mints where the file is.** A credential two sides hold
/// — a store entry a workload reads and a file a machine service presents or verifies — must be ONE
/// value, and a value comes into being once, in the store. This is the machine-file counterpart of
/// materializing an entry onto a cluster: the entry is written by an earlier row, and this step is
/// how its value reaches the one file a program row names. Nothing mints here, and a field that is
/// not in the entry is a skipped earlier row, reported as exactly that.
///
/// **The check asks whether the file is there, and never what it holds.** Comparing would mean
/// reading the credential out of the store on every converge run in order to decide whether to
/// write it again, and the store is the truth either way. What that costs is stated rather than
/// hidden: a file holding an OLD value is not put right by a re-run — taking the file away is what
/// asks for it to be materialized again, which is also this platform's one way of rotating a
/// materialized credential.
///
/// **The value reaches the machine through the files port and never through an argument.** An
/// argument is visible in a process listing to every process on the machine and lands in the
/// record; a file write records its path and its size and nothing of its content.
final class FileFromVault extends ReversibleStep<bool> {
  /// Writes [field] of the entry at [path] into the file at [filePath].
  const FileFromVault({
    required this.repository,
    required this.mount,
    required this.path,
    required this.field,
    required this.filePath,
    required this.fileMode,
    required this.layout,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory FileFromVault.fromArguments(Arguments arguments) => FileFromVault(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    field: arguments.text('field'),
    filePath: arguments.text('file_path'),
    fileMode: arguments.integer('file_mode'),
    layout: VaultLayout.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this run reads from, which carries the profile and Vault's own credential "
          'file',
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes: 'the key-value mount the entry stands on',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the entry, with the marked slots this run fills',
    ),
    ArgumentSpec(
      name: 'field',
      kind: ArgumentKind.text,
      describes: 'the one field of the entry whose value becomes the whole of the file',
    ),
    ArgumentSpec(
      name: 'file_path',
      kind: ArgumentKind.text,
      describes:
          'the file the value is written to, on this machine, with the marked slots this run fills '
          '— the same slots the entry path takes, because two installations at different points of '
          'the axis the layout names write two different files',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the file is written with, as the number the machine stores — 384 is '
          'the mode of a file only its owner may read, which is what a materialized credential '
          'wants',
    ),
    ...VaultLayout.arguments,
    elevationArgument,
  ];

  /// The entry is written by an earlier row of the same program, so in the two modes that change
  /// nothing this step reports what it would do rather than failing on a value nobody wrote yet.
  @override
  bool get restsOnAnEarlierStep => true;

  /// The checkout this run reads from.
  final String repository;

  /// The mount.
  final String mount;

  /// The entry, before its marked slots are filled.
  final String path;

  /// The field whose value becomes the file.
  final String field;

  /// The file the value is written to, before its marked slots are filled.
  final String filePath;

  /// The permissions the file is written with.
  final int fileMode;

  /// Where Vault's own facts stand, and under which names — the same profile and credential file
  /// every other step of this family reads, declared under the same names.
  final VaultLayout layout;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  /// The mode the directory around the file is made with, which is 0700: a listable directory
  /// around a credential file still says which secret lives where.
  static const int directoryMode = 448;

  /// Where the value is written on this machine, with the slots of this run filled in.
  ///
  /// **The same filling the entry path gets, and the same the credential file gets.** A machine can
  /// carry one installation per point of the axis the layout names, so a row writing `<stage>` in a
  /// file name means one file per stage — and without this the name was taken literally, which
  /// creates a file whose name carries the angle brackets and which the next reader spelling the
  /// slot the same way then finds. Two readers agreeing on a wrong name is green on both sides and
  /// right on neither.
  ///
  /// Filled from the ANSWERS and not from the profile, because this is a path on this machine: the
  /// profile's own values are an address, a cluster name and a mount, and none of them names a file
  /// here. A slot nothing fills is left standing and refused by name where the path is used.
  String fileFor(StepContext context) => layout.runAnswerFilled(context, filePath);

  @override
  Future<CheckResult> check(StepContext context) async {
    final String file = fileFor(context);
    if (unfilledSlotRefusal(file) case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    // Whether the file is there, and never what it holds. Comparing would mean reading the
    // credential out of the store on every converge run, and the store is the truth either way —
    // a file to be replaced is a file somebody deletes.
    return await context.files.exists(file, elevated: elevated)
        ? CheckResult.satisfied('$file is on this machine, holding what $path held')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    // The read it would perform and the file it would fill, and nothing of the value: a plan is
    // written into the record an operator keeps.
    return StepPlan.request(
      'GET',
      '${vault.url}/v1/${_dataPath(entry.value ?? '')}',
      body: 'the field $field, written to ${fileFor(context)} and nowhere else',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String file = fileFor(context);
    if (unfilledSlotRefusal(file) case final String refusal) {
      throw StateError(refusal);
    }
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      throw StateError(refusal);
    }

    final String dataPath = _dataPath(entry.value ?? '');
    final HttpAnswer held = await context.http.send(
      vaultRead(vault.url ?? '', dataPath, token: token.value ?? ''),
    );
    final VaultReading reading = readingOf(held, path: dataPath);
    if (reading case final VaultUnreadable refused) {
      throw StateError(refused.because);
    }
    final Object? data = reading is VaultHeld ? reading.data['data'] : null;
    final Object? value = data is Map<String, Object?> ? data[field] : null;
    if (value is! String || value.isEmpty) {
      throw StateError(
        '$field of $dataPath is what $file is written from, and it is not there. The entry is '
        'written by an earlier row, so a run that reaches this one without it has skipped that row '
        'rather than failed it',
      );
    }

    await context.files.createDirectory(
      _directoryOf(file),
      mode: directoryMode,
      elevated: elevated,
    );
    await context.files.write(file, value, mode: fileMode, elevated: elevated);
  }

  /// Whether the file was already there, read before the apply.
  ///
  /// A file that was there stays through an undo: this run did not put it there, and taking it
  /// away would take a credential from whatever was already presenting it.
  @override
  Future<bool> capture(StepContext context) =>
      context.files.exists(fileFor(context), elevated: elevated);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(fileFor(context), elevated: elevated);
  }

  /// Where the entry [at] has its data, under Vault's version one API.
  String _dataPath(String at) => '$mount/data/$at';

  /// The directory [path] stands in, or the root where it stands in none.
  static String _directoryOf(String path) {
    final int cut = path.lastIndexOf('/');
    return cut <= 0 ? '/' : path.substring(0, cut);
  }
}
