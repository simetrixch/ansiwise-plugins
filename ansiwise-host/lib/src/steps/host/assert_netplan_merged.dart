import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

/// Proves the drop-in folded into the installer's declaration before anything is applied.
///
/// **A drop-in that did not fold looks exactly like one that did.** It is written, it is valid, and
/// the tool accepts it — and it describes the interface a SECOND time. The next time the
/// configuration is applied, the interface comes up with what the second declaration says and
/// without the address configuration the first one gave it, which on a machine reached over that
/// same interface is the end of the session.
///
/// So the merged configuration is read back and both halves must be in it: the address configuration
/// the installer wrote, and the steering this program wrote. One declaration carrying both is the
/// proof; two declarations show up as one of them missing.
final class AssertNetplanMerged extends ObservingStep {
  /// Reads the merged declaration of the public interface back.
  const AssertNetplanMerged();

  /// Builds the step from what the program gave it.
  factory AssertNetplanMerged.fromArguments(Arguments arguments) => const AssertNetplanMerged();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// What the installer's own declaration contributes.
  static const String installerHalf = 'dhcp4';

  /// What this program's drop-in contributes.
  static const String ourHalf = 'routing-policy';

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    if (nic == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so there is no drop-in that had to fold in',
      );
    }

    final CommandResult merged = await context.shell.run(
      Command.observing('netplan', <String>['get', 'ethernets.${nic.device}']),
    );
    if (!merged.ok) {
      return CheckResult.blocked(
        'the merged declaration of ${nic.device} could not be read: ${merged.stderr.trim()}',
      );
    }
    final List<String> missing = <String>[
      for (final String half in <String>[installerHalf, ourHalf])
        if (!merged.stdout.contains(half)) half,
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied(
        'one declaration of ${nic.device} carries both $installerHalf and $ourHalf, so the drop-in '
        'folded in',
      );
    }
    return CheckResult.blocked(
      'the merged declaration of ${nic.device} is missing ${missing.join(' and ')}, so the drop-in '
      'became a second declaration of the interface rather than folding into the installer\'s — '
      'applying it would take the interface\'s address configuration away',
    );
  }
}
