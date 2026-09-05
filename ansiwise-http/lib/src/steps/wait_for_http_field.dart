import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_conversation.dart';

/// Waits until one field of an address's answer reaches a state the row names, and ends the wait
/// AT ONCE where it reaches one the row names as final and wrong.
///
/// **A wait that ends on a state rather than on a count.** The row names the field, the values
/// that mean "arrived", and the values that mean "this is over and it did not arrive". A value of
/// the second kind ends the wait immediately as a failure that names the state — waiting out the
/// whole window in front of a state that never changes again would report a timeout where the
/// machine had already said what happened.
///
/// **A ROW SAYS WHICH VALUES ARRIVE, OR THAT ANY VALUE DOES, AND ONE OF THE TWO ALWAYS.** `until`
/// names them. `until_present` says the field carrying a value AT ALL is the arrival, for an
/// address whose answer proves itself by standing there: where the value is composed by the far
/// end, a row that restated it would carry a second copy of something the run already holds, and
/// the two agree only until one of them is edited. `failing` still decides first, so a value named
/// there is over and wrong even under `until_present` and every other value arrives. Saying
/// neither would leave a wait nothing can end; saying both would leave two rules deciding one
/// question, and which of them a run obeyed would depend on the order they are read in.
///
/// **Everything in between is "not yet".** An address that does not answer, an answer that is not
/// JSON, a field that is not there — while something is coming up, each of those is what the
/// in-between looks like, so each is carried to the record and the wait keeps asking. What the
/// last ask saw is what a reached deadline reports, because "waited 300s" without it sends an
/// operator to a service that may have stated its refusal in words.
///
/// **It only measures.** Every ask is a GET, so a dry run may ask too, and nothing here changes
/// anything at either end.
final class WaitForHttpField extends ObservingStep {
  /// Polls [url] until [field] holds one of [until] — or any value at all, where [untilPresent] —
  /// for at most [timeoutSeconds].
  const WaitForHttpField({
    required this.waitingFor,
    required this.url,
    required this.socketPath,
    required this.field,
    required this.until,
    required this.untilPresent,
    required this.failing,
    required this.values,
    required this.bearerAnswer,
    required this.bearer,
    required this.acceptsAnyCertificate,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitForHttpField.fromArguments(Arguments arguments) => WaitForHttpField(
    waitingFor: arguments.text('waiting_for'),
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row that has the address from an earlier
    // measurement names that measurement, and everything that examines a program before it runs
    // has to build every step — at that moment the value does not exist.
    url: arguments.optionalText('url') ?? '',
    socketPath: arguments.optionalText('socket_path'),
    field: arguments.text('field'),
    // OPTIONAL BECAUSE "until_present" IS THE OTHER WAY TO SAY IT, never because a row may leave
    // both out. A row that names neither is refused by name when it is asked, rather than waiting
    // on a condition nothing can meet.
    until: arguments.has('until') ? arguments.textList('until') : const <String>[],
    untilPresent: arguments.has('until_present') && arguments.flag('until_present'),
    failing: arguments.has('failing') ? arguments.textList('failing') : const <String>[],
    values: slotSources(arguments.has('values') ? arguments.raw('values') : null),
    bearerAnswer: arguments.has('bearer_answer') ? arguments.text('bearer_answer') : null,
    bearer: arguments.optionalText('bearer'),
    acceptsAnyCertificate:
        arguments.has('accepts_any_certificate') && arguments.flag('accepts_any_certificate'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'waiting_for',
      kind: ArgumentKind.text,
      describes:
          'what is being waited for, named so a deadline that is reached says what did not happen',
    ),
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the address whose answer is watched. A row that has it from an earlier measurement '
          'names that measurement instead, which is why this is not required: the program is '
          'examined before anything is measured, and a step that could not be built then would '
          'refuse the program',
    ),
    ArgumentSpec(
      name: 'socket_path',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the filesystem path of a unix domain socket file. Given, every ask goes to that file '
          'instead of to a host — the address is still read as it stands and still supplies the '
          'request path and the host header, and only where the bytes go changes. Leave it off for '
          'asks that go over the network',
    ),
    ArgumentSpec(
      name: 'field',
      kind: ArgumentKind.text,
      describes:
          'which field of the JSON answer carries the state, as field names joined by dots — each '
          'dot descends one object',
    ),
    ArgumentSpec(
      name: 'until',
      kind: ArgumentKind.textList,
      required: false,
      describes:
          'the values of that field that mean the wait is over and what was waited for is so. Say '
          '"until_present" instead where any value at all is the arrival — one of the two, and '
          'never neither and never both',
    ),
    ArgumentSpec(
      name: 'until_present',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether the field carrying a value AT ALL is what ends the wait, whatever that value '
          'is. For an address whose answer proves itself by standing there: the value is composed '
          'by the far end, and a row that wrote it out would carry a second copy of something the '
          'run already holds — one the far end can change without the row saying anything. A value '
          'named under "failing" still ends the wait badly; every other value arrives. Say this or '
          '"until", and never neither and never both',
    ),
    ArgumentSpec(
      name: 'failing',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the values of that field that mean it is over and did NOT arrive — each ends the wait '
          'at once as a failure naming the state, instead of waiting out the window in front of a '
          'state that never changes again',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      required: false,
      describes:
          'what fills each slot of the address, as `slot-name: {answer: name}` for a value this '
          'run was started with and `slot-name: {measured: name}` for one an earlier row '
          'published. Leave it off where the address is written out whole',
    ),
    ArgumentSpec(
      name: 'bearer_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value rides the authorization header as a bearer '
          'credential — never the credential itself, so no program file carries one. Leave it off '
          'where the address answers without one',
    ),
    ArgumentSpec(
      name: 'bearer',
      kind: ArgumentKind.text,
      required: false,
      secret: true,
      describes:
          'the bearer credential itself, for a row that has it from an earlier measurement rather '
          'than from the operator — which is what a handshake is: what one exchange hands back is '
          'what the next ask proves itself with. DECLARED SECRET, so the framework fills it only '
          'from a measurement declared secret too, and the value is one the redactor already knows '
          'and hides everywhere. A program file never writes one here: a file ships to every '
          'installation, and a credential in it is the same credential everywhere. Name '
          '"bearer_answer" instead where the operator supplies it, and never both',
    ),
    ArgumentSpec(
      name: 'accepts_any_certificate',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether a certificate that cannot be verified is accepted, for the one case where the '
          'wait and the certificate come out of the same run: a route is published before its '
          'issuer has finished, so the proxy serves its own default certificate for the first part '
          'of exactly the window this wait covers, and a verifying ask reports the service as '
          'unreachable while it is running. Say it only for an address inside the installation '
          'being built, and never for one out on the internet, where the certificate is the only '
          'thing establishing that the answer came from who it claims',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 300,
      describes: 'how long the state is given before the wait reports that it did not happen',
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 5,
      describes: 'how long to leave between asks',
    ),
  ];

  /// What is being waited for, in the words the failure reports.
  final String waitingFor;

  /// The address whose answer is watched, before any slot in it is filled.
  final String url;

  /// The socket file every ask goes to instead of a host, or null to go over the network.
  final String? socketPath;

  /// Which field of the answer carries the state.
  final String field;

  /// The values that mean the wait is over and what was waited for is so.
  final List<String> until;

  /// Whether the field carrying any value at all is what ends the wait.
  final bool untilPresent;

  /// The values that mean it is over and did not arrive.
  final List<String> failing;

  /// Which answer fills each slot of the address.
  final Map<String, SlotSource> values;

  /// The name of the answer whose value rides the authorization header, or null for none.
  final String? bearerAnswer;

  /// The credential a measurement filled, or null where this row takes it from an answer or
  /// carries none.
  final String? bearer;

  /// Whether a certificate that cannot be verified ends the ask or is accepted.
  ///
  /// See `HttpRequest.acceptsAnyCertificate`: it is narrow on purpose, and what it gives up is the
  /// proof of WHO answered — never the answer itself, which is the only thing this step reads.
  final bool acceptsAnyCertificate;

  /// How long the state is given.
  final int timeoutSeconds;

  /// How long to leave between asks.
  final int intervalSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Look look = await _ask(context);
    return switch (look) {
      _Stuck(:final String refusal) => CheckResult.blocked(refusal),
      _Arrived(:final String value) => CheckResult.satisfied(
        '$waitingFor — "$field" holds "$value"',
      ),
      _EndedBadly(:final String value) => CheckResult.blocked(
        '$waitingFor ended in "$value", which the row names as a state it does not come back from',
      ),
      _NotYet() => const CheckResult.ready(),
    };
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.nothing('would wait up to ${timeoutSeconds}s for $waitingFor');

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    String? lastSaw;
    while (true) {
      final _Look look = await _ask(context);
      switch (look) {
        case _Arrived():
          return;
        case _Stuck(:final String refusal):
          throw StateError(refusal);
        case _EndedBadly(:final String value):
          throw StateError(
            '$waitingFor ended in "$value", which the row names as a state it does not come back '
            'from — waiting longer cannot change it',
          );
        case _NotYet(:final String? saw):
          lastSaw = saw ?? lastSaw;
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(
          waitingFor: lastSaw == null ? waitingFor : '$waitingFor — $lastSaw',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  /// Asks once, and says which of the four states the answer is in.
  Future<_Look> _ask(StepContext context) async {
    final ({String? refusal, String? value}) carried = bearerCredential(
      context,
      answerName: bearerAnswer,
      given: bearer,
      carries: 'the bearer credential the asks carry',
    );
    if (carried.refusal case final String refusal) {
      return _Stuck(refusal);
    }
    final ({Map<String, String>? filled, String? refusal}) slots = await slotValues(
      context,
      values,
    );
    if (slots.refusal case final String refusal) {
      return _Stuck(refusal);
    }
    if (unusedSlotRefusal(slots.filled!, <String?>[url, socketPath]) case final String refusal) {
      return _Stuck(refusal);
    }
    final String address = filledSlots(url, slots.filled!);
    if (address.isEmpty) {
      return const _Stuck(
        'this row holds no address — write one under "url", or take it from a measurement an '
        'earlier row publishes',
      );
    }
    if (leftoverSlotRefusal(address) case final String refusal) {
      return _Stuck(refusal);
    }
    final ({String? path, String? refusal}) socket = filledSocketPath(socketPath, slots.filled!);
    if (socket.refusal case final String refusal) {
      return _Stuck(refusal);
    }
    if (untilPresent && until.isNotEmpty) {
      return const _Stuck(
        'this row names values under "until" and says "until_present" as well, and nothing says '
        'which of the two ends the wait — say one of them',
      );
    }
    if (!untilPresent && until.isEmpty) {
      return const _Stuck(
        'this row says nothing that ends the wait — name the values under "until", or say '
        '"until_present: true" where the field carrying any value at all is the arrival',
      );
    }
    // A value of the same field in both lists would make one state mean two opposite things, and
    // which of them a run reports would depend on the order they are read in.
    final Iterable<String> both = until.where(failing.contains);
    if (both.isNotEmpty) {
      return _Stuck(
        '"${both.join('", "')}" ${both.length == 1 ? 'stands' : 'stand'} in "until" and in '
        '"failing" at once, so arriving there would mean two opposite things',
      );
    }

    final HttpAnswer answer;
    try {
      // ONE ASK IS GIVEN THE GAP BETWEEN TWO ASKS, and no more. A poll that outlives the interval
      // has stopped being a poll: the next one is already due, and an address that cannot answer
      // inside that gap is not yet the thing being waited for.
      answer = await context.http.send(
        HttpRequest(
          'GET',
          address,
          headers: composedHeaders(bearer: carried.value),
          timeout: Duration(seconds: intervalSeconds),
          socketPath: socket.path,
          acceptsAnyCertificate: acceptsAnyCertificate,
        ),
      );
    } on Object catch (why) {
      // An address that cannot be reached is what the in-between looks like while something comes
      // up, so the reason is carried to the deadline rather than crashing the wait on its first ask.
      return _NotYet('$why'.split('\n').map((String line) => line.trim()).join(' '));
    }
    switch (readingOf(answer, url: address)) {
      case NothingThere():
        return _NotYet('asking $address answered 404, so nothing stands there yet');
      case Unreadable(:final String because):
        return _NotYet(because);
      case AnswerHeld(:final Map<String, Object?> object):
        switch (fieldIn(object, field)) {
          // FAILING IS READ FIRST, and it has to be: under "until_present" every value arrives, so
          // a value the row named as final and wrong would arrive too if the arrival were read
          // first. Where the row names "until" instead, no value can stand in both lists — the
          // refusal above stops that row before it asks — so the order changes nothing there.
          case FieldText(:final String value) when failing.contains(value):
            return _EndedBadly(value);
          case FieldText(:final String value) when untilPresent || until.contains(value):
            return _Arrived(value);
          case FieldText(:final String value):
            return _NotYet('"$field" of $address holds "$value"');
          case FieldMissing(:final String field):
            return _NotYet('the answer at $address carries no value under "$field" yet');
          case FieldNotOneValue(:final String because):
            return _NotYet(because);
        }
    }
  }
}

/// What one ask found, told apart into the four states the wait acts on.
sealed class _Look {
  const _Look();
}

/// The field holds a value the row names as arrived.
final class _Arrived extends _Look {
  const _Arrived(this.value);

  /// The value that ended the wait well.
  final String value;
}

/// The field holds a value the row names as final and wrong.
final class _EndedBadly extends _Look {
  const _EndedBadly(this.value);

  /// The state it ended in.
  final String value;
}

/// The state is not there yet, and this is what the ask saw instead.
final class _NotYet extends _Look {
  const _NotYet([this.saw]);

  /// What was read instead of the answer, or null where there is nothing to add.
  final String? saw;
}

/// The row itself cannot be asked as it stands.
final class _Stuck extends _Look {
  const _Stuck(this.refusal);

  /// Why, in the words a refusal uses.
  final String refusal;
}
