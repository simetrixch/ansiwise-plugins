import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry_mirror.dart';

/// Decides, before anything is installed, whether this machine can pull images through the mirror.
///
/// **Why it is a step of its own and not part of the write.** The mirror is written part way through
/// an install, and a credential that is merely unfilled would stop the run there with the machine
/// half built. The same question asked first costs nothing and refuses while nothing is installed.
/// The step that writes the mirror asks it again, so the same guard holds when that step is run on
/// its own.
///
/// **Only two states are refusals, and both are fixed by editing one file and running again.** A
/// file of credentials written with the line endings of another operating system keeps an invisible
/// character inside every value, and what that produces is a rejected credential that looks
/// perfectly correct on screen. A credential that is blank or still the placeholder an example file
/// ships is not a credential.
///
/// **Everything else passes, and each for its own reason.** The machine the MIRROR runs on cannot
/// pull through it — at that point in its own install the mirror does not exist. A machine whose
/// mirror address cannot be read from the profile would have no mirror to write. And a machine with
/// no credential file at all is the unattended base install of a machine the credentials reach
/// later.
///
/// **These two states are refused rather than warned for one measured reason.** A machine without
/// the mirror sends every pull to the rate-limited public path with no further sign of it, and
/// nothing later comes back to write the mirror on its own.
final class PreflightRegistryPullCredential extends ObservingStep {
  /// Decides whether the machine can pull through the mirror [layout] describes.
  const PreflightRegistryPullCredential({required this.layout, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory PreflightRegistryPullCredential.fromArguments(Arguments arguments) =>
      PreflightRegistryPullCredential(
        layout: RegistryMirror.fromArguments(arguments),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  ///
  /// The layout and nothing besides: this gate reads exactly what the writer reads, so a row that
  /// pointed one of them at another file would be refused for the argument it left out rather than
  /// measuring one thing and configuring another.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...RegistryMirror.arguments,
    elevationArgument,
  ];

  /// Where the mirror is written down and what it is reached with.
  final RegistryMirror layout;

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
        'this machine is the one the mirror runs on, and at this point in its own install that '
        'mirror does not exist — so nothing pulls through it here',
      );
    }

    final String secrets = layout.secretsIn(context);
    final String? host = await layout.mirrorHostIn(context, elevated: elevated);
    if (host == null) {
      return CheckResult.satisfied(
        "the mirror's address is not readable from ${layout.profile}, so no mirror is written and "
        'pulls stay on the public path',
      );
    }
    if (!await context.files.exists(secrets, elevated: elevated)) {
      context.log.warn(
        '$secrets is not on this machine, so no mirror is written and every pull goes to the '
        'rate-limited public path. That is the unattended base install of a machine whose '
        'credentials arrive later; fill the file in and run this program again to write the mirror.',
      );
      return const CheckResult.satisfied('there is no credential file on this machine yet');
    }

    final PullCredential credential = await layout.readCredential(
      context,
      secrets,
      host,
      elevated: elevated,
    );
    if (credential.refusal case final String refusal) {
      return CheckResult.blocked('$secrets: $refusal');
    }
    return CheckResult.satisfied('$secrets carries a usable pull credential for $host');
  }
}
