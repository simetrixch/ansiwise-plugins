/// The network a test scripts: every request is kept whole, and the answer may depend on how often
/// the same ask has been made.
///
/// `FakeHttp` keeps only `METHOD url`, and the tests of this package are about everything else — a
/// header that must carry the credential, a body whose slots must be filled, and a state that reads
/// differently once the request before it has been sent. So the port here keeps each [HttpRequest]
/// as it was handed in, and answers through one function that also sees how many times this
/// method-and-address pair has been asked.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// A network port that keeps every request and answers by script.
final class ScriptedHttp implements Http {
  /// Answers every request through the given function, which also sees how often that ask was
  /// made before.
  ScriptedHttp(this._answer);

  final HttpAnswer Function(HttpRequest request, int nth) _answer;

  /// Every request that was sent, in order, whole.
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final int nth = sent
        .where((HttpRequest each) => each.method == request.method && each.url == request.url)
        .length;
    sent.add(request);
    return _answer(request, nth);
  }
}

/// An answer with a body and nothing else worth scripting.
HttpAnswer answerOf(int status, [String body = '']) => HttpAnswer(
  status: status,
  body: body,
  headers: const <String, String>{},
  elapsed: Duration.zero,
);

/// A logger for a step under test, whose words no assertion reads.
final class NothingSaid implements Logger {
  /// Creates the logger.
  const NothingSaid();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
