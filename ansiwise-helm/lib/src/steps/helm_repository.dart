import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

import 'helm_command.dart';

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
  const HelmRepository({
    required this.name,
    required this.url,
    this.helm = const <String>['helm'],
  });

  /// Builds the step from what the program gave it.
  factory HelmRepository.fromArguments(Arguments arguments) =>
      HelmRepository(
        name: arguments.text('name'),
        url: arguments.text('url'),
        helm: arguments.textList('helm_command'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    helmCommandArgument,
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

  /// How helm is reached on this machine, as the program and any arguments before helm's own.
  final List<String> helm;

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
    final CommandResult added = await context.shell.run(helmCommand(helm, _add.sublist(helm.length)));
    if (!added.ok) {
      throw CommandFailed(argv: _add, exitCode: added.exitCode, stdout: '',
        stderr: added.stderr);
    }
  }

  /// The address helm holds [name] at right now, or null when it holds no such name.
  ///
  /// Read before the add, and the add is a `--force-update`: it overwrites the address a name was
  /// already registered at, and afterwards nothing on the machine says what that address was. The
  /// undo puts it back from here, and removes the name only where helm held none.
  @override
  Future<String?> capture(StepContext context) => _registeredUrl(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.shell.run(helmCommand(helm, <String>['repo', 'remove', name]));
      return;
    }
    await context.shell.run(
      helmCommand(helm, <String>['repo', 'add', name, captured, '--force-update']),
    );
  }

  List<String> get _add => <String>[...helm, 'repo', 'add', name, url, '--force-update'];

  /// What helm currently resolves [name] to, or null when it holds no such name.
  ///
  /// A machine with no repositories at all makes `helm repo list` answer non-zero, which is not a
  /// failure to report — it is the same answer as a machine that holds other repositories but not
  /// this one.
  Future<String?> _registeredUrl(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      helmCommand(helm, <String>['repo', 'list', '-o', 'json'], observes: true),
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
