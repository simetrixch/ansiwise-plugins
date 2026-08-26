import 'package:ansiwise_core/ansiwise_core.dart';
import 'align_calico_backend.dart';
import 'kubectl.dart';

/// Takes the network agent's rules out of the packet-filtering backend it no longer writes to.
///
/// **What this is for, measured on a machine.** The agent starts with the distribution, works the
/// backend out for itself, and paints a full rule set into whichever one it picked. A later row
/// pins it to the backend the machine actually filters with, and from then on it paints only there.
/// What it does NOT do is go back: the set it wrote before the pin stays on the machine, and the
/// kernel keeps evaluating it.
///
/// That abandoned set is not inert. Its workload dispatch chain admits the interfaces that existed
/// when it was frozen and ends in a DROP for every other, so it passes exactly the pods that were
/// already running and discards everything created afterwards. Measured on a from-zero install
/// (apps3, 2026-08-26): the older set's `cali-from-wl-dispatch` had dropped 4256 packets, every
/// drop counter in the pinned set stood at 0, a pod started after the pin reached neither another
/// pod, nor the node, nor the cluster's own API address, and the older set still listed an
/// interface belonging to a pod that no longer existed. None of it reads as a filtering fault: the
/// ingress controller simply never became ready.
///
/// **Why this is not the earlier version of this idea.** One did exist, inside the pinning step,
/// and it EMPTIED the other backend's tables. That took the port-translation rules for published
/// ports with it and broke the ingress path on a working machine, silently — the same tables carry
/// the distribution's own forwarding rules for the pod network and the translation chains for a
/// published port, and none of that belongs to the agent.
///
/// So nothing here empties a table. It removes the agent's OWN chains, by their name, and the
/// jumps that reach them, by their position in the built-in chain — and it can touch nothing else,
/// because it never names anything else. A table with no such chain is left exactly as it stands.
///
/// **The guard, and why it is not a second measurement.** [backend] arrives from the row that
/// measured the machine, the same value the pinning step is given. Before removing anything, this
/// step reads the agent's own settings and requires them to name that backend. That is not a second
/// answer to which backend the machine filters with — it is the question of whether the pin has
/// actually landed, and it is the difference between removing an abandoned set and removing the
/// live one.
///
/// **It cannot be taken back**, and the reason is not that an undo would be hard to write. Putting
/// the set back would put the defect back, and nothing on the machine wrote down which of those
/// rules the agent would author today — the interfaces they name are gone.
final class RemoveCalicoRulesFromOtherBackend extends IrreversibleStep {
  /// Removes the agent's rules from the backend it is not pinned to.
  const RemoveCalicoRulesFromOtherBackend({this.backend, this.kubectl = const Kubectl()});

