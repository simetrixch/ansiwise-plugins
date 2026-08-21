import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_conversation.dart';

/// Sends one request that tells an address to change its own state, gated on a read that says
/// whether that state already stands.
///
/// **Everything about the request comes from its row.** The method, the address, the body, the
/// answer a credential rides in — this step knows the protocol and never which interface it is
/// pointed at. A value no program file may carry — a credential, an installation's own name —
/// arrives through a declared answer and fills a named slot, so the file stays the same for every
/// installation and the secret stays out of it.
///
/// **Its check reads ONE thing before it acts: the answer at the row's own `already_url`.** The
/// protocol has no way to ask an arbitrary interface "was this done", so the row names the read
/// that answers it: when `already_field` of that answer holds `already_value`, the state this
/// request brings about already stands and the request is not sent — which is also what makes a
/// second run of the row do nothing. The same read runs again after the request, and it is what
/// proves the request worked: returning without an error is not success, the state standing is.
///
/// **It is irreversible, and the reason is the protocol's.** What the request changed is the other
/// end's own state, and this package knows no request that puts it back — only the interface that
/// was spoken to knows its own inverse, and a row that has one writes it as its own step.
final class SendHttpRequest extends IrreversibleStep {
  /// Sends [method] to [url] unless the read at [alreadyUrl] says the state already stands.
  const SendHttpRequest({
    required this.method,
    required this.url,
    required this.socketPath,
    required this.body,
    required this.contentType,
    required this.values,
    required this.bearerAnswer,
    required this.alreadyUrl,
    required this.alreadyField,
    required this.alreadyValue,
    required this.timeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory SendHttpRequest.fromArguments(Arguments arguments) => SendHttpRequest(
    method: arguments.text('method'),
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row that has the address from an earlier
    // measurement names that measurement, and everything that examines a program before it runs
    // has to build every step — at that moment the value does not exist.
    url: arguments.optionalText('url') ?? '',
    socketPath: arguments.optionalText('socket_path'),
    body: arguments.optionalText('body'),
    contentType: arguments.optionalText('content_type'),
    values: answerBySlot(arguments.has('values') ? arguments.raw('values') : null),
    bearerAnswer: arguments.has('bearer_answer') ? arguments.text('bearer_answer') : null,
    alreadyUrl: arguments.text('already_url'),
    alreadyField: arguments.text('already_field'),
    alreadyValue: arguments.text('already_value'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // The methods the protocol itself defines as changing something at the other end. A read has
    // its own step, so letting one be written here would let a row claim work where there is none.
    ArgumentSpec(
      name: 'method',
      kind: ArgumentKind.text,
      allowed: <String>['POST', 'PUT', 'PATCH', 'DELETE'],
      describes: 'the request method, one of the protocol\'s own words for a request that changes',
    ),
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the address the request goes to. A row that has it from an earlier measurement names '
          'that measurement instead, which is why this is not required: the program is examined '
          'before anything is measured, and a step that could not be built then would refuse the '
          'program',
    ),
    ArgumentSpec(
      name: 'socket_path',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the filesystem path of a unix domain socket file. Given, the request and the '
          'already-read alike go to that file instead of to a host — each address is still read as '
          'it stands and still supplies the request path and the host header, and only where the '
          'bytes go changes. Leave it off for requests that go over the network',
    ),
    ArgumentSpec(
      name: 'body',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the body the request carries, written out by the row. A value no program file may '
          'carry fills a named slot through the values mapping. Leave it off for a request that '
          'carries none',
    ),
    ArgumentSpec(
      name: 'content_type',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'what the body\'s content-type header declares. Leave it off where there is no body or '
          'the other end asks for none',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      required: false,
      describes:
          'which answer fills each slot of the address, the body and the already-address, as '
          '`slot-name: {answer: name}`. Leave it off where every text is written out whole',
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
      name: 'already_url',
      kind: ArgumentKind.text,
      describes:
          'the address whose answer says whether the state this request brings about already '
          'stands — read before the request decides anything, and read again after it as the '
          'proof that it worked',
    ),
    ArgumentSpec(
      name: 'already_field',
      kind: ArgumentKind.text,
      describes:
          'which field of that answer carries the state, as field names joined by dots — each dot '
          'descends one object',
    ),
    ArgumentSpec(
      name: 'already_value',
      kind: ArgumentKind.text,
      describes: 'the value of that field that means the state already stands',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 30,
      describes:
          'how long any one request may take before the row gives up on it. Bounded because the '
          'protocol default is to wait forever, and an address that accepts the connection and '
          'then hangs would turn one slow dependency into a run nobody can tell from a working one',
    ),
  ];

  /// The request method, one of the words the protocol defines as changing something.
  final String method;

  /// The address the request goes to, before any slot in it is filled.
  final String url;

  /// The socket file every request of this row goes to instead of a host, or null to go over the
  /// network.
  final String? socketPath;

  /// The body the request carries, or null for none.
  final String? body;

  /// What the content-type header declares, or null for none.
  final String? contentType;

  /// Which answer fills each slot of the row's texts.
  final Map<String, String> values;

  /// The name of the answer whose value rides the authorization header, or null for none.
  final String? bearerAnswer;

  /// The address whose answer says whether the state already stands.
  final String alreadyUrl;

  /// Which field of that answer carries the state.
  final String alreadyField;

  /// The value of that field that means the state stands.
  final String alreadyValue;

  /// How long any one request may take.
  final int timeoutSeconds;

  @override
  String get irreversibleReason =>
      'the request told the other end to change its own state, and there is no general request '
      'that puts a state back — what was changed there stays changed until something with its own '
      'row changes it again';

  /// The row's texts with every slot filled, or the refusal that stops the row.
  ///
  /// One method for the check and the apply, so what was probed and what is sent cannot drift
  /// apart.
  ({({String address, String? content, String probe})? texts, String? refusal}) _filled(
    StepContext context,
  ) {
    final ({Map<String, String>? filled, String? refusal}) slots = slotValues(context, values);
    if (slots.refusal case final String refusal) {
      return (texts: null, refusal: refusal);
    }
    if (unusedSlotRefusal(slots.filled!, <String?>[url, body, alreadyUrl])
        case final String refusal) {
      return (texts: null, refusal: refusal);
    }
    final String address = filledSlots(url, slots.filled!);
    if (address.isEmpty) {
      return (
        texts: null,
        refusal:
            'this row holds no address — write one under "url", or take it from a measurement an '
            'earlier row publishes',
      );
    }
    final String probe = filledSlots(alreadyUrl, slots.filled!);
    for (final String each in <String>[address, probe]) {
      if (leftoverSlotRefusal(each) case final String refusal) {
        return (texts: null, refusal: refusal);
      }
    }
    final String? content = body == null ? null : filledSlots(body!, slots.filled!);
    return (texts: (address: address, content: content, probe: probe), refusal: null);
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? refusal, String? value}) bearer = answerValue(
      context,
      bearerAnswer,
      carries: 'the bearer credential the requests carry',
    );
    if (bearer.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({({String address, String? content, String probe})? texts, String? refusal}) filled =
        _filled(context);
    if (filled.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String probe = filled.texts!.probe;

    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'GET',
        probe,
        headers: composedHeaders(bearer: bearer.value),
        timeout: Duration(seconds: timeoutSeconds),
        socketPath: socketPath,
      ),
    );
    switch (readingOf(answer, url: probe)) {
      case NothingThere():
        return const CheckResult.ready();
      case Unreadable(:final String because):
        return CheckResult.blocked(
          '$because — and a row that read that as "not yet" would send the request over whatever '
          'stands there',
        );
      case AnswerHeld(:final Map<String, Object?> object):
        switch (fieldIn(object, alreadyField)) {
          case FieldText(:final String value) when value == alreadyValue:
            return CheckResult.satisfied(
              '"$alreadyField" of $probe holds "$alreadyValue", so what this request brings about '
              'already stands',
            );
          case FieldText(:final String value):
            // What the read said INSTEAD goes to the record: after the request, this same read is
            // the proof, and a proof that never arrives is diagnosed from these lines rather than
            // from "the check did not answer satisfied".
            context.log.info('"$alreadyField" of $probe holds "$value" and not "$alreadyValue"');
            return const CheckResult.ready();
          case FieldMissing(:final String field):
            context.log.info('the answer at $probe carries no value under "$field" yet');
            return const CheckResult.ready();
          case FieldNotOneValue(:final String because):
            return CheckResult.blocked(because);
        }
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ({({String address, String? content, String probe})? texts, String? refusal}) filled =
        _filled(context);
    // A row whose texts refuse to fill has a blocked check, and its plan may still be asked — the
    // engine only plans a ready row, but what else asks a step is not this step's to know. What
    // can honestly be said then is the request as the row wrote it, slots and all.
    if (filled.texts == null) {
      return StepPlan.request(method, url, body: body);
    }
    return StepPlan.request(method, filled.texts!.address, body: filled.texts!.content);
  }

  @override
  Future<void> apply(StepContext context) async {
    final ({String? refusal, String? value}) bearer = answerValue(
      context,
      bearerAnswer,
      carries: 'the bearer credential the requests carry',
    );
    if (bearer.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final ({({String address, String? content, String probe})? texts, String? refusal}) filled =
        _filled(context);
    if (filled.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final ({String address, String? content, String probe}) texts = filled.texts!;

    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        method,
        texts.address,
        headers: composedHeaders(bearer: bearer.value, contentType: contentType),
        body: texts.content,
        timeout: Duration(seconds: timeoutSeconds),
        socketPath: socketPath,
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: method,
        url: texts.address,
        status: answer.status,
        body: answer.body,
      );
    }
  }
}
