import 'dart:convert';

import 'package:ansiwise_authentik/ansiwise_authentik.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// Saying whether the provider is still standing on its out-of-box flow, and at which address.
///
/// **What every probe here is really about: the sentence must be false when the flow is closed.**
/// A row that said "waiting for its first person" on any run at all would be worth nothing — the
/// second run of the same installation, an hour after somebody took the account, would say it
/// again. So the two directions are measured against the same step with the same row, and the only
/// thing that differs is what the provider answers.
void main() {
  const String domain = 'example.invalid';
  const String base = 'https://idp.$domain';
  const String executor = '$base/api/v3/flows/executor/initial-setup/?query=';
  const String flow = '$base/if/flow/initial-setup/';

  const ReportOutOfBoxFlow step = ReportOutOfBoxFlow(
    subdomain: 'idp',
    domainAnswer: 'books_cluster',
  );

  ({StepContext context, _WhatItSaid said}) contextOn(FakeHttp http, {String? holding = domain}) {
    final _WhatItSaid said = _WhatItSaid();
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{}),
        http: http,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: said,
        step: const StepName('report_out_of_box_flow'),
        arguments: Arguments.none,
        answers: Arguments(<String, Object>{'books_cluster': ?holding}),
        facts: Facts.none,
      ),
      said: said,
    );
  }

  FakeHttp providerStandingOn(String component) => FakeHttp()
    ..answers(
      'GET $executor',
      body: jsonEncode(<String, Object?>{'component': component, 'type': 'native'}),
    );

  group('an installation nobody holds yet', () {
    test('is said to be waiting, and the address a person goes to is in the sentence', () async {
      final FakeHttp provider = providerStandingOn('ak-stage-prompt');
      final ({StepContext context, _WhatItSaid said}) it = contextOn(provider);

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains(flow));
      expect(answer.because, contains('waiting'));
      expect(it.said.warnings.single, contains(flow));
    });

    test('is warned about and not merely mentioned', () async {
      // The level is the whole difference between a line an operator scrolls past and one they act
      // on. The row did its work; what deserves saying is about the machine.
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        providerStandingOn('ak-stage-identification'),
      );

      await step.check(it.context);

      expect(it.said.warnings, hasLength(1));
      expect(it.said.infos, isEmpty);
    });

    test('is asked for with no credential, the way the first person asks', () async {
      // THE CLAIM AND THE ASK HAVE TO MATCH. What is being said is that a stranger reaching this
      // address walks the flow, so an ask carrying a credential would establish something else.
      final FakeHttp provider = providerStandingOn('ak-stage-prompt');

      await step.check(contextOn(provider).context);

      expect(provider.sent, <String>['GET $executor']);
    });
  });

  group('an installation somebody already holds', () {
    test('is never said to be waiting', () async {
      // THE PLANTED DEFECT this guards: a step that reported "waiting" without reading the answer
      // passes every probe above and fails here. Made to go red by hand — returning the open
      // sentence for the refused component turns this probe red and leaves the others green.
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        providerStandingOn('ak-stage-access-denied'),
      );

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains('closed'));
      expect(answer.because, isNot(contains('waiting')));
      expect(it.said.warnings, isEmpty);
      expect(it.said.infos.single, contains('already has its first person'));
    });
  });

  group('what it refuses to say anything about', () {
    test('a provider whose own flow broke, which is not the same as a closed one', () async {
      // The two used to be one answer in every tool that reads a status code: a provider that could
      // not run its flow would have been reported as an installation somebody holds, which is a
      // true-sounding sentence about something nothing looked at.
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        providerStandingOn('ak-stage-flow-error'),
      );

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('ak-stage-flow-error'));
    });

    test('a provider that answered something else entirely', () async {
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        FakeHttp()..answers('GET $executor', status: 503, body: 'no'),
      );

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('503'));
    });

    test('a body that names no stage at all', () async {
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        FakeHttp()..answers('GET $executor', body: '<html>a login page</html>'),
      );

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('no stage'));
    });

    test('a run holding no such answer, named by the answer the row pointed at', () async {
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        providerStandingOn('ak-stage-prompt'),
        holding: null,
      );

      final CheckResult answer = await step.check(it.context);

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('books_cluster'));
    });

    test('an answer given as nothing', () async {
      final ({StepContext context, _WhatItSaid said}) it = contextOn(
        providerStandingOn('ak-stage-prompt'),
        holding: '',
      );

      expect(await step.check(it.context), isA<Blocked>());
    });
  });

  test('the address it names follows the row and is not fixed in the code', () async {
    const ReportOutOfBoxFlow other = ReportOutOfBoxFlow(
      subdomain: 'entry',
      domainAnswer: 'elsewhere',
    );
    const String otherBase = 'https://entry.two.example.org';
    final FakeHttp provider = FakeHttp()
      ..answers(
        'GET $otherBase/api/v3/flows/executor/initial-setup/?query=',
        body: jsonEncode(<String, Object?>{'component': 'ak-stage-prompt'}),
      );
    final _WhatItSaid said = _WhatItSaid();

    final CheckResult answer = await other.check(
      StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{}),
        http: provider,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: said,
        step: const StepName('report_out_of_box_flow'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'elsewhere': 'two.example.org'}),
        facts: Facts.none,
      ),
    );

    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains('$otherBase/if/flow/initial-setup/'));
  });

  test('a second run on an unmoved machine says exactly what the first one said', () async {
    // What the idempotence audit asks of a step that only measures: one that answered differently
    // twice would be reading something that moved while nothing was done to it.
    final FakeHttp provider = providerStandingOn('ak-stage-prompt');

    final CheckResult first = await step.check(contextOn(provider).context);
    final CheckResult again = await step.check(contextOn(provider).context);

    expect((first as Satisfied).because, (again as Satisfied).because);
  });
}

/// Everything a step said while a probe was running it, kept apart by level.
///
/// The level is part of what is measured here and not decoration, so a log that threw it away would
/// leave the probes unable to tell a sentence an operator acts on from one they scroll past.
final class _WhatItSaid implements Logger {
  final List<String> infos = <String>[];
  final List<String> warnings = <String>[];

  @override
  void debug(String message) {}

  @override
  void info(String message) => infos.add(message);

  @override
  void warn(String message) => warnings.add(message);

  @override
  void error(String message) {}
}
