import 'package:ansiwise_api/ansiwise_api.dart';

/// Switches on the addons this platform is built out of, in the order the program lists them.
///
/// **The order is load-bearing and the failure of getting it wrong is completely silent.** The
/// access-control addon has to be first. Until it is on, the API server allows everything: every
/// access rule the platform later applies is accepted, looks correct, and enforces nothing — so
/// every workload can read every secret on the cluster, and nothing anywhere says so.
///
/// **Reading which addons are on means reading the enabled section and nothing else.** The status
/// lists what is on and then what is off, so a search of the whole output finds an addon in the
/// second list and reports it as on. The section between the two headings is what answers.
///
/// **The name servers can only be given when the name addon is switched on for the first time.**
/// After that the argument has no effect at all, and the only thing that changes them is editing the
/// live configuration — which the step that does exactly that is for.
final class EnableAddons extends ReversibleStep {
  /// Switches on each of [addons], in order.
  const EnableAddons({required this.addons, required this.dnsUpstreamServers});

  /// Builds the step from what the program gave it.
  factory EnableAddons.fromArguments(Arguments arguments) => EnableAddons(
    addons: arguments.textList('addons'),
    dnsUpstreamServers: arguments.textList('dns_upstream_servers'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'addons',
      kind: ArgumentKind.textList,
      describes:
          'the addons this cluster runs, in the order they are switched on — access control '
          'first, or every access rule after it is accepted and enforces nothing',
    ),
    ArgumentSpec(
      name: 'dns_upstream_servers',
      kind: ArgumentKind.textList,
      describes:
          'the name servers to give the name addon when it is switched on for the first time',
      required: false,
      defaultValue: <String>[],
    ),
  ];

  /// The addon whose enable argument carries the name servers.
  static const String dnsAddon = 'dns';

  /// The heading the status writes above what is on.
  static const String enabledHeading = 'enabled:';

  /// The heading it writes above what is off.
  static const String disabledHeading = 'disabled:';

  /// Which addons are on.
  ///
  /// Shared with the steps that wait for them and that switch some of them off, so the reading of
  /// the status lives in one place. A reading that searched the whole output would find an addon in
  /// the list of what is OFF and report it as on.
  static Future<Set<String>?> enabled(StepContext context) async {
    final CommandResult status = await context.shell.run(
      const Command.observing('microk8s', <String>['status']),
    );
    if (!status.ok) {
      return null;
    }
    return readEnabled(status.stdout);
  }

  /// The addons the enabled section of [status] names.
  static Set<String> readEnabled(String status) {
    final Set<String> on = <String>{};
    bool inside = false;
    for (final String line in status.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed == enabledHeading) {
        inside = true;
        continue;
      }
      if (trimmed == disabledHeading) {
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

  /// The addons this cluster runs.
  final List<String> addons;

  /// The name servers given to the name addon on a first switch-on.
  final List<String> dnsUpstreamServers;

  @override
  Future<CheckResult> check(StepContext context) async {
    final Set<String>? on = await enabled(context);
    if (on == null) {
      return const CheckResult.blocked(
        'the addons could not be read, so nothing says which of them are on',
      );
    }
    final List<String> missing = _missing(on);
    if (missing.isEmpty) {
      return CheckResult.satisfied('${addons.join(', ')} are on');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final Set<String> on = await enabled(context) ?? const <String>{};
    return StepPlan.argv(<String>[
      'microk8s',
      'enable',
      for (final String addon in _missing(on)) _asked(addon),
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final Set<String> on = await enabled(context) ?? const <String>{};
    // One at a time and in the order the program wrote them, so an addon that fails is named and
    // nothing after it is switched on against a cluster that is missing what comes before it.
    for (final String addon in _missing(on)) {
      final List<String> argv = <String>['microk8s', 'enable', _asked(addon)];
      final CommandResult switched = await context.shell.run(Command(argv.first, argv.sublist(1)));
      if (!switched.ok) {
        throw CommandFailed(argv: argv, exitCode: switched.exitCode, stderr: switched.stderr);
      }
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    // Only the ones that are on now. Which of them this step switched on is not recorded anywhere,
    // and an undo runs while cleaning up after a failure — the worst moment to switch off something
    // that was already running.
    final Set<String> on = await enabled(context) ?? const <String>{};
    for (final String addon in addons.reversed) {
      if (!on.contains(addon)) {
        continue;
      }
      await context.shell.run(Command('microk8s', <String>['disable', addon]));
    }
  }

  /// How an addon is asked for: the name, and for the name addon the servers behind a colon.
  String _asked(String addon) => addon == dnsAddon && dnsUpstreamServers.isNotEmpty
      ? '$addon:${dnsUpstreamServers.join(',')}'
      : addon;

  List<String> _missing(Set<String> on) => <String>[
    for (final String addon in addons)
      if (!on.contains(addon)) addon,
  ];
}
