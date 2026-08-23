/// What the wait for an address to answer HANDS THE PORT, and in particular what it says about the
/// certificate on the other end.
///
///   dart test test/wait_for_http_test.dart
///
/// THE PAIR FAILS IN OPPOSITE DIRECTIONS. A row that says nothing must ask for the check to be
/// made, because for an address out on the internet the certificate is the only thing establishing
/// that the answer came from who it claims. A row that says otherwise must reach the port with it,
/// and the case it exists for is an address inside the installation being built: the route is
/// published before its certificate is issued, so the proxy serves its own default for the first
/// part of exactly the window this wait covers, and a verifying ask reports the address as
/// unreachable for the whole of it while the service behind it is answering.
///
/// The port is read for what it was HANDED rather than the step for what it holds. A step that kept
/// the value in a field and never put it on the request would satisfy anything weaker, and that is
/// the failure this is here to make impossible.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/src/steps/host/wait_for_http.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A port that answers everything and keeps the requests themselves, which is the whole point:
/// `FakeHttp` records `METHOD url` and nothing that carries this property.
final class _RecordingHttp implements Http {
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    sent.add(request);
    return const HttpAnswer(
      status: 200,
      body: '',
      headers: <String, String>{},
      elapsed: Duration.zero,
    );
  }
}

/// Says nothing anywhere. What this pair reads is the request, and a step that logged its way to
/// the wrong one would still be judged on what the port was handed.
final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

void main() {
  const String address = 'https://idp.example.test/application/o/headlamp/';
  const StepName under = StepName('wait_for_http');

  WaitForHttp stepFor({bool? acceptsAnyCertificate}) => WaitForHttp.fromArguments(
    Arguments(<String, Object>{
      'url': address,
      'timeout_seconds': 60,
      'interval_seconds': 5,
      'accepts_any_certificate': ?acceptsAnyCertificate,
    }),
  );

  StepContext contextOn(Http http) {
    final HostMachine machine = HostMachine();
    return StepContext(
      shell: machine.shell,
      files: machine.files,
      http: http,
      clock: machine.clock,
      entropy: FakeEntropy(),
      log: const _SilentLog(),
      step: under,
      arguments: Arguments.none,
      facts: Facts.none,
    );
  }

  test('a row that says nothing about certificates asks for the check to be made', () async {
    final _RecordingHttp http = _RecordingHttp();
    await stepFor().check(contextOn(http));
    expect(http.sent.single.acceptsAnyCertificate, isFalse);
  });

  test('a row that says so hands it to the port, and the ask is otherwise the same', () async {
    final _RecordingHttp http = _RecordingHttp();
    await stepFor(acceptsAnyCertificate: true).check(contextOn(http));
    expect(http.sent.single.acceptsAnyCertificate, isTrue);
    expect(http.sent.single.method, 'GET', reason: 'it still only measures');
    expect(http.sent.single.url, address);
  });
}
