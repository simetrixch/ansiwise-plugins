import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// Takes one machine's membership away at the coordinator: its registered nodes, then its user —
/// which is what carries its pre-auth keys away with it.
///
/// **The inverse of minting, by the same doctrine: one coordinator user per machine, named after
/// it.** That naming is what makes this removal exact — destroying the user takes its keys and its
/// nodes with it and touches no other machine. A machine removed any other way keeps something: its
/// node key alone would leave the machine ON the network, and its keys alone would leave a live
/// credential behind for anybody who holds a copy.
///
/// **Nodes first, then the user, and the order is forced from both sides.** The coordinator refuses
/// to destroy a user that still owns nodes; and a machine that already joined carries its own node
/// key from then on, so taking the user's pre-auth keys alone would leave that machine on the
/// network while this step reported it removed.
///
/// **A coordinator that cannot be asked BLOCKS this step — absence is never concluded from
/// silence.** A removal that reported success while the coordinator was merely unreachable leaves
/// the machine's membership standing, and the caller — a removal of the whole machine — goes on to
/// destroy the surfaces that would have made a second attempt easy. Blocking here, with nothing yet
/// destroyed, is what makes running the removal again the whole repair.
final class RemoveTailnetUser extends IrreversibleStep {
  /// Removes the membership of the machine [userAnswer] names.
  const RemoveTailnetUser({
    required this.invocation,
    required this.needsRoot,
    required this.userAnswer,
    required this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory RemoveTailnetUser.fromArguments(Arguments arguments) {
    final List<String> invocation = arguments.textList('headscale');
    if (invocation.isEmpty) {
      throw ArgumentError.value(
        invocation,
        'headscale',
        'names no word at all, so there is nothing to invoke the coordinator\'s admin surface with',
      );
    }
    return RemoveTailnetUser(
      invocation: invocation,
      needsRoot: arguments.has('headscale_needs_root') && arguments.flag('headscale_needs_root'),
      userAnswer: arguments.text('user_answer'),
      runAnswer: arguments.optionalText('run_answer'),
    );
  }

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'headscale',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>['headscale'],
      describes:
          'the words the coordinator\'s admin surface is invoked with, in front of every '
          'subcommand — the default is the plain command on the path, and a coordinator that runs '
          'as a workload names every word of the invocation that reaches into it instead',
    ),
    ArgumentSpec(
      name: 'headscale_needs_root',
      kind: ArgumentKind.flag,
      required: false,
      describes:
          'whether that invocation has to run as root to reach the coordinator at all. Leave it '
          'off for an invocation this account may make',
    ),
    ArgumentSpec(
      name: 'user_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer that holds the machine\'s name at the coordinator — the same '
          'name the credential was minted under, which is what makes this removal find exactly '
          'that machine\'s user, keys and nodes and nothing else\'s',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'invocation words — write "stage" here and every "<stage>" in them is filled with this '
          'run\'s stage. Leave it off where nothing is marked. The answer user_answer names fills '
          'its own slot the same way',
    ),
  ];

  /// The words the admin surface is invoked with, before any slot is filled.
  final List<String> invocation;

  /// Whether the invocation runs as root.
  final bool needsRoot;

  /// The name of the answer that holds the machine's name at the coordinator.
  final String userAnswer;

  /// The name of the answer whose value fills the slot of the same name, or null.
  final String? runAnswer;

  /// How long any one admin call may take: the surface answers from memory, so what this bound
  /// cuts short is only a coordinator that accepted the connection and then hung.
  static const Duration _callBudget = Duration(seconds: 60);

