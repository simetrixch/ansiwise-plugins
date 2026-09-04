/// Holding an exchange: one changing request whose ANSWER is the whole of what it did.
///
/// **What an exchange is, in the protocol's own words.** A request that changes something at the
/// other end and hands back a value that did not exist before it. The protocol has no way to ask
/// again for what was handed back — asking again is another request of the same kind, which changes
/// something again. So there is nothing an address could be asked afterwards that would prove the
/// first one worked, and the value that came back is the only evidence there is.
///
/// **THERE IS NO ALREADY-PROBE HERE, AND THAT IS A DECISION.** A step of this kind cannot have one,
/// and putting one in would be a claim nobody can keep: what a row would have to read is the value
/// the request hands back, and no address holds it. So rerunning a program RE-SENDS. A second create is answered by the other end's own refusal, the row fails loudly, and
/// an operator sees it — which is the honest outcome and the one a caller of this kind asked for.
/// A quiet second one, made and published as though it were the first, is the alternative — and
/// it is worse in every way.
///
/// **What is shared here and what is not.** The arguments below are one list because both exchange
/// steps take exactly the same ones — the difference between them is what they PUBLISH, which is
/// declared in the registry and not in a row. [ExchangeRow] holds one row's values and does the
/// sending, so what the check judges and what the apply sends cannot drift apart.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_conversation.dart';

/// What an exchange step accepts, which is the same list for every one of them.
///
/// A NAMED constant rather than a list written into each step, because it exists to stand in several
/// steps' declarations: two kinds that differ only in what they publish would otherwise carry two
/// copies of one grammar, and the day one of them gained an argument the other would silently be a
/// different step.
const List<ArgumentSpec> exchangeArguments = <ArgumentSpec>[
  // The methods the protocol itself defines as changing something at the other end. A READ HAS ITS
  // OWN STEP, and letting one be written here would let a row call a read an exchange — claiming
  // work, a value that was made for it, and a point of no return where nothing was ever touched.
  ArgumentSpec(
    name: 'method',
    kind: ArgumentKind.text,
    allowed: <String>['POST', 'PUT', 'PATCH', 'DELETE'],
    describes:
        'the request method, one of the protocol\'s own words for a request that changes. A request '
        'that only reads has its own step, so none of its words is accepted here',
  ),
  ArgumentSpec(
    name: 'url',
    kind: ArgumentKind.text,
    required: false,
    describes:
        'the address the one request goes to. A row that has it from an earlier measurement names '
        'that measurement instead, which is why this is not required: the program is examined '
        'before anything is measured, and a step that could not be built then would refuse the '
        'program',
  ),
  ArgumentSpec(
    name: 'socket_path',
    kind: ArgumentKind.text,
    required: false,
    describes:
        'the filesystem path of a unix domain socket file. Given, the one request goes to that file '
        'instead of to a host — the address is still read as it stands and still supplies the '
        'request path and the host header, and only where the bytes go changes. Leave it off for a '
        'request that goes over the network',
  ),
  ArgumentSpec(
    name: 'body',
    kind: ArgumentKind.text,
    required: false,
    describes:
        'the body the request carries, written out by the row. A value no program file may carry '
        'fills a named slot through the values mapping. Leave it off for a request that carries none',
  ),
  ArgumentSpec(
    name: 'content_type',
    kind: ArgumentKind.text,
    required: false,
    describes:
        'what the body\'s content-type header declares. Leave it off where there is no body or the '
        'other end asks for none',
  ),
  ArgumentSpec(
    name: 'values',
    kind: ArgumentKind.mapping,
    required: false,
    describes:
        'what fills each slot of the address and the body, as `slot-name: {answer: name}` for a '
        'value this run was started with and `slot-name: {measured: name}` for one an earlier row '
        'published. Leave it off where every text is written out whole',
  ),
  ArgumentSpec(
    name: 'bearer_answer',
    kind: ArgumentKind.answerName,
    required: false,
    describes:
        'the name of the answer whose value rides the authorization header as a bearer credential — '
        'never the credential itself, so no program file carries one. Leave it off where the address '
        'answers without one',
  ),
  ArgumentSpec(
    name: 'bearer',
    kind: ArgumentKind.text,
    required: false,
    secret: true,
    describes:
        'the bearer credential itself, for a row that has it from an earlier measurement rather '
        'than from the operator — which is what a handshake is: what one exchange hands back is '
        'what the next request proves itself with. DECLARED SECRET, so the framework fills it only '
        'from a measurement declared secret too, and the value is one the redactor already knows '
        'and hides everywhere. A program file never writes one here: a file ships to every '
        'installation, and a credential in it is the same credential everywhere. Name '
        '"bearer_answer" instead where the operator supplies it, and never both',
  ),
  ArgumentSpec(
    name: 'field',
    kind: ArgumentKind.text,
    describes:
        'which field of the answer to THIS request is published, as field names joined by dots — '
        'each dot descends one object. It is the whole of what this row proves, because nothing can '
        'be asked afterwards for what the request handed back',
  ),
  ArgumentSpec(
    name: 'timeout_seconds',
    kind: ArgumentKind.integer,
    required: false,
    defaultValue: 30,
    describes:
        'how long the one request may take before the row gives up on it. Bounded because the '
        'protocol default is to wait forever, and an address that accepts the connection and then '
        'hangs would turn one slow dependency into a run nobody can tell from a working one',
  ),
];

