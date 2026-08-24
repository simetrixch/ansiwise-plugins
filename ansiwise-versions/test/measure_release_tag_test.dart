import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Composing the tag a release is cut under, and the four ways a run can be told something that
/// would compose a tag nothing downstream can parse.
///
/// **The property the whole design turns on is the last case.** The tag must be the same text in
/// every mode: the mode that only says what would change announces it, and the mode that changes
/// things acts on it. A value read from a clock would differ between the two, and what was
/// announced would be a tag that never comes into being.
void main() {
  const MeasureReleaseTag step = MeasureReleaseTag(
    versionAnswer: 'release_version',
    channelAnswer: 'release_channel',
    stampAnswer: 'release_stamp',
    channels: <String>['alpha', 'beta', 'stable'],
  );

  Map<MeasurementName, String> published = <MeasurementName, String>{};

  StepContext contextOn(Map<String, Object> answers, {Clock? clock}) {
    published = <MeasurementName, String>{};
    return StepContext(
      shell: FakeShell(),
      files: FakeFiles(),
      http: FakeHttp(),
      clock: clock ?? FakeClock(),
      entropy: FakeEntropy(),
      log: CollectedLog(),
      step: const StepName('under_test'),
      arguments: Arguments.none,
      answers: Arguments(answers),
      facts: Facts.none,
      measurements: _Sink(published),
    );
  }

  const Map<String, Object> whole = <String, Object>{
    'release_version': '1.2.3',
    'release_channel': 'alpha',
    'release_stamp': '20260824120000',
  };

  test('the three parts become one tag, and the run is told what it cuts', () async {
    final CheckResult answer = await step.check(contextOn(whole));

    expect(answer, isA<Satisfied>());
    expect(published[const MeasurementName('release_tag')], '1.2.3-alpha-20260824120000');
    expect((answer as Satisfied).because, contains('1.2.3-alpha-20260824120000'));
  });

  test('THE SAME ANSWERS COMPOSE THE SAME TAG, whatever the clock says', () async {
    // The announcement and the act are one statement or they are two, and two is a plan that names
    // something that never comes into being. A step reading the time would fail here.
    final DateTime early = DateTime.utc(2020);
    final DateTime late = DateTime.utc(2031, 7, 4, 5, 6, 7);

    await step.check(contextOn(whole, clock: FakeClock(early)));
    final String first = published[const MeasurementName('release_tag')]!;
    await step.check(contextOn(whole, clock: FakeClock(late)));
    final String second = published[const MeasurementName('release_tag')]!;

    expect(first, second);
  });

  test('a version with a leading zero is refused, or one release would have two names', () async {
    // 01.02.03 and 1.2.3 are two tags nothing can tell apart, on two different trees.
    final CheckResult answer = await step.check(
      contextOn(<String, Object>{...whole, 'release_version': '01.02.03'}),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('leading zero'));
    expect(published, isEmpty, reason: 'nothing is published where nothing could be composed');
  });

  test('a version that is not three numbers is refused by what was answered', () async {
    final CheckResult answer = await step.check(
      contextOn(<String, Object>{...whole, 'release_version': '1.2'}),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('"1.2"'));
  });

  test('a channel this product does not have is refused, and the row\'s list is named', () async {
    // WHICH CHANNELS EXIST IS THE ROW'S. The refusal says what they are, because an operator who
    // typed the wrong one cannot know the list from anywhere else.
    final CheckResult answer = await step.check(
      contextOn(<String, Object>{...whole, 'release_channel': 'nightly'}),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('nightly'));
    expect(answer.reason, contains('alpha, beta, stable'));
  });

  test('a stamp that is not fourteen digits is refused', () async {
    final CheckResult answer = await step.check(
      contextOn(<String, Object>{...whole, 'release_stamp': '2026-08-24'}),
    );

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('fourteen digits'));
  });

  test('an answer the run does not hold is refused by that answer\'s name', () async {
    for (final String missing in <String>['release_version', 'release_channel', 'release_stamp']) {
      final Map<String, Object> without = <String, Object>{...whole}..remove(missing);
      final CheckResult answer = await step.check(contextOn(without));

      expect(answer, isA<Blocked>(), reason: 'without $missing there is nothing to compose');
      expect((answer as Blocked).reason, contains('"$missing"'));
    }
  });

  test('THE INNOCENT NEIGHBOUR: every channel the row states is taken', () async {
    // Without this, a step that refused every channel would satisfy the refusal case above.
    for (final String channel in <String>['alpha', 'beta', 'stable']) {
      final CheckResult answer = await step.check(
        contextOn(<String, Object>{...whole, 'release_channel': channel}),
      );
      expect(answer, isA<Satisfied>(), reason: '$channel is one this product has');
      expect(published[const MeasurementName('release_tag')], '1.2.3-$channel-20260824120000');
    }
  });
}

/// Collects what a step publishes, so a probe can read it.
final class _Sink implements MeasurementSink {
  const _Sink(this._into);

  final Map<MeasurementName, String> _into;

  @override
  void publish(MeasurementName name, String value) => _into[name] = value;
}
