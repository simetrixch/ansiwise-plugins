import 'package:ansiwise_core/ansiwise_core.dart';
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
  /// Reads the merged declaration of the public interface back, and looks for [installerKey] and
  /// [dropInKey] in it.
  const AssertNetplanMerged({required this.installerKey, required this.dropInKey});

  /// Builds the step from what the program gave it.
  factory AssertNetplanMerged.fromArguments(Arguments arguments) => AssertNetplanMerged(
    installerKey: arguments.text('installer_key'),
    dropInKey: arguments.text('drop_in_key'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // Neither key has a default. What the installer wrote depends on how the machine was addressed
    // — an image that takes its address from the network names one key, a statically addressed one
    // names another — and a default would refuse a correctly configured machine for looking
    // different from the author's. What the drop-in wrote is decided by the template the program
    // renders. So both are read out of the program that knows them.
    ArgumentSpec(
      name: 'installer_key',
      kind: ArgumentKind.text,
      describes:
          "a key of the interface's own declaration as the machine's installer wrote it, which "
          'proves that declaration is still in the merged reading',
    ),
    ArgumentSpec(
      name: 'drop_in_key',
      kind: ArgumentKind.text,
      describes:
          'a key the drop-in this program wrote contributes, which proves the drop-in folded into '
          "the installer's declaration rather than becoming a second one",
    ),
  ];

  /// A key of the installer's own declaration.
  final String installerKey;

  /// A key the drop-in contributes.
  final String dropInKey;

  @override
  bool get restsOnAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    if (nic == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so there is no drop-in that had to fold in',
      );
    }

    final CommandResult merged = await context.shell.run(
      Command.observing('netplan', arguments: <String>['get', 'ethernets.${nic.device}']),
    );
    if (!merged.ok) {
      return CheckResult.blocked(
        'the merged declaration of ${nic.device} could not be read: ${merged.stderr.trim()}',
      );
    }
    final List<String> missing = <String>[
      for (final String half in <String>[installerKey, dropInKey])
        if (!merged.stdout.contains(half)) half,
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied(
        'one declaration of ${nic.device} carries both $installerKey and $dropInKey, so the drop-in '
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