  @override
  String get irreversibleReason =>
      'destroying the user takes its pre-auth keys and its registered nodes with it, and none of '
      'them can be put back: a key is minted, never restored, and a node registers again only by '
      'presenting a fresh credential from the machine itself';

  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, String>? users = await _users(context);
    if (users == null) {
      return CheckResult.blocked(
        'the coordinator\'s admin surface did not answer its own user listing — a membership can '
        'only be reported removed where the coordinator says it holds none, so nothing is '
        'concluded from silence. Asked with: ${_filled(context, invocation).join(' ')}',
      );
    }
    final String name = _name(context);
    return users.containsKey(name)
        ? const CheckResult.ready()
        : CheckResult.satisfied(
            'the coordinator holds no user "$name" — its keys and nodes went with it',
          );
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>[
    ..._filled(context, invocation),
    'users',
    'destroy',
    '--identifier',
    _name(context),
    '--force',
  ]);

  @override
  Future<void> apply(StepContext context) async {
    final List<String> admin = _filled(context, invocation);
    final String name = _name(context);

    final Map<String, String>? users = await _users(context);
    if (users == null) {
      throw StateError('the coordinator\'s admin surface stopped answering its user listing');
    }
    final String? uid = users[name];
    if (uid == null) {
      // Between the check and this moment somebody else removed it — which is the state this step
      // produces, so there is nothing left to do.
      return;
    }

    // The nodes, collected whole before the first delete: the coordinator refuses to destroy a
    // user that still owns one, and a node deleted mid-listing must not hide its siblings.
    final CommandResult listed = await context.shell.run(
      Command.observing(
        admin.first,
        arguments: <String>[...admin.sublist(1), 'nodes', 'list', '--user', uid, '-o', 'json'],
        elevated: needsRoot,
      ),
    );
    if (listed.exitCode != 0) {
      throw StateError(
        'the coordinator\'s admin surface did not answer the node listing of user "$name" — '
        'nothing was removed, so running this again once it answers is the whole repair',
      );
    }
    for (final String node in _nodeIds(listed.stdout)) {
      await _mustRun(context, <String>[
        ...admin,
        'nodes',
        'delete',
        '--identifier',
        node,
        '--force',
      ]);
    }

    await _mustRun(context, <String>[...admin, 'users', 'destroy', '--identifier', uid, '--force']);
  }

  /// The machine's name at the coordinator, read out of the run under the name the row gave.
  String _name(StepContext context) => context.answers.text(userAnswer).trim();

  /// [words] with the slots of the two named answers filled — the same derivation the mint uses,
  /// so a program that renames the answer renames the slot in the same act.
  List<String> _filled(StepContext context, List<String> words) {
    List<String> filled = words;
    for (final String? answer in <String?>[runAnswer, userAnswer]) {
      if (answer == null || !context.answers.has(answer)) {
        continue;
      }
      final String slot = '<$answer>';
      final String value = context.answers.text(answer);
      filled = <String>[for (final String word in filled) word.replaceAll(slot, value)];
    }
    return filled;
  }

  /// The coordinator's users as name to id, or null when the surface did not answer.
  Future<Map<String, String>?> _users(StepContext context) async {
    final List<String> admin = _filled(context, invocation);
    final CommandResult listed = await context.shell.run(
      Command.observing(
        admin.first,
        arguments: <String>[...admin.sublist(1), 'users', 'list', '-o', 'json'],
        elevated: needsRoot,
      ),
    );
    if (listed.exitCode != 0) {
      return null;
    }
    final Object? decoded = _decoded(listed.stdout);
    // The coordinator answers an empty listing as JSON null, and that IS an answer: no users.
    if (decoded == null && listed.stdout.trim() != 'null' && listed.stdout.trim().isNotEmpty) {
      return null;
    }
    if (decoded is! List<Object?>) {
      return <String, String>{};
    }
    final Map<String, String> ids = <String, String>{};
    for (final Object? entry in decoded) {
      if (entry is Map<String, Object?>) {
        final Object? name = entry['name'];
        final Object? id = entry['id'];
        if (name is String && id != null) {
          ids[name] = id.toString();
        }
      }
    }
    return ids;
  }

  /// The ids of the nodes [listing] names, in the order the coordinator gave them.
  static List<String> _nodeIds(String listing) {
    final Object? decoded = _decoded(listing);
    if (decoded is! List<Object?>) {
      return const <String>[];
    }
    return <String>[
      for (final Object? entry in decoded)
        if (entry is Map<String, Object?>)
          if (entry['id'] case final Object id) id.toString(),
    ];
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        argv.first,
        arguments: argv.sublist(1),
        elevated: needsRoot,
        timeout: _callBudget,
      ),
    );
    if (answer.exitCode != 0) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }

  /// [text] as JSON, or null when it is not.
  static Object? _decoded(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
