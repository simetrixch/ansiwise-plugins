import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// The store, as far as a key-pair step meets it: an entry that a write really changes.
///
/// A table-driven fake answers the same thing however often it is asked, which cannot express the
/// property the key-pair cases turn on — that a second run reads what the first one wrote.
final class FakeStore implements Http {
  FakeStore({Map<String, Object?>? holding, this.readStatus = 200, this.writeStatus = 200})
    : held = holding == null ? null : <String, Object?>{...holding};

  /// What the entry holds, or null where nothing was ever written to it.
  Map<String, Object?>? held;

  /// What a read answers, for the case where reading fails rather than finding nothing.
  final int readStatus;

  /// What a write answers.
  final int writeStatus;

  /// Every write that was sent, so a probe can say a check wrote nothing.
  final List<String> wrote = <String>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    if (request.method == 'GET') {
      if (readStatus != 200) {
        return _answer('{"errors":["permission denied"]}', status: readStatus);
      }
      return held == null
          ? _answer('', status: 404)
          : _answer(
              jsonEncode(<String, Object?>{
                'data': <String, Object?>{'data': held, 'metadata': <String, Object?>{}},
              }),
            );
    }
    wrote.add('${request.method} ${request.url}');
    if (writeStatus != 200) {
      return _answer('{"errors":["refused"]}', status: writeStatus);
    }
    final Object? body = jsonDecode(request.body ?? '{}');
    final Object? data = body is Map<String, Object?> ? body['data'] : null;
    held = data is Map<String, Object?> ? <String, Object?>{...data} : <String, Object?>{};
    return _answer('{}');
  }

  static HttpAnswer _answer(String body, {int status = 200}) => HttpAnswer(
    status: status,
    body: body,
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );
}

/// A log nothing reads, so a probe measures what a step DID and not what it said about it.
final class SilentLog implements Logger {
  const SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// A sink that keeps what a step published, keyed by the name the step declares.
final class RecordingSink implements MeasurementSink {
  RecordingSink(this.published);

  final Map<MeasurementName, String> published;

  @override
  void publish(MeasurementName name, String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'published as nothing');
    }
    published[name] = value;
  }
}
