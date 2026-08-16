import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';

/// A machine in memory, and the context one step of this plugin is asked its questions in.
final class HostMachine {
  HostMachine({FakeShell? shell, FakeFiles? files, FakeClock? clock})
    : shell = shell ?? FakeShell(),
      files = files ?? FakeFiles(),
      clock = clock ?? FakeClock() {
    // The templates travel with the programs of an installation, so a machine one of these steps
    // meets carries them the way it carries its programs. A machine that carries none is what the
    // blocked check is for, and the test that wants that case takes one away.
    this.files.contents.addAll(fixtureTemplates());
  }

  final FakeShell shell;
  final FakeFiles files;
  final FakeClock clock;

  /// Everything the log was told, so a test can assert what a step said about what it found.
  final List<String> said = <String>[];

  /// Everything published to the measurements sink.
  final Map<MeasurementName, String> published = <MeasurementName, String>{};

  /// The context [step] is run in, with [arguments] where the step reads any.
  ///
  /// [answers] carries what an operator stated about this installation, and every step gets them
  /// whether or not it reads any: a step reads its answers BY NAME out of the run, so a context
  /// built without them would measure the step against an empty bag rather than an installation.
  StepContext contextFor(
    StepName step, [
    Arguments arguments = Arguments.none,
    Arguments answers = hostAnswers,
  ]) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: clock,
    entropy: FakeEntropy(),
    log: _CollectingLog(said),
    step: step,
    arguments: arguments,
    answers: answers,
    facts: Facts.none,
    measurements: _FakeMeasurementSink(published),
  );

  /// Every command that changed something, in the order it ran.
  List<String> get changing => <String>[
    for (final Command command in shell.commands)
      if (!command.observes) command.argv.join(' '),
  ];
}

/// The account that operates the machine in these fixtures.
const String operatorUser = 'operator';

/// Where that account lives.
const String operatorHome = '/home/$operatorUser';

/// What an operator stated about the installation these fixtures describe.
const Arguments hostAnswers = Arguments(hostAnswerValues);

/// The same installation with [changed] answered differently.
Arguments hostAnswering(Map<String, Object> changed) =>
    Arguments(<String, Object>{...hostAnswerValues, ...changed});

/// The values [hostAnswers] and [hostAnswering] are both built from.
const Map<String, Object> hostAnswerValues = <String, Object>{
  'operator_user': operatorUser,
  'storage_path': '',
  'storage_directory': '',
};

/// Where each template fixture stands, as a program row would name it.
const String connmarkNftTableTemplate = 'test/templates/connmark-nft-table.tpl';

/// See [connmarkNftTableTemplate].
const String netplanPublicSrcRoutingTemplate = 'test/templates/netplan-public-src-routing.tpl';

/// See [connmarkNftTableTemplate].
const String publicSrcRoutingScriptTemplate = 'test/templates/public-src-routing-script.tpl';

/// See [connmarkNftTableTemplate].
const String publicSrcRoutingUnitTemplate = 'test/templates/public-src-routing-unit.tpl';

/// Every template fixture, keyed by the path a program row would name it under.
///
/// READ OFF THE DISK, never pasted in. A test carrying its own copy of the text would measure that
/// copy: the template could name a slot nothing fills, or lose one a step fills, and every
/// assertion here would go on passing while the file that ships is broken.
Map<String, String> fixtureTemplates() => <String, String>{
  for (final String path in <String>[
    connmarkNftTableTemplate,
    netplanPublicSrcRoutingTemplate,
    publicSrcRoutingScriptTemplate,
    publicSrcRoutingUnitTemplate,
  ])
    path: File(path).readAsStringSync(),
};

final class _CollectingLog implements Logger {
  const _CollectingLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}

final class _FakeMeasurementSink implements MeasurementSink {
  const _FakeMeasurementSink(this.published);

  final Map<MeasurementName, String> published;

  @override
  void publish(MeasurementName name, String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'cannot be empty');
    }
    published[name] = value;
  }
}
