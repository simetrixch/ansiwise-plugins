import 'package:ansiwise_api/ansiwise_api.dart';

/// Puts on the machine the two things every tool download needs, and judges by the tools themselves.
///
/// **The package manager's answer is not the verdict, and this is the incident.** Automatic updates
/// hold the package lock for minutes after a machine boots, so an install exits with a failure on a
/// freshly provisioned machine that already carries both of these — and the server release ships
/// both. Reading that answer would skip every tool below over a lock, on a machine where nothing was
/// missing.
///
/// **One gate up front rather than three failures further down.** One of these fetches the tools and
/// the other unpacks one of them. Without them the downloads fail one at a time and the run reports
/// three unrelated problems instead of the one.
final class EnsureToolPrerequisites extends IrreversibleStep {
  /// Puts [packages] on the machine, judging by the commands they carry.
  const EnsureToolPrerequisites({required this.packages});

  /// Builds the step from what the program gave it.
  factory EnsureToolPrerequisites.fromArguments(Arguments arguments) =>
      EnsureToolPrerequisites(packages: arguments.textList('packages'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'packages',
      kind: ArgumentKind.textList,
      describes:
          'what every tool download needs, each one both a package and the command it carries',
      required: false,
      defaultValue: <String>['curl', 'unzip'],
    ),
  ];

  /// What keeps the package manager from stopping to ask a question nobody is there to answer.
  static const Map<String, String> quiet = <String, String>{'DEBIAN_FRONTEND': 'noninteractive'};

  /// What every tool download needs.
  final List<String> packages;

  @override
  String get irreversibleReason =>
      'nothing recorded which of these the machine already carried, so removing them again would '
      'take away tools that were there before this ran — and one of them is how anything else is '
      'fetched at all';

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> missing = await _missing(context);
    if (missing.isEmpty) {
      return CheckResult.satisfied('${packages.join(', ')} are on the path');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['apt-get', 'install', '--yes', ...await _missing(context)]);

  @override
  Future<void> apply(StepContext context) async {
    final List<String> missing = await _missing(context);
    context.log.info('installing ${missing.join(', ')}');
    // What either of these returned is deliberately not read. The verdict comes from the check that
    // follows, which asks the machine whether the commands are there.
    await context.shell.run(
      const Command.detailed('apt-get', arguments: <String>['update'], environment: quiet),
    );
    await context.shell.run(
      Command.detailed(
        'apt-get',
        arguments: <String>['install', '--yes', ...missing],
        environment: quiet,
      ),
    );
  }

  Future<List<String>> _missing(StepContext context) async => <String>[
    for (final String package in packages)
      if (!await onPath(context, package)) package,
  ];

  /// Whether [command] is on the path.
  ///
  /// Shared with every tool step, because the presence of a command is the one question all of them
  /// begin with and a second copy of it would be a second answer.
  static Future<bool> onPath(StepContext context, String command) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('command', <String>['-v', command]),
    );
    return answer.ok && answer.trimmed.isNotEmpty;
  }
}
