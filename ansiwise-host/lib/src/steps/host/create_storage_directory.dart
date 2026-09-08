import 'package:ansiwise_core/ansiwise_core.dart';

import 'data_disk.dart';

/// Makes the directory on the data disk that every volume of this cluster lives under.
///
/// **The permissions are set when it is made and never re-applied.** A directory that is already
/// there is left exactly as it is: whatever the cluster wrote under it is owned by the accounts the
/// cluster runs as, and reaching in to change permissions after that is a change nobody asked for
/// with data behind it.
final class CreateStorageDirectory extends IrreversibleStep {
  /// Makes [subdirectory] under the data disk's mount with the permissions [mode].
  const CreateStorageDirectory({
    required this.subdirectory,
    required this.mode,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory CreateStorageDirectory.fromArguments(Arguments arguments) => CreateStorageDirectory(
    subdirectory: arguments.text('subdirectory'),
    mode: arguments.integer('mode'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    subdirectoryArgument,
    ArgumentSpec(
      name: 'mode',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 0,
        most: 4095,
        because:
            'a permission mode is twelve bits, so 4095 is 0o7777 and nothing outside it is a mode',
      ),
      describes: 'the permission bits it is made with, as a decimal number',
      required: false,
      // 0755 as a number, because a program file writes a value and not a notation.
      defaultValue: 493,
    ),
    elevationArgument,
  ];

  /// The name of the directory under the data disk's mount.
  final String subdirectory;

  /// The permission bits it is made with.
  final int mode;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'every volume the cluster hands to a workload is written under this directory, so removing it '
      'destroys the data of everything that ever claimed one — and nothing else on the machine holds '
      'a copy of any of it';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? mount = await dataDiskMount(context);
    if (mount == null) {
      return const CheckResult.satisfied(
        'this machine has no data disk, so there is no directory to make',
      );
    }
    final String directory = '$mount/$subdirectory';
    if (await context.files.exists(directory, elevated: elevated)) {
      return CheckResult.satisfied('the data disk is mounted at $mount, and $directory is there');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? mount = await dataDiskMount(context);
    return mount == null
        ? const StepPlan.nothing('this machine has no data disk, so there is no directory to make')
        : StepPlan.argv(<String>['mkdir', '-p', '$mount/$subdirectory']);
  }

  @override
  Future<void> apply(StepContext context) async {
    // Only reached once the check has found the data disk, because it answers satisfied otherwise.
    final String mount = (await dataDiskMount(context))!;
    await context.files.createDirectory('$mount/$subdirectory', mode: mode, elevated: elevated);
  }
}