/// One row of an exchange step: everything it was given, and the one request it sends.
///
/// Held apart from the steps because two kinds share it and their check and their apply share it
/// again: the row's texts are filled once, by one method, so what a check judged fillable and what
/// an apply sends cannot be two different things.
final class ExchangeRow {
  /// Holds what one row was given.
  const ExchangeRow({
    required this.method,
    required this.url,
    required this.socketPath,
    required this.body,
    required this.contentType,
    required this.values,
    required this.bearerAnswer,
    required this.bearer,
    required this.field,
    required this.timeoutSeconds,
  });

  /// Reads one row out of what the program gave it.
  factory ExchangeRow.fromArguments(Arguments arguments) => ExchangeRow(
    method: arguments.text('method'),
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row that has the address from an earlier
    // measurement names that measurement, and everything that examines a program before it runs has
    // to build every step — at that moment the value does not exist.
    url: arguments.optionalText('url') ?? '',
    socketPath: arguments.optionalText('socket_path'),
    body: arguments.optionalText('body'),
    contentType: arguments.optionalText('content_type'),
    values: slotSources(arguments.has('values') ? arguments.raw('values') : null),
    bearerAnswer: arguments.has('bearer_answer') ? arguments.text('bearer_answer') : null,
    bearer: arguments.optionalText('bearer'),
    field: arguments.text('field'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
  );

  /// The request method, one of the words the protocol defines as changing something.
  final String method;

  /// The address the request goes to, before any slot in it is filled.
  final String url;

  /// The socket file the request goes to instead of a host, or null to go over the network.
  final String? socketPath;

  /// The body the request carries, or null for none.
  final String? body;

  /// What the content-type header declares, or null for none.
  final String? contentType;

  /// Which answer fills each slot of the row's texts.
  final Map<String, SlotSource> values;

  /// The name of the answer whose value rides the authorization header, or null for none.
  final String? bearerAnswer;

  /// The credential a measurement filled, or null where this row takes it from an answer or
  /// carries none.
  final String? bearer;

  /// Which field of the answer to this request is published, as a dotted path.
  final String field;

  /// How long the one request may take.
  final int timeoutSeconds;

  /// Whether this row can be sent as it stands, which is the WHOLE of what an exchange's check may
  /// answer.
  ///
  /// **It is never the proof and it never answers satisfied.** Nothing at the other end says whether
  /// this exchange has happened — that is what the kind is — so the only honest question here is
  /// whether what has to be sent is there: the credential the row names, the answers its slots
  /// stand for, and an address left after they are filled. The proof is the value the apply brings
  /// back, and the engine reads it off the run's own measurements.
  ///
  /// It changes nothing and sends nothing, so a dry run reaches it too.
  CheckResult readyOrBlocked(StepContext context) {
    final ({String? refusal, String? value}) carried = _carried(context);
    if (carried.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({({String address, String? content, String? socket})? texts, String? refusal}) filled =
        _filled(context);
    return filled.refusal == null
        ? const CheckResult.ready()
        : CheckResult.blocked(filled.refusal!);
  }

  /// What this row would send, for the plan an operator reads before starting.
  StepPlan planned(StepContext context) {
    final ({({String address, String? content, String? socket})? texts, String? refusal}) filled =
        _filled(context);
    // A row whose texts refuse to fill has a blocked check, and its plan may still be asked. What
    // can honestly be said then is the request as the row wrote it, slots and all.
    return filled.texts == null
        ? StepPlan.request(method, url, body: body)
        : StepPlan.request(method, filled.texts!.address, body: filled.texts!.content);
  }

  /// Sends the one changing request and answers with the value its own answer holds under [field].
  ///
  /// Throws where the row cannot be sent, where the other end refused, and where the answer holds no
  /// one value under the named field — because a row that published nothing would be a row whose
  /// work left no evidence, and the engine fails it either way. Failing here says WHY.
  ///
  /// **[mayQuoteWhatCameBack] decides whether a refusal carries the body it came with.** For a step
  /// that publishes a credential the answer is no, in every message and on every branch: the value
  /// this request brings back is not registered with the redactor until it is published, so a body
  /// written before that is a body written in the clear. What is said instead names the method, the
  /// address and the status, which is what an operator acts on.
  Future<String> valueFrom(StepContext context, {required bool mayQuoteWhatCameBack}) async {
    final ({String? refusal, String? value}) carried = _carried(context);
    if (carried.refusal case final String refusal) {
      throw AnswerIncomplete(refusal);
    }
    final ({({String address, String? content, String? socket})? texts, String? refusal}) filled =
        _filled(context);
    if (filled.refusal case final String refusal) {
      throw AnswerIncomplete(refusal);
    }
    final ({String address, String? content, String? socket}) texts = filled.texts!;

    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        method,
        texts.address,
        headers: composedHeaders(bearer: carried.value, contentType: contentType),
        body: texts.content,
        timeout: Duration(seconds: timeoutSeconds),
        socketPath: texts.socket,
      ),
    );
    if (!answer.ok) {
      if (!mayQuoteWhatCameBack) {
        throw AnswerIncomplete(
          '$method ${texts.address} answered ${answer.status}, and what came with it is not '
          'repeated here: this row publishes a credential, and nothing hides a value that was '
          'never published',
        );
      }
      throw RequestRefused(
        method: method,
        url: texts.address,
        status: answer.status,
        body: answer.body,
      );
    }
    switch (readingOf(answer, url: texts.address)) {
      case NothingThere():
        throw AnswerIncomplete(
          '$method ${texts.address} answered 404, so there is nothing to read "$field" out of',
        );
      case Unreadable(:final String because):
        throw AnswerIncomplete(because);
      case AnswerHeld(:final Map<String, Object?> object):
        switch (fieldIn(object, field)) {
          case FieldText(:final String value):
            return value;
          case FieldMissing(:final String field):
            throw AnswerIncomplete(
              'the answer to $method ${texts.address} carries no value under "$field", so this '
              'exchange left nothing behind that says what it did',
            );
          case FieldNotOneValue(:final String because):
            throw AnswerIncomplete(because);
        }
    }
  }

