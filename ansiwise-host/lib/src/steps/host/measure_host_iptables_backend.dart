import 'package:ansiwise_core/ansiwise_core.dart';

/// Measures which packet-filtering backend this machine's own tooling is set to.
///
/// The machine chooses between the two by a link, and which one it points at is what the network
/// agent has to be pinned to. Nothing here changes anything: it reads the link, and the step that
/// aligns the agent asks it.
///
/// **The fallback direction is chosen rather than accidental.** A machine this cannot read is
/// reported as being on the modern backend, which is the default of current releases and the safer
/// of the two to be wrong about — pinning the agent to the older one on a machine that is really on
/// the modern one is the split this measurement exists to prevent.
final class MeasureHostIptablesBackend extends ObservingStep {
  /// Measures the backend by reading [alternativesLink].
  const MeasureHostIptablesBackend({required this.alternativesLink});

  /// Builds the step from what the program gave it.
  factory MeasureHostIptablesBackend.fromArguments(Arguments arguments) =>
      MeasureHostIptablesBackend(alternativesLink: arguments.text('alternatives_link'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'alternatives_link',
      kind: ArgumentKind.text,
      describes: 'the link that says which packet-filtering tooling this machine is set to',
      required: false,
      defaultValue: defaultLink,
    ),
  ];

  /// The link the measurement reads.
  static const String defaultLink = '/etc/alternatives/iptables';

  /// The modern backend, and what an unreadable machine is reported as.
  static const String nft = 'nft';

  /// The older backend.
  static const String legacy = 'legacy';

  /// Which backend this machine is set to.
  ///
  /// **This is the ONE reading of this machine's backend, and the step that pins the network agent
  /// takes it from here.** That step lives in the package that owns the cluster client, and that
  /// package and this one do not depend on each other; what carries the value across the line is
  /// the measurement this step publishes and the row below it reads. A second reading over there
  /// would be a second answer to one question, and two answers can come to disagree with nothing to
  /// report it.
  /// **Null is not a value, it is the absence of a reading.** Answering with a backend when neither
  /// link could be read would make "the machine filters with nft" and "nothing here could be read"
  /// the same sentence, and the caller cannot tell them apart afterwards.
  static Future<String?> measure(StepContext context, {String link = defaultLink}) async {
    for (final List<String> argv in <List<String>>[
      <String>['readlink', '-f', link],
      <String>['readlink', '-f', '/usr/sbin/iptables'],
    ]) {
      final CommandResult resolved = await context.shell.run(
        Command.observing(argv.first, arguments: argv.sublist(1)),
      );
      if (!resolved.ok) {
        continue;
      }
      final String target = resolved.trimmed;
      if (target.contains(legacy)) {
        return legacy;
      }
      if (target.contains(nft)) {
        return nft;
      }
    }
    return null;
  }

  /// The link this step reads.
  final String alternativesLink;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? backend = await measure(context, link: alternativesLink);
    if (backend == null) {
      // A measurement that could not be taken is not a measurement, and this step exists to take
      // one. Answering satisfied here would put a sentence in the record naming a backend nothing
      // read, and the engine stamps a satisfied observing row PROVEN.
      return CheckResult.blocked(
        'neither $alternativesLink nor /usr/sbin/iptables could be read, so nothing here says '
        'which backend this machine filters packets with',
      );
    }
    context.measurements.publish(const MeasurementName('backend'), backend);
    return CheckResult.satisfied(
      '$alternativesLink says this machine filters packets with $backend',
    );
  }
}
