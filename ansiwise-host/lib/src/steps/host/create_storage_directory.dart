import 'package:ansiwise_api/ansiwise_api.dart';

/// Makes the directory on the data filesystem that every volume of this cluster lives under.
///
/// **The permissions are set when it is made and never re-applied.** A directory that is already
/// there is left exactly as it is: whatever the cluster wrote under it is owned by the accounts the
/// cluster runs as, and reaching in to change permissions after that is a change nobody asked for
/// with data behind it.
final class CreateStorageDirectory extends IrreversibleStep {
  /// Makes the answered storage directory with the permissions [mode].
  const CreateStorageDirectory({required this.mode});

  /// Builds the step from what the program gave it.
  factory CreateStorageDirectory.fromArguments(Arguments arguments) =>
      CreateStorageDirectory(mode: arguments.integer('mode'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'mode',
      kind: ArgumentKind.integer,
      describes: 'the permission bits it is made with, as a decimal number',
      required: false,
      // 0755 as a number, because a program file writes a value and not a notation.
      defaultValue: 493,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Where this installation keeps the data its volumes are backed by, or empty when the machine
  /// keeps it where the snap puts it. One machine's disks, so it is answered.
  static const List<String> answers = <String>['storage_directory'];

  /// The permission bits it is made with.
  final int mode;

  @override
  String get irreversibleReason =>
      'every volume the cluster hands to a workload is written under this directory, so removing it '
      'destroys the data of everything that ever claimed one — and nothing else on the machine holds '
      'a copy of any of it';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (context.answers.text('storage_directory').isEmpty) {
      return const CheckResult.satisfied(
        'this machine has no separate data filesystem, so there is no directory to make',
      );
    }
    if (await context.files.exists(context.answers.text('storage_directory'))) {
      return CheckResult.satisfied('${context.answers.text('storage_directory')} is there');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['mkdir', '-p', context.answers.text('storage_directory')]);

  @override
  Future<void> apply(StepContext context) async {
    await context.files.createDirectory(context.answers.text('storage_directory'), mode: mode);
  }
}
