import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'helm.dart';

/// Makes one chart repository known to helm on this machine.
///
/// A release installs from a repository helm already knows, so each repository has to be
/// registered before the first release that names it. This is that, once per repository.
///
/// **It is keyed on the name AND the address.** A repository already registered under this name but
/// pointing somewhere else is the case worth catching: helm answers every later question about it
/// from the wrong index, and the release that installs from it is a chart nobody chose. So the check
/// asks what the name currently resolves to rather than whether the name is taken.
final class HelmRepository extends ReversibleStep<String?> {
  /// Registers the chart repository at [url] under [name].
  const HelmRepository({required this.name, required this.url, this.helm = const Helm()});

  /// Builds the step from what the program gave it.
  factory HelmRepository.fromArguments(Arguments arguments) => HelmRepository(
    name: arguments.text('name'),
    url: arguments.text('url'),
    helm: Helm.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    Helm.argument,
    Helm.elevationArgument,
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the short name a release names this repository by',
    ),
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      describes: 'where the repository publishes its index',
    ),
  ];

  /// The short name helm holds it under.
  final String name;

  /// Where it publishes.
  final String url;

  /// How helm is reached on this machine: the words it is started with, and whether they need root.
  final Helm helm;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? registered = await _registeredUrl(context);
    if (registered == null) {
      return const CheckResult.ready();
    }
    return registered == url
        ? CheckResult.satisfied('helm holds "$name" at $url')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_add);

  @override
  Future<void> apply(StepContext context) async {
    // `--force-update` and not an add that fails on a name already taken: this step converges a name
    // pointing at the wrong address, which is the case its check exists to find.
    final CommandResult added = await context.shell.run(helm.command(_addArguments));
    if (!added.ok) {
      // BOTH STREAMS. helm writes the sentence that explains a failure to whichever stream it feels
      // like — `Release "x" does not exist. Installing it now.` goes to stdout while the error goes
      // to stderr — so a refusal carrying one of them shows an operator half of what happened. This
      // is the row directly above the release, and it is where the release's own misdirection sent
      // people to look.
      throw CommandFailed(
        argv: _add,
        exitCode: added.exitCode,
        stdout: added.stdout,
        stderr: added.stderr,
      );
    }
  }

  /// The address helm holds [name] at right now, or null when it holds no such name.
  ///
  /// Read before the add, and the add is a `--force-update`: it overwrites the address a name was
  /// already registered at, and afterwards nothing on the machine says what that address was. The
  /// undo puts it back from here; where helm held none, the registration this run made stands.
  @override
  Future<String?> capture(StepContext context) => _registeredUrl(context);

  /// Puts back the address the add overwrote, and leaves a fresh registration standing.
  ///
  /// The overwrite is the only damage the add can do: an address that was registered before the run
  /// belongs to whatever registered it, and after `--force-update` nothing but [captured] still
  /// says what it was. A name helm held nothing under is the other case, and removing it was
  /// measured doing harm on an unwind: any genuine failure at a row below took the repository away,
  /// so the NEXT attempt failed earlier, at the release with `repo <name> not found` — pointing at
  /// this row, where nothing was wrong. A registration is a name resolving to a chart index; it
  /// installs nothing and nothing consults it unless a row names it, so leaving it costs the
  /// machine nothing and removing it costs the next run its diagnosis.
  ///
  /// The line below is for the record: the unwind writes "taken back" around every undo, and this
  /// one deliberately leaves something standing.
  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      context.log.info(
        'the registration of "$name" stands: helm held no such name before this run, and removing '
        'it would only make the next attempt fail at the release that installs from it',
      );
      return;
    }
    await context.shell.run(
      helm.command(<String>['repo', 'add', name, captured, '--force-update']),
    );
  }

  /// helm's own half of the add, which is what a step writes and hands over.
  List<String> get _addArguments => <String>['repo', 'add', name, url, '--force-update'];

  /// The whole command line, including how helm is reached, which is what a plan shows the operator
  /// and what a failure names.
  List<String> get _add => helm.argv(_addArguments);

  /// What helm currently resolves [name] to, or null when it holds no such name.
  ///
  /// A machine with no repositories at all makes `helm repo list` answer non-zero, which is not a
  /// failure to report — it is the same answer as a machine that holds other repositories but not
  /// this one.
  Future<String?> _registeredUrl(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      helm.observing(<String>['repo', 'list', '-o', 'json']),
    );
    if (!listed.ok || listed.trimmed.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(listed.trimmed);
    } on FormatException {
      return null;
    }
    if (decoded is! List<Object?>) {
      return null;
    }
    for (final Object? entry in decoded) {
      if (entry is Map<String, Object?> && entry['name'] == name) {
        final Object? held = entry['url'];
        return held is String ? held : null;
      }
    }
    return null;
  }
}
