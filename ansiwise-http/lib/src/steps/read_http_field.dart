import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_conversation.dart';

/// Reads one field out of the answer an address gives, and publishes it for a later row.
///
/// **Everything it sends and everything it looks for comes from its row.** The address, the field,
/// the answer a credential rides in — this step knows the protocol and never which interface it is
/// pointed at, so a program row supplies each of them and nothing here has a default that belongs
/// to any one product.
///
/// **It only reads.** The one request it sends is a GET, which is the protocol's own word for a
/// request that changes nothing — so a dry run sends it too, and the value is there for the rows
/// that follow.
///
/// **Its check reads the answer to that one request, and that is the whole of what it acts on.**
/// A status outside the two hundreds, a body that is not a JSON object, and a field that is not
/// there or does not hold one value are each a blocked check that says what came back — never an
/// empty measurement, because a row downstream cannot tell "the field holds nothing" from "nothing
/// here could be read".
final class ReadHttpField extends ObservingStep {
  /// Reads [field] out of the answer at [url].
  const ReadHttpField({
    required this.url,
    required this.socketPath,
    required this.field,
    required this.values,
    required this.bearerAnswer,
    required this.timeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory ReadHttpField.fromArguments(Arguments arguments) => ReadHttpField(
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row that has the address from an earlier
    // measurement names that measurement, and everything that examines a program before it runs
    // has to build every step — at that moment the value does not exist. Read as required, the
    // whole program would be refused before anything looked at anything.
    url: arguments.optionalText('url') ?? '',
    socketPath: arguments.optionalText('socket_path'),
    field: arguments.text('field'),
    values: answerBySlot(arguments.has('values') ? arguments.raw('values') : null),
    bearerAnswer: arguments.has('bearer_answer') ? arguments.text('bearer_answer') : null,
    timeoutSeconds: arguments.integer('timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the address whose answer is read. A row that has it from an earlier measurement names '
          'that measurement instead, which is why this is not required: the program is examined '
          'before anything is measured, and a step that could not be built then would refuse the '
          'program',
    ),
    ArgumentSpec(
      name: 'socket_path',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the filesystem path of a unix domain socket file. Given, the one request goes to that '
          'file instead of to a host — the address is still read as it stands and still supplies '
          'the request path and the host header, and only where the bytes go changes. Leave it off '
          'for a request that goes over the network',
    ),
    ArgumentSpec(
      name: 'field',
      kind: ArgumentKind.text,
      describes:
          'which field of the JSON answer is published, as field names joined by dots — each dot '
          'descends one object',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      required: false,
      describes:
          'which answer fills each slot of the address, as `slot-name: {answer: name}`. Leave it '
          'off where the address is written out whole',
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
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 30,
      describes:
          'how long the one request may take before the row gives up on it. Bounded because the '
          'protocol default is to wait forever, and an address that accepts the connection and '
          'then hangs would turn one slow dependency into a run nobody can tell from a working one',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('http_field'),
      describes: 'the value the named field of the answer holds',
    ),
  ];

  /// The address whose answer is read, before any slot in it is filled.
  final String url;

  /// The socket file the request goes to instead of a host, or null to go over the network.
  final String? socketPath;

  /// Which field of the answer is published, as a dotted path.
  final String field;

  /// Which answer fills each slot of the address.
  final Map<String, String> values;

  /// The name of the answer whose value rides the authorization header, or null for none.
  final String? bearerAnswer;

  /// How long the one request may take.
  final int timeoutSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? refusal, String? value}) bearer = answerValue(
      context,
      bearerAnswer,
      carries: 'the bearer credential the request carries',
    );
    if (bearer.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({Map<String, String>? filled, String? refusal}) slots = slotValues(context, values);
    if (slots.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (unusedSlotRefusal(slots.filled!, <String?>[url]) case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String address = filledSlots(url, slots.filled!);
    if (address.isEmpty) {
      return const CheckResult.blocked(
        'this row holds no address — write one under "url", or take it from a measurement an '
        'earlier row publishes',
      );
    }
    if (leftoverSlotRefusal(address) case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'GET',
        address,
        headers: composedHeaders(bearer: bearer.value),
        timeout: Duration(seconds: timeoutSeconds),
        socketPath: socketPath,
      ),
    );
    switch (readingOf(answer, url: address)) {
      case NothingThere():
        return CheckResult.blocked(
          'asking $address answered 404, so there is nothing to read a field out of',
        );
      case Unreadable(:final String because):
        return CheckResult.blocked(because);
      case AnswerHeld(:final Map<String, Object?> object):
        switch (fieldIn(object, field)) {
          case FieldText(:final String value):
            context.measurements.publish(const MeasurementName('http_field'), value);
            return CheckResult.satisfied('"$field" of $address holds "$value"');
          case FieldMissing(:final String field):
            return CheckResult.blocked(
              'the answer at $address carries no value under "$field", so there is nothing to '
              'publish',
            );
          case FieldNotOneValue(:final String because):
            return CheckResult.blocked(because);
        }
    }
  }
}
