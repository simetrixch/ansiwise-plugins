/// How a cluster snap is asked about its addons, and how its answer is read.
///
/// **The COMMANDS come from the row, and the shape of the answer is code.** Three steps ask the
/// same question — the one that switches addons on, the one that switches them off, and the one
/// that waits for them — so the reading stands here once instead of on whichever of the three
/// happened to be written first. Which snap runs the cluster is a product's choice, so the words
/// each command is run with are required arguments and stand in that product's program row; the
/// exit-code and section knowledge below is a fact of the answer format and is mechanism, not
/// configuration.
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

import 'package:ansiwise_core/ansiwise_core.dart';

/// The argument every step that reads the addon status declares.
///
/// Required and without a default: the verbs are the cluster snap's own, and which snap runs the
/// cluster is the product's choice, so a value here would decide it for every caller.
const ArgumentSpec statusCommandArgument = ArgumentSpec(
  name: 'status_command',
  kind: ArgumentKind.textList,
  describes:
      'the command that prints the state of the node with its addons, given as the program and '
      'its arguments — it must only look, and its output carries the enabled and disabled sections '
      'this step reads',
);

/// The argument every step that switches an addon on declares.
const ArgumentSpec enableCommandArgument = ArgumentSpec(
  name: 'enable_command',
  kind: ArgumentKind.textList,
  describes:
      'the command an addon request is appended to in order to switch that addon on, given as the '
      'program and its arguments',
);

/// The argument every step that switches an addon off declares.
const ArgumentSpec disableCommandArgument = ArgumentSpec(
  name: 'disable_command',
  kind: ArgumentKind.textList,
  describes:
      'the command an addon name is appended to in order to switch that addon off, given as the '
      'program and its arguments',
);

/// The heading the status writes above what is on.
const String addonsEnabledHeading = 'enabled:';

/// The heading it writes above what is off.
const String addonsDisabledHeading = 'disabled:';

/// Which addons are on, asked with [statusCommand], or null when it could not be run at all.
///
/// Observing on the row's word: the command prints the state of the node and changes nothing, so a
/// dry run may ask it.
///
/// [elevated] is the row's answer and is the same one the switching uses. A step that ASKS as the
/// operator and SWITCHES as root reads a refusal instead of a state — on the snap this was learned
/// on, an account outside the tool's group gets that refusal with an exit code of one and nothing on
/// standard error, so what the caller sees is "the addons could not be read" and not the reason.
///
/// Null and an empty set are different answers and a caller has to tell them apart: nothing could be
/// read, against a node that answered and named no addon as on.
Future<Set<String>?> enabledAddons(
  StepContext context,
  List<String> statusCommand, {
  bool elevated = false,
}) async {
  final CommandResult status = await context.shell.run(
    Command.observing(statusCommand.first, arguments: statusCommand.sublist(1), elevated: elevated),
  );
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