  /// Builds the step from what the program gave it.
  factory RemoveCalicoRulesFromOtherBackend.fromArguments(Arguments arguments) =>
      RemoveCalicoRulesFromOtherBackend(
        backend: arguments.optionalText('backend'),
        kubectl: Kubectl.fromArguments(arguments),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // Optional for the same reason the pinning step's is: a row fills it from a MEASUREMENT, and
    // every surface that describes a program before it runs builds the step while that measurement
    // does not exist yet.
    ArgumentSpec(
      name: 'backend',
      kind: ArgumentKind.text,
      describes:
          'the packet-filtering backend this machine is on, taken from the row that measured it — '
          'the agent\'s rules are removed from the OTHER one',
      required: false,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The tables the agent writes into, in the order it is safe to take them apart.
  ///
  /// All four, because the agent's chains stand in all four and a chain left in one of them keeps
  /// its jump reachable. The order between tables does not matter; the order INSIDE a table does,
  /// and that is [_removeFrom].
  static const List<String> tables = <String>['filter', 'nat', 'mangle', 'raw'];

  /// The chains the machine's own filtering starts from, which are never removed.
  ///
  /// A jump out of one of these into an agent chain is removed. The chain itself is the kernel's
  /// and removing it is not something any step may do.
  static const List<String> builtIns = <String>[
    'INPUT',
    'OUTPUT',
    'FORWARD',
    'PREROUTING',
    'POSTROUTING',
  ];

  /// How the agent names everything it writes.
  ///
  /// Both its chains (`cali-…`) and the comment it puts on every rule it adds to a built-in chain
  /// (`cali:…`) start with it, which is what makes its own work separable from everybody else's in
  /// the same table.
  static const String marker = 'cali';

  /// The packet-filtering backend this machine is on, passed from a measurement.
  final String? backend;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'the rules the network agent left in the backend it no longer writes to are deleted, and '
      'nothing on this machine holds a copy of them — the agent authors its set from the pods that '
      'exist when it paints, so what is removed here names interfaces that are already gone and '
      'could not be authored again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? other = _other;
    if (other == null) {
      return CheckResult.blocked(
        backend == null
            ? 'nothing measured which backend this machine filters packets with, so nothing says '
                  'which of the two the agent has abandoned'
            : '"$backend" is not a backend this step knows — a measurement of this machine names '
                  'either $_nft or $_legacy',
      );
    }
    final String? pinned = await _pinnedBackend(context);
    if (pinned == null) {
      return const CheckResult.blocked(
        '${AlignCalicoBackend.configuration} could not be read, so nothing says which backend the '
        'agent writes to — and removing the rules of the backend it is actually using would take '
        'the cluster\'s network with it',
      );
    }
    if (!_names(pinned, backend!)) {
      return CheckResult.blocked(
        'the agent is pinned to $pinned while this machine filters packets with $backend, so the '
        'set this step would remove is the one the agent is still writing to — the row that pins '
        'the agent has to have landed before this one runs',
      );
    }
    final Map<String, _Leftovers> found = await _survey(context, other);
    final int chains = found.values.fold(0, (int sum, _Leftovers t) => sum + t.chains.length);
    final int jumps = found.values.fold(0, (int sum, _Leftovers t) => sum + t.jumps.length);
    if (chains == 0 && jumps == 0) {
      return CheckResult.satisfied(
        'the $other backend holds no chain of the network agent, over ${tables.length} table(s)',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? other = _other;
    if (other == null) {
      return const StepPlan.nothing(
        'the row above this one measures which backend this machine filters packets with, and '
        'until that has run there is nothing here to say which set the agent has abandoned',
      );
    }
    final Map<String, _Leftovers> found = await _survey(context, other);
    final List<String> said = <String>[];
    String? first;
    String? firstTable;
    for (final String table in tables) {
      final _Leftovers left = found[table] ?? const _Leftovers(<String>[], <int>{});
      if (left.chains.isEmpty && left.jumps.isEmpty) {
        continue;
      }
      said.add(
        '$table: ${left.jumps.length} jump(s) out of the machine\'s own chains, then '
        '${left.chains.length} chain(s) of the agent',
      );
      first ??= left.chains.isEmpty ? null : left.chains.first;
      firstTable ??= first == null ? null : table;
    }
    if (said.isEmpty) {
      return StepPlan.nothing('the $other backend holds no chain of the network agent');
    }
    // The whole of what would go is written to the record, because ONE command cannot carry it and
    // a dry run that showed only the first would understate the change by every table but one. The
    // plan names a command, as every plan does; this line is what the operator reads beside it.
    context.log.info(
      'would take the network agent\'s rules out of the $other backend, which it no longer writes '
      'to — ${said.join('; ')}. Nothing outside those chains is named, so nothing outside them can '
      'be reached',
    );
    return StepPlan.argv(<String>[
      _rules(other),
      '-t',
      firstTable ?? tables.first,
      '-X',
      first ?? '$marker-INPUT',
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String other = _otherOrThrow;
    int chains = 0;
    int jumps = 0;
    for (final String table in tables) {
      final _Leftovers left = await _readTable(context, other, table);
      if (left.chains.isEmpty && left.jumps.isEmpty) {
        continue;
      }
      await _removeFrom(context, other, table, left);
      chains += left.chains.length;
      jumps += left.jumps.length;
    }
    context.log.info(
      'the network agent\'s rules are out of the $other backend: $jumps jump(s) and $chains '
      'chain(s) over ${tables.length} table(s). Every pod created from here on is judged by the '
      'set the agent actually writes',
    );
  }

  /// Takes one table apart, in the only order that works.
  ///
  /// The jumps go FIRST, highest position first so the ones below keep their numbers, because a
  /// chain something still jumps to cannot be deleted. Then every agent chain is emptied — which is
  /// what breaks the references they hold to EACH OTHER — and only then are they deleted.
  Future<void> _removeFrom(
    StepContext context,
    String backend,
    String table,
    _Leftovers left,
  ) async {
    for (final MapEntry<String, List<int>> chain in left.jumpsByChain.entries) {
      final List<int> positions = chain.value.toList()..sort();
      for (final int position in positions.reversed) {
        await _mustRun(context, backend, <String>['-t', table, '-D', chain.key, '$position']);
      }
    }
    for (final String chain in left.chains) {
      await _mustRun(context, backend, <String>['-t', table, '-F', chain]);
    }
    for (final String chain in left.chains) {
      await _mustRun(context, backend, <String>['-t', table, '-X', chain]);
    }
  }

  /// What the agent left behind in every table of [backend].
  Future<Map<String, _Leftovers>> _survey(StepContext context, String backend) async {
    final Map<String, _Leftovers> found = <String, _Leftovers>{};
    for (final String table in tables) {
      found[table] = await _readTable(context, backend, table);
    }
    return found;
  }

  /// What the agent left behind in one table, read out of that backend's own dump.
  ///
  /// The dump is used and not `-L`, because it states a chain's rules in the order the kernel holds
  /// them: the position of an `-A` line inside its chain IS the number `-D` takes. That is what
  /// lets a jump be removed by position instead of by re-quoting a rule that carries a quoted
  /// comment — a rule spec written back by hand is a rule spec that can differ.
  Future<_Leftovers> _readTable(StepContext context, String backend, String table) async {
    final CommandResult dumped = await context.shell.run(
      Command.detailed(
        _save(backend),
        arguments: <String>['-t', table],
        observes: true,
        elevated: true,
      ),
    );
    if (!dumped.ok) {
      // A backend with nothing in it answers with an error on some machines and an empty dump on
      // others. Neither is a leftover, and neither is something to remove.
      return const _Leftovers(<String>[], <int>{});
    }
    final List<String> chains = <String>[];
    final Set<int> jumps = <int>{};
    final Map<String, int> seen = <String, int>{for (final String chain in builtIns) chain: 0};
    final Map<String, List<int>> byChain = <String, List<int>>{};
    for (final String line in dumped.stdout.split('\n')) {
      final String row = line.trim();
      if (row.startsWith(':$marker-')) {
        chains.add(row.substring(1).split(' ').first);
        continue;
      }
      if (!row.startsWith('-A ')) {
        continue;
      }
      final List<String> words = row.split(' ');
      if (words.length < 2) {
        continue;
      }
      final String chain = words[1];
      if (!seen.containsKey(chain)) {
        continue;
      }
      // Counted for EVERY rule of a built-in chain and not only the agent's, because the number
      // `-D` takes is the position among all of them.
      final int position = seen[chain]! + 1;
      seen[chain] = position;
      if (!row.contains(marker)) {
        continue;
      }
      jumps.add(position);
      (byChain[chain] ??= <int>[]).add(position);
    }
    return _Leftovers(chains, jumps, byChain);
  }

  /// The backend the agent says it writes to, or null where its settings cannot be read.
  Future<String?> _pinnedBackend(StepContext context) async {
    final CommandResult live = await context.shell.run(
      kubectl.observing(<String>[
        'get',
        AlignCalicoBackend.configuration,
        '-o',
        'jsonpath={.spec.iptablesBackend}',
      ]),
    );
    if (!live.ok) {
      return null;
    }
    final String value = live.trimmed;
    // The empty string is the agent carrying no pin at all, which means it is still working the
    // backend out for itself — and a step that removed a set on that basis would be removing one
    // the agent may pick again at its next start.
    return value.isEmpty ? AlignCalicoBackend.auto : value;
  }

  /// The older backend, as the machine's own tooling names it.
  static const String _legacy = 'legacy';

  /// The modern backend, as the machine's own tooling names it.
  static const String _nft = 'nft';

  /// The backend this machine does NOT filter with, or null where nothing measured it.
  String? get _other => switch (backend) {
    _legacy => _nft,
    _nft => _legacy,
    _ => null,
  };

  /// The same, for the members that run only after [check] has admitted the step.
  String get _otherOrThrow =>
      _other ??
      (throw StateError('no measurement said which backend this machine filters packets with'));

  /// The dump program of [backend].
  static String _save(String backend) => 'iptables-$backend-save';

  /// The rule program of [backend].
  static String _rules(String backend) => 'iptables-$backend';

  /// Whether the agent's pin [value] names the backend [wanted], however it is spelled.
  static bool _names(String value, String wanted) => value.toLowerCase() == wanted.toLowerCase();

  Future<void> _mustRun(StepContext context, String backend, List<String> argv) async {
    final Command command = Command.detailed(_rules(backend), arguments: argv, elevated: true);
    final CommandResult answer = await context.shell.run(command);
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>[command.executable, ...command.arguments],
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}

/// What one table of the abandoned backend still holds.
final class _Leftovers {
  /// Records the agent's chains and the positions of the jumps that reach them.
  const _Leftovers(this.chains, this.jumps, [this.jumpsByChain = const <String, List<int>>{}]);

  /// The agent's own chains in this table, by name.
  final List<String> chains;

  /// Every position removed, across all of the machine's own chains — a count, not an address.
  final Set<int> jumps;

  /// Where each of those positions is, which is what makes it an address.
  final Map<String, List<int>> jumpsByChain;
}
