/// How the MicroK8s snap is asked which of its addons are on, and how its answer is read.
///
/// **These are facts about that snap, and no single step owns them.** Three steps ask the same
/// question — the one that switches addons on, the one that switches them off, and the one that
/// waits for them — so the command and the shape of its answer stand here once instead of on
/// whichever of the three happened to be written first.
///
/// **THE ANSWER IS THE OUTPUT AND NEVER THE EXIT CODE.** The status returns zero on a node that
/// answered, whatever the answer was: a stopped node prints that it is not running, tells the
/// operator to start it, and exits ZERO. Anything reading the exit code would take a node reporting
/// itself down as a yes — a wait satisfied by a cluster that is not running. What decides here is
/// the section of the output, which a stopped node does not print at all.
///
/// **Reading which addons are on means reading the enabled section and nothing else.** The status
/// lists what is on and then what is off, so a search of the whole output finds an addon in the
/// second list and reports it as on — which is the state every addon is in at the moment a wait
/// starts looking.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

/// What is run to learn which addons are on.
///
/// Observing: it prints the state of the node and changes nothing, so a dry run may ask it.
const Command addonStatusCommand = Command.observing('microk8s', <String>['status']);

/// The heading the status writes above what is on.
const String addonsEnabledHeading = 'enabled:';

/// The heading it writes above what is off.
const String addonsDisabledHeading = 'disabled:';

/// Which addons are on, or null when the status could not be run at all.
///
/// Null and an empty set are different answers and a caller has to tell them apart: nothing could be
/// read, against a node that answered and named no addon as on.
Future<Set<String>?> enabledAddons(StepContext context) async {
  final CommandResult status = await context.shell.run(addonStatusCommand);
  if (!status.ok) {
    return null;
  }
  return addonsEnabledIn(status.stdout);
}

/// The addons the enabled section of [status] names.
///
/// A node that printed no such section — one that is not running is the case this was learned on —
/// names nothing, which is what makes a wait keep waiting rather than end on a stopped cluster.
Set<String> addonsEnabledIn(String status) {
  final Set<String> on = <String>{};
  bool inside = false;
  for (final String line in status.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed == addonsEnabledHeading) {
      inside = true;
      continue;
    }
    if (trimmed == addonsDisabledHeading) {
      inside = false;
      continue;
    }
    if (!inside || trimmed.isEmpty) {
      continue;
    }
    final String name = trimmed.split(RegExp(r'\s+')).first;
    if (name.isNotEmpty) {
      on.add(name);
    }
  }
  return on;
}

/// The name of the addon [asked] requests.
///
/// An addon is asked for by its name, and one that takes arguments by its name, a colon and them —
/// that colon is the snap's own notation. The status answers under the NAME alone, so the part
/// before the first colon is what a request is held against; comparing the whole request would find
/// an addon that is on and switch it on again on every run.
String addonNameIn(String asked) => asked.split(':').first;
