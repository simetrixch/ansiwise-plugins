import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry_mirror.dart';

/// Decides, before anything is installed, whether this machine can pull images through the mirror.
///
/// **Why it is a step of its own and not part of the write.** The mirror is written part way through
/// an install, and a credential that is merely unfilled would stop the run there with the machine
/// half built. The same question asked first costs nothing and refuses while nothing is installed.
/// The step that writes the mirror asks it again, so the same guard holds when that step is run on
/// its own.
///
/// **A machine that pulls through the mirror and holds no credential for it is refused.** The
/// credential is either a value this run carries under the name the row gives, or a key of a file on
/// the machine; holding neither is refused by both names, as is a credential that is blank, still
/// the placeholder an example file ships, or not an encoded pull configuration for the mirror's
/// address. A file of credentials written with the line endings of another operating system keeps an
/// invisible character inside every value, which produces a rejected credential that looks perfectly
/// correct on screen, and that is refused too.
///
/// **Two states pass, and each for its own reason.** The machine the MIRROR runs on cannot pull
/// through it — at that point in its own install the mirror does not exist. And a machine whose
/// mirror address cannot be read from the profile has no mirror to pull through at all.
///
/// **Everything else is refused rather than warned for one measured reason.** A machine without the
/// mirror sends every pull to the rate-limited public path with no further sign of it, and nothing
/// later comes back to write the mirror on its own.
final class RequireRegistryPullCredential extends ObservingStep {
  /// Decides whether the machine can pull through the mirror [layout] describes.
  const RequireRegistryPullCredential({required this.layout, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory RequireRegistryPullCredential.fromArguments(Arguments arguments) =>
      RequireRegistryPullCredential(
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

    final String? host = await layout.mirrorHostIn(context, elevated: elevated);
    if (host == null) {
      return CheckResult.satisfied(
        "the mirror's address is not readable from ${layout.profileIn(context)}, so no mirror is written and "
        'pulls stay on the public path',
      );
    }

    final PullCredential credential = await layout.credentialFor(context, host, elevated: elevated);
    if (credential.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return CheckResult.satisfied(
      '${layout.credentialSourceIn(context)} carries a usable pull credential for $host',
    );
  }
}
