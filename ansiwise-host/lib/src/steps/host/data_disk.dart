/// Reading the disk a cluster's volumes belong on, for the three rows that place them.
///
/// **THE MACHINE IS ASKED, NEVER A PERSON.** An answer is what a form gets when nobody types a
/// path: empty. The rows then skip, and a mounted data disk goes on holding nothing while the boot
/// disk fills, with nothing reporting it. Read off the kernel's own mount table, the reading is the
/// same whoever runs the program, so a second run cannot answer it differently from the first and
/// move the volumes out from under the cluster.
///
/// **What counts as the data disk:** a mount of a real block device, under `/dev/`, whose target is
/// neither the root filesystem, nor under the boot partition, nor under the snap tree — those last
/// are the cluster's own volumes appearing as mounts, and taking one would point the storage at
/// itself. The shallowest one left wins, ties broken alphabetically: a machine built with one data
/// disk has exactly one, and a mount nested under it is a part of it.
///
/// **A machine with no such disk is answered with null**, and every row keeps the snap's own default.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// The kernel's mount table: one line per mount, the target then the source, and nothing else.
const Command mountTableCommand = Command.observing(
  'findmnt',
  arguments: <String>['-rno', 'TARGET,SOURCE'],
);

/// The name of the directory on the data disk that every volume of this cluster lives in.
///
/// No default: the name is the product's, and a package that spelled it would name one product's
/// cluster. It is a NAME under the mount and not a path — the mount is read off the machine, and the
/// row that makes the directory and the row that links to it join the same name onto it.
const ArgumentSpec subdirectoryArgument = ArgumentSpec(
  name: 'subdirectory',
  kind: ArgumentKind.text,
  describes:
      "the name of the directory under the data disk's mount that every volume of this cluster "
      'lives in — a name under the mount, not a path',
);

/// Where this machine's data disk is mounted, or null when it carries none.
///
/// A mount table that could not be read is not an empty one. Read as empty it would put the volumes
/// on the boot disk with nothing saying so, so the failure is thrown and the row fails with it.
Future<String?> dataDiskMount(StepContext context) async {
  final CommandResult table = await context.shell.run(mountTableCommand);
  if (!table.ok) {
    throw CommandFailed(
      argv: mountTableCommand.argv,
      exitCode: table.exitCode,
      stdout: table.stdout,
      stderr: table.stderr,
    );
  }
  return dataDiskMountFrom(table.stdout);
}

/// The data disk's mount out of [mountTable], as [mountTableCommand] prints it, or null when no
/// line of it names one.
String? dataDiskMountFrom(String mountTable) {
  final List<String> candidates = <String>[];
  for (final String line in mountTable.split('\n')) {
    final List<String> columns = line.trim().split(RegExp(r'\s+'));
    if (columns.length < 2 || !columns[1].startsWith('/dev/') || _keptByTheSystem(columns[0])) {
      continue;
    }
    candidates.add(columns[0]);
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((String a, String b) {
    final int byDepth = a.split('/').length.compareTo(b.split('/').length);
    return byDepth != 0 ? byDepth : a.compareTo(b);
  });
  return candidates.first;
}

/// Whether [target] is a mount the system keeps for itself rather than a disk for data.
bool _keptByTheSystem(String target) =>
    target == '/' ||
    target.startsWith('/boot') ||
    target.startsWith('/snap') ||
    target.startsWith('/var/snap');
