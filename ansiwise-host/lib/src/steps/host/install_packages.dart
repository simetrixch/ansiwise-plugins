import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts the packages a machine needs onto it, refreshing the lists first.
///
/// **Refreshing the package lists is part of this step and not a step of its own.** `apt-get update`
/// has no target state — it always does work, and there is nothing about a machine that says
/// whether it has been done. A step like that cannot answer whether it still needs to run, so it
/// cannot be idempotent and cannot have a verdict that means anything. Here it is how this step
/// reaches its target state, and the target state is that the packages are installed.
///
/// **The verdict comes from the packages being installed, never from what apt returned.** The shell
/// this replaces has a comment saying its failure branch fires "when apt did not produce the
/// command": an install can report success and leave nothing behind.
final class InstallPackages extends ReversibleStep<List<String>> {
  /// Installs [packages].
  const InstallPackages(this.packages);

  /// Builds the step from what the program gave it.
  factory InstallPackages.fromArguments(Arguments arguments) =>
      InstallPackages(arguments.textList('packages'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'packages',
      kind: ArgumentKind.textList,
      describes: 'the packages this machine needs before anything else runs',
    ),
  ];

  /// The packages that have to be installed.
  final List<String> packages;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> missing = await _missing(context);
    if (missing.isEmpty) {
      return CheckResult.satisfied('${packages.join(', ')} are installed');
    }
    return const CheckResult.ready();
  }

  /// What every apt command here says before its own words: wait for the lock, do not fail on it.
  ///
  /// **Ubuntu runs `unattended-upgrades` on its own, shortly after boot.** A machine that was just
  /// restored or just provisioned is therefore holding the dpkg lock through the first minutes of
  /// its life — which is exactly when a first installation reaches this step, four rows into the
  /// first program it runs. Without this the run ends at
  /// `Could not get lock /var/lib/dpkg/lock-frontend`, and the operator is sent to look at a
  /// package manager that is behaving perfectly normally.
  ///
  /// **apt already knows how to wait**, and says so while it does. This asks it to, for a bound
  /// that stands in the argv — so a record shows how long the run was willing to wait, rather than
  /// leaving a reader to guess whether it waited at all.
  ///
  /// **What it does NOT do is take the lock away.** Stopping or masking `unattended-upgrades` would
  /// trade a machine's security updates for a quieter installation, which is not a trade this makes.
  static const List<String> _waitingForTheLock = <String>['-o', 'DPkg::Lock::Timeout=600'];

  @override
  Future<StepPlan> plan(StepContext context) async {
    final List<String> missing = await _missing(context);
    return StepPlan.argv(<String>[
      'apt-get',
      ..._waitingForTheLock,
      'install',
      '--yes',
      ...missing,
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final List<String> missing = await _missing(context);
    context.log.info('installing ${missing.join(', ')}');

    final CommandResult refreshed = await context.shell.run(
      const Command.detailed(
        'apt-get',
        arguments: <String>[..._waitingForTheLock, 'update'],
        environment: _quiet,
        elevated: true,
      ),
    );
    if (!refreshed.ok) {
      throw CommandFailed(
        argv: <String>['apt-get', ..._waitingForTheLock, 'update'],
        exitCode: refreshed.exitCode,
        stdout: '',
        stderr: refreshed.stderr,
      );
    }

    final CommandResult installed = await context.shell.run(
      Command.detailed(
        'apt-get',
        arguments: <String>[..._waitingForTheLock, 'install', '--yes', ...missing],
        environment: _quiet,
        elevated: true,
      ),
    );
    if (!installed.ok) {
      throw CommandFailed(
        argv: <String>['apt-get', ..._waitingForTheLock, 'install', '--yes', ...missing],
        exitCode: installed.exitCode,
        stdout: '',
        stderr: installed.stderr,
      );
    }
  }

  /// Which of [packages] the machine already carried before this step ran.
  ///
  /// This is what "was not before" is read from, and it can only be read here: after the install
  /// every one of them is present, so the machine no longer says which of them it brought. A machine
  /// that already carried `git` had it removed by an undo cleaning up after an unrelated failure,
  /// because the only question being asked was whether the package was there now.
  @override
  Future<List<String>> capture(StepContext context) async => <String>[
    for (final String package in packages)
      if (await _isInstalled(context, package)) package,
  ];

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    // Only what is here now and was not before. Removing everything this step names would take away
    // packages the machine already carried, which nobody asked for — and undo runs while cleaning up
    // after a failure, the worst moment for a surprise.
    final List<String> installed = <String>[
      for (final String package in packages)
        if (!captured.contains(package))
          if (await _isInstalled(context, package)) package,
    ];
    if (installed.isEmpty) {
      return;
    }
    await context.shell.run(
      Command.detailed(
        'apt-get',
        arguments: <String>[..._waitingForTheLock, 'remove', '--yes', ...installed],
        environment: _quiet,
        elevated: true,
      ),
    );
  }

  Future<List<String>> _missing(StepContext context) async => <String>[
    for (final String package in packages)
      if (!await _isInstalled(context, package)) package,
  ];

  /// Whether dpkg reports [package] as installed.
  ///
  /// `dpkg-query -W -f=${Status}` prints a three-word status, and only `install ok installed` means
  /// the package is there. A package that was removed but not purged is still known to dpkg and
  /// still exits zero, which is why the status is read rather than the exit code.
  Future<bool> _isInstalled(StepContext context, String package) async {
    final CommandResult status = await context.shell.run(
      Command.observing('dpkg-query', arguments: <String>[r'-W', r'-f=${Status}', package]),
    );
    return status.ok && status.trimmed == 'install ok installed';
  }

  /// What keeps apt from stopping to ask a question nobody is there to answer.
  ///
  /// There is no terminal: this runs from a session the client opened, and a prompt would hang the
  /// run until the deadline rather than fail it.
  static const Map<String, String> _quiet = <String, String>{'DEBIAN_FRONTEND': 'noninteractive'};
}
