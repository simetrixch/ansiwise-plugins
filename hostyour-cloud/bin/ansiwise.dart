// The composition root, and the only place that decides what the real implementations are.
//
// `dart:io` is used here for the process's own arguments, its exit code and its standard streams,
// and for nothing else. Everything this does to a machine goes through the same four ports every
// step uses, built once here and handed down.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'mode',
      allowed: <String>['test', 'dry', 'run'],
      help: 'test measures the machine, dry says what would change, run does it',
    )
    ..addOption('run', help: 'the identifier of this run, when something else chose it')
    ..addOption('resume', help: 'the identifier of a run this one continues')
    ..addOption('programs', defaultsTo: 'programs', help: 'where the program files are')
    ..addOption(
      'config',
      defaultsTo: Configuration.defaultFileName,
      help: 'the file naming which plugins are active',
    )
    ..addOption('runs', defaultsTo: RunDirectory.defaultRoot, help: 'where records are kept')
    ..addOption(
      'answers',
      help:
          'a JSON object of what the program declares it must be told; a path, because a '
          'credential must not appear in a process listing. "-" reads it from standard input, '
          'which is how a run started over the API is told, since a file of raw answers would be '
          'the one thing beside a redacted record that is not redacted',
    )
    ..addOption(
      'log-level',
      allowed: <String>['debug', 'info', 'warn', 'error'],
      help:
          'the quietest level this run writes; overrides log_level in the configuration, which is '
          'where it normally stands so that handing this binary its config file is enough',
    )
    ..addOption('role', defaultsTo: 'master', help: 'what this machine is')
    ..addOption('stage', defaultsTo: 'dev')
    ..addOption('fqdn', defaultsTo: '', help: 'the domain name of this installation')
    ..addFlag('no-unwind', help: 'disable unwinding steps on failure so evidence is preserved for debugging')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(argv);
  } on FormatException catch (bad) {
    stderr.writeln(bad.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  final List<String> rest = options.rest;
  if (options.flag('help') || rest.isEmpty) {
    stdout
      ..writeln('ansiwise <program> --mode test|dry|run [--answers <file>]')
      ..writeln('ansiwise serve')
      ..writeln()
      ..writeln(parser.usage);
    exit(rest.isEmpty && !options.flag('help') ? 64 : 0);
  }

  // Not const: the entropy port holds the platform's cryptographic generator, which is created
  // once and cannot be built at compile time.
  final Machine machine = Machine(
    shell: const RealShell(),
    files: const RealFiles(),
    http: const RealHttp(),
    clock: const RealClock(),
    entropy: RealEntropy(),
  );

  // Every plugin this binary was compiled with. Dart ahead of time loads no code that was not
  // built in, so this list is a fact of the build — and the configuration below decides which of
  // them are on, which is a fact of the installation.
  const PluginSet plugins = compiledPlugins;

  final String configuration = options.option('config') ?? Configuration.defaultFileName;
  final Registry registry;
  // The configuration decides it and the command line overrides it, which is the ordinary
  // precedence: the file is what this installation always wants, the flag is what this one run
  // wants. Declared here so a refusal below cannot leave it unset.
  LogLevel logLevel = LogLevel.info;
  // Whether a real run still needs a clean dry run behind it. An installation may waive it, and
  // the waiver is read here rather than assumed, so the gate a run meets is the one this
  // installation configured rather than the one the code happens to default to.
  bool requireDryRun = true;
  // Whether the engine is allowed to unwind on failure.
  bool allowUnwind = true;
  try {
    if (!await machine.files.exists(configuration)) {
      throw PluginRejected(
        'there is no $configuration, so nothing says which plugins are active\n'
        'write one naming at least one of: ${plugins.names.join(', ')}',
      );
    }
    final Configuration active = await Configuration.load(
      files: machine.files,
      path: configuration,
    );
    registry = plugins.activate(active.plugins);
    logLevel = active.logLevel;
    requireDryRun = active.requireDryRun;
    allowUnwind = active.allowUnwind;
  } on PluginRejected catch (refused) {
    stderr.writeln(refused.message);
    exit(78);
  }

  if (options.option('log-level') case final String asked) {
    logLevel = LogLevel.values.firstWhere((LogLevel each) => each.name == asked);
  }

  final String programs = options.option('programs') ?? 'programs';
  if (!await machine.files.exists(programs)) {
    // Named rather than thrown. This is what an operator meets when they run the binary from
    // somewhere other than the installation it belongs to, and a stack trace tells them nothing
    // about which of the two is wrong.
    stderr.writeln('there are no programs at "$programs"');
    stderr.writeln('run this where the installation is, or say --programs <directory>');
    exit(66);
  }

  final Catalogue catalogue;
  try {
    catalogue = await LoadedCatalogue.load(
      files: machine.files,
      directory: programs,
      registry: registry,
    );
  } on ProgramInvalid catch (invalid) {
    // The first gate, before anything is looked at or touched. Every problem at once, so an
    // operator fixing a program file learns everything in one run.
    stderr.writeln(invalid.toString());
    exit(65);
  }

  final RunDirectory directory = RunDirectory(options.option('runs') ?? RunDirectory.defaultRoot);
  final FileRunStore store = FileRunStore(directory: directory);

  if (rest.first == 'serve') {
    await _serve(
      machine: machine,
      catalogue: catalogue,
      store: store,
      directory: directory,
      options: options,
      requireDryRun: requireDryRun,
    );
    return;
  }

  exit(
    await _runProgram(
      machine: machine,
      catalogue: catalogue,
      store: store,
      directory: directory,
      options: options,
      argv: argv,
      program: ProgramName(rest.first),
      logLevel: logLevel,
      requireDryRun: requireDryRun,
      allowUnwind: allowUnwind && !options.flag('no-unwind'),
    ),
  );
}

Future<void> _serve({
  required bool requireDryRun,
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required RunDirectory directory,
  required ArgResults options,
}) async {
  final DeploymentApi api = DeploymentApi(
    programs: ProgramsEndpoint(catalogue),
    runs: RunsEndpoint(
      store: store,
      launcher: DetachedLauncher(
        executable: Platform.resolvedExecutable,
        workingDirectory: Directory.current.path,
        newRunId: () => _newRunId(machine.clock),
      ),
      catalogue: catalogue,
      gate: Gate(store, requireDryRun: requireDryRun),
      json: const RecordCodec(),
      commit: () => _commit(machine),
    ),
    events: EventsEndpoint(store: store, json: const RecordCodec()),
  );

  // The session's own standard input and output are the connection. Nothing listens.
  await ChannelHttpServer(api, incoming: stdin, outgoing: stdout).serve();
}

Future<int> _runProgram({
  required bool requireDryRun,
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required RunDirectory directory,
  required ArgResults options,
  required List<String> argv,
  required ProgramName program,
  required LogLevel logLevel,
  required bool allowUnwind,
}) async {
  final ResolvedProgram? resolved = catalogue.byName(program);
  if (resolved == null) {
    stderr.writeln('no program is called "$program"');
    stderr.writeln(
      'there is: ${catalogue.programs.map((ResolvedProgram p) => p.declared.name).join(', ')}',
    );
    return 65;
  }

  final Mode mode = _modeNamed(options.option('mode'));

  // Checked before the gate and before the first step: an installation stopped halfway for a value
  // somebody could have supplied at the start is the worst of both. The same call the API makes, so
  // the two doors cannot come to disagree about what a program needs.
  final Arguments answers;
  try {
    answers = resolved.declared.answers.validate(
      await _answersIn(machine, options.option('answers')),
      program: program.value,
    );
  } on AnswersRejected catch (refused) {
    stderr.writeln(refused.message);
    return 65;
  } on FormatException catch (unreadable) {
    stderr.writeln('--answers: ${unreadable.message}');
    return 65;
  }

  final String commit = await _commit(machine);
  final String fingerprint = fingerprintOf(program: resolved, commit: commit, answers: answers);

  // Said BEFORE the run, and by the one implementation. Every step declares whether it can be taken
  // back, so where a run stops being reversible is a fact this program can state rather than a
  // surprise the operator meets at the failure. Printed for a dry run as much as for a real one:
  // the dry run is where somebody decides, and a boundary they read afterwards is a boundary they
  // could not act on.
  if (pointOfNoReturnSaid(resolved) case final String boundary) {
    stdout.writeln(boundary);
  }

  try {
    await Gate(
      store,
      requireDryRun: requireDryRun,
    ).admit(mode: mode, program: program, fingerprint: fingerprint);
  } on GateNotMet catch (refusal) {
    stderr.writeln(refusal.message);
    return 69;
  }

  final String? chosen = options.option('run');
  final RunId id = chosen == null || chosen.isEmpty ? _newRunId(machine.clock) : RunId(chosen);

  // Resuming runs the same program again rather than skipping to a remembered position. Every step
  // that already did its work answers that there is nothing to do, and a machine somebody touched
  // in between is measured again instead of assumed. What the identifier is for is the record: it
  // joins the two halves of one story, which two unrelated runs would not.
  final String? continues = options.option('resume');
  RunId? resumes;
  if (continues != null && continues.isNotEmpty) {
    final RunRecord? earlier = await store.read(RunId(continues));
    if (earlier == null) {
      stderr.writeln('there is no run called "$continues" to continue');
      return 65;
    }
    if (earlier.fingerprint != fingerprint) {
      stderr.writeln('run "$continues" was a different input, so this would not be continuing it');
      stderr.writeln('start a fresh run instead, or say why the input changed');
      return 65;
    }
    resumes = earlier.id;
  }

  final RunRecord header = RunRecord(
    id: id,
    program: program,
    mode: mode,
    argv: argv,
    start: machine.clock.now(),
    stage: Stage(options.option('stage') ?? 'dev'),
    role: Role(options.option('role') ?? 'master'),
    fqdn: Fqdn(options.option('fqdn') ?? ''),
    commit: commit,
    fingerprint: fingerprint,
    resumes: resumes,
  );

  // Built from the VALUES of everything declared secret, on BOTH surfaces a value arrives by.
  // Everything on its way into the record passes through here, which is what makes a record safe to
  // read and to paste into a message when something has gone wrong.
  //
  // An ANSWER is the surface an operator fills in. An ARGUMENT is the surface a program row writes,
  // and a step may declare one secret too - a token a row carries, a key a plugin needs. Built from
  // the answers alone, a secret argument's value would reach a world-readable record through the
  // command line a step composes and through the plan it prints, while ArgumentSpec.secret says the
  // value is never sent back out.
  final Redactor redactor = Redactor(<String>[
    for (final String name in resolved.declared.answers.secretNames)
      if (answers.optionalText(name) case final String value) value,
    for (final ResolvedStep step in resolved.steps)
      for (final ArgumentSpec spec in step.registered.arguments)
        if (spec.secret)
          if (step.entry.arguments.optionalText(spec.name) case final String value) value,
  ]);

  final FileRecorder recorder = await FileRecorder.open(
    id: id,
    directory: directory,
    clock: machine.clock,
    redactor: redactor,
  );

  // The header goes to disk before the first step. A run that is killed a minute later is then
  // still a run somebody can find and read — and without this, nothing would answer `GET /runs`
  // and the gate could never find the dry run it is looking for.
  await recorder.save(header);

  final RunRecord record = await Runner(
    machine: machine,
    recorder: recorder,
    redactor: redactor,
    logLevel: logLevel,
    allowUnwind: allowUnwind,
  ).run(program: resolved, mode: mode, header: header, answers: answers);
  await recorder.save(record);

  stdout.writeln('${record.id}  ${record.program} ${record.mode.name}  exit ${record.exitCode}  ${record.standings.summary}');
  for (final String issue in record.issues) {
    stdout.writeln('  issue: $issue');
  }
  return record.exitCode ?? 1;
}

/// What the file at [path] says the operator supplied, or nothing when no file was named.
///
/// A PATH and not the values themselves. A credential handed on the command line stands in the
/// process listing for every account on the machine, and `Command` has no standard input by design —
/// so the one thing that crosses argv here is where to read, never what was read.
///
/// Throws [FormatException] when the file is not a JSON object, which is what the caller turns into
/// a refusal naming the file rather than a stack trace.
Future<Map<String, Object?>> _answersIn(Machine machine, String? path) async {
  if (path == null || path.isEmpty) {
    return const <String, Object?>{};
  }

  final String text;
  if (path == '-') {
    // From standard input, which is how the launcher tells a detached run: not argv, where a
    // credential lands in every process listing, and not a file, which would be raw where the
    // record beside it is redacted — and would outlive the run unless somebody remembered it.
    //
    // Read here in the composition root rather than through the files port, because standard input
    // is not a file and there is nothing for that port to be asked about.
    text = await stdin.transform(utf8.decoder).join();
    if (text.trim().isEmpty) {
      throw const FormatException('--answers - was given and standard input was empty');
    }
  } else {
    if (!await machine.files.exists(path)) {
      throw FormatException('there is no file at "$path"');
    }
    text = await machine.files.read(path);
  }

  final Object? parsed = jsonDecode(text);
  if (parsed is! Map<String, Object?>) {
    final String where = path == '-' ? 'standard input' : '"$path"';
    throw FormatException('$where holds ${parsed.runtimeType}, and answers are a JSON object');
  }
  // A list arrives as List<dynamic> from the decoder, and every answer that holds a list holds a
  // list of text — so the element type is fixed here rather than left to fail the kind check with a
  // message about a type nobody wrote.
  return <String, Object?>{
    for (final MapEntry<String, Object?> answer in parsed.entries)
      answer.key: switch (answer.value) {
        final List<Object?> texts => <String>[for (final Object? each in texts) '$each'],
        final Object? value => value,
      },
  };
}

Mode _modeNamed(String? name) {
  for (final Mode mode in Mode.values) {
    if (mode.flag == name) {
      return mode;
    }
  }
  // No default that acts. A run started without saying which of the three it is would be a run
  // whose safety nobody chose, so the safe one is the only sensible answer.
  return Mode.test;
}

RunId _newRunId(Clock clock) {
  final DateTime now = clock.now();
  final String stamp = now.toIso8601String().replaceAll(RegExp(r'[-:.]'), '').split('T').join('T');
  return RunId('${stamp.substring(0, 15)}Z-$pid');
}

/// The commit this installation's branch is on, which is part of what makes an input the same.
///
/// Empty when this is not a checkout — a machine that was given a built binary and no repository
/// still runs, and its fingerprint simply carries no commit.
Future<String> _commit(Machine machine) async {
  final CommandResult head = await machine.shell.run(
    const Command.observing('git', <String>['rev-parse', 'HEAD']),
  );
  return head.ok ? head.trimmed : '';
}