  /// The credential this row's request carries, from whichever source it names.
  ({String? value, String? refusal}) _carried(StepContext context) => bearerCredential(
    context,
    answerName: bearerAnswer,
    given: bearer,
    carries: 'the bearer credential the request carries',
  );

  /// The row's texts with every slot filled, or the refusal that stops the row.
  ({({String address, String? content, String? socket})? texts, String? refusal}) _filled(
    StepContext context,
  ) {
    final ({Map<String, String>? filled, String? refusal}) slots = slotValues(context, values);
    if (slots.refusal case final String refusal) {
      return (texts: null, refusal: refusal);
    }
    if (unusedSlotRefusal(slots.filled!, <String?>[url, body, socketPath])
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
    if (leftoverSlotRefusal(address) case final String refusal) {
      return (texts: null, refusal: refusal);
    }
    final ({String? path, String? refusal}) socket = filledSocketPath(socketPath, slots.filled!);
    if (socket.refusal case final String refusal) {
      return (texts: null, refusal: refusal);
    }
    final String? content = body == null ? null : filledSlots(body!, slots.filled!);
    return (texts: (address: address, content: content, socket: socket.path), refusal: null);
  }
}

/// Why an exchange cannot be taken back, in the operator's words.
///
/// One sentence for both kinds, because it is one fact about the protocol rather than about either
/// of them: what the request brought about at the other end stands, and the value it handed back
/// exists exactly once.
const String exchangeIsIrreversible =
    'the other end acted on the request and handed back a value that did not exist before it — '
    'there is no request in the protocol that unmakes either, and asking again would make a second '
    'one rather than take the first back';
