import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ansiwise_core/ansiwise_core.dart' hide HttpRequest;
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A digest no body of this file has, for the case where the bytes that arrive are not the pinned
/// ones.
const String _plantedDigest = '0000000000000000000000000000000000000000000000000000000000000bad';

/// How many machines fetch at once, as in the redeploy of 2026-10-19.
const int _machines = 8;

/// What a registry did to a download on 2026-10-19, at a scale a test can wait for.
///
/// The registry ended every response that was still being written 60 seconds after it began, and
/// eight machines fetching one 250 MB file shared the bandwidth, so seven of the eight were ended
/// part-way. The cut is a wall-clock limit on ONE response, so it does not depend on how many
/// seconds it is: here a response is ended after [cutAfter], and [bytesPerSecond] is the bandwidth
/// all open responses share, so the eight together need about eight times as long as one.
///
/// The stand-in answers a `Range` request with 206, as the registry and the proxy in front of it do,
/// which is what lets a download that was cut be continued.
final class CuttingStore {
  CuttingStore({required this.body, required this.bytesPerSecond, required this.cutAfter});

  /// The bytes it serves.
  final Uint8List body;

  /// The bandwidth shared by every response that is open.
  final int bytesPerSecond;

  /// How long a response may be written before the store ends it.
  final Duration cutAfter;

  /// How many responses it ended part-way.
  int cuts = 0;

  static const Duration _tick = Duration(milliseconds: 50);

  late final HttpServer _server;
  late final Timer _timer;
  final Set<_Response> _open = <_Response>{};

  /// Where the file is served from.
  String get address => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_answer);
    _timer = Timer.periodic(_tick, (_) => _write());
  }

  Future<void> stop() async {
    _timer.cancel();
    for (final _Response response in _open) {
      response.socket.destroy();
    }
    await _server.close(force: true);
  }

  Future<void> _answer(HttpRequest request) async {
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    final int from = range == null
        ? 0
        : int.parse(RegExp(r'^bytes=(\d+)-$').firstMatch(range)!.group(1)!);
    final HttpResponse response = request.response;
    if (from >= body.length) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${body.length}');
      await response.close();
      return;
    }
    response.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $from-${body.length - 1}/${body.length}',
      );
    }
    response.headers.set(HttpHeaders.connectionHeader, 'close');
    response.contentLength = body.length - from;
    final Socket socket = await response.detachSocket();
    final _Response open = _Response(socket, from)..started.start();
    _open.add(open);
    unawaited(
      socket.done.then((_) {}, onError: (Object _) {}).whenComplete(() => _open.remove(open)),
    );
  }

  void _write() {
    final List<_Response> writing = _open.toList();
    if (writing.isEmpty) return;
    final int share = bytesPerSecond * _tick.inMilliseconds ~/ 1000 ~/ writing.length;
    for (final _Response response in writing) {
      if (response.started.elapsed >= cutAfter) {
        cuts++;
        _open.remove(response);
        response.socket.destroy();
        continue;
      }
      final int end = (response.sent + share).clamp(0, body.length);
      response.socket.add(Uint8List.sublistView(body, response.sent, end));
      response.sent = end;
      if (end == body.length) {
        _open.remove(response);
        unawaited(response.socket.close());
      }
    }
  }
}

final class _Response {
  _Response(this.socket, this.sent);

  final Socket socket;
  final Stopwatch started = Stopwatch();

  /// The offset of the next byte to write.
  int sent;
}

/// Runs a command on this machine, whoever it is asked to run as.
///
/// The fake shell cannot start `curl`, and the real one raises a command to root through sudo. A
/// test of a download against a server of its own needs the program itself and nothing about root.
final class _LocalShell implements Shell {
  const _LocalShell();

  @override
  Future<CommandResult> run(Command command) async {
    final Stopwatch watch = Stopwatch()..start();
    final ProcessResult result = await Process.run(command.executable, command.arguments);
    return CommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
      elapsed: watch.elapsed,
    );
  }
}

/// A body whose bytes differ along its length, so a resume at the wrong offset changes the digest.
Uint8List _bodyOf(int length) =>
    Uint8List.fromList(List<int>.generate(length, (int at) => (at * 31 + (at >> 8) * 7) & 0xff));

/// The SHA-256 of [body], taken the way the step takes it, by the program of the same name.
Future<String> _digestOf(Uint8List body, Directory scratch) async {
  final File file = File('${scratch.path}/body')..writeAsBytesSync(body);
  final ProcessResult result = await Process.run('sha256sum', <String>[file.path]);
  return (result.stdout as String).split(' ').first;
}

/// One machine's step, pinned at [digest] and fetching [address] into its own directory.
InstallPinnedTool _stepFor(String address, String digest, Directory directory) => InstallPinnedTool(
  tool: 'stand-cli',
  version: 'v3.5.5',
  url: '$address/${InstallPinnedTool.versionPlaceholder}/stand-cli',
  sha256: digest,
  directory: directory.path,
  archive: null,
  versionCommand: const <String>['--version'],
  pinPrefixes: const <String>['v'],
);

void main() {
  const StepName under = StepName('under_test');
  const Shell local = _LocalShell();

  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('install-pinned-tool-fetch'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Directory machineDirectory(int number) =>
      Directory('${scratch.path}/machine-$number')..createSync();

  group('a download the registry ends part-way', () {
    // 600 kB at 1 MB/s shared: one machine alone needs 0.6 s, eight together need 4.8 s, and every
    // response is ended after 2 s. The same numbers as 2026-10-19 with the 60 seconds and the
    // 250 MB taken down, which is why the test is scaled and the cut is not.
    final Uint8List body = _bodyOf(600000);
    const int bandwidth = 1000000;
    const Duration cutAfter = Duration(seconds: 2);

    test('eight machines fetching at once all end with the whole file', () async {
      final CuttingStore store = CuttingStore(
        body: body,
        bytesPerSecond: bandwidth,
        cutAfter: cutAfter,
      );
      await store.start();
      addTearDown(store.stop);
      final String digest = await _digestOf(body, scratch);

      final List<HostMachine> machines = <HostMachine>[
        for (int number = 0; number < _machines; number++) HostMachine(),
      ];
      final List<InstallPinnedTool> steps = <InstallPinnedTool>[
        for (int number = 0; number < _machines; number++)
          _stepFor(store.address, digest, machineDirectory(number)),
      ];

      await Future.wait(<Future<void>>[
        for (int number = 0; number < _machines; number++)
          steps[number].apply(
            machines[number].contextFor(under, Arguments.none, hostAnswers, local),
          ),
      ]);

      expect(store.cuts, greaterThan(0), reason: 'the store cut nothing, so nothing was measured');
      for (int number = 0; number < _machines; number++) {
        final File tool = File(steps[number].path);
        expect(tool.readAsBytesSync(), body, reason: 'machine $number');
        expect(File(steps[number].incoming).existsSync(), isFalse, reason: 'machine $number');
      }
      final HostMachine cutOne = machines.firstWhere(
        (HostMachine machine) => machine.said.isNotEmpty,
      );
      final String told = cutOne.said.join('\n');
      expect(told, contains('attempt 1 of ${InstallPinnedTool.fetchAttempts}'));
      expect(told, contains('curl: ('), reason: 'curl\'s own sentence');
      expect(told, contains('${store.address}/v3.5.5/stand-cli'));
      expect(
        cutOne.clock.slept,
        everyElement(InstallPinnedTool.pauseBetweenAttempts),
        reason: 'it waited between attempts and only then',
      );
    });

    test('a download nothing ends is fetched once, silently, with no pause', () async {
      final CuttingStore store = CuttingStore(
        body: body,
        bytesPerSecond: bandwidth,
        cutAfter: const Duration(minutes: 5),
      );
      await store.start();
      addTearDown(store.stop);
      final String digest = await _digestOf(body, scratch);
      final HostMachine machine = HostMachine();
      final InstallPinnedTool step = _stepFor(store.address, digest, machineDirectory(0));

      await step.apply(machine.contextFor(under, Arguments.none, hostAnswers, local));

      expect(File(step.path).readAsBytesSync(), body);
      expect(store.cuts, 0);
      expect(machine.said, isEmpty);
      expect(machine.clock.slept, isEmpty);
    });

    test('a file resumed to the wrong bytes is refused and removed', () async {
      final CuttingStore store = CuttingStore(
        body: body,
        bytesPerSecond: 200000,
        cutAfter: const Duration(seconds: 1),
      );
      await store.start();
      addTearDown(store.stop);
      final HostMachine machine = HostMachine();
      final InstallPinnedTool step = _stepFor(store.address, _plantedDigest, machineDirectory(0));

      await expectLater(
        step.apply(machine.contextFor(under, Arguments.none, hostAnswers, local)),
        throwsA(isA<FetchedReleaseRefused>()),
      );

      expect(
        store.cuts,
        greaterThan(0),
        reason: 'the file was not resumed, so nothing was measured',
      );
      expect(
        File(step.path).existsSync(),
        isFalse,
        reason: 'a refused file never reaches the tool',
      );
      expect(machine.files.deleted, contains(step.incoming));
    });
  });

  group('a download that never gets further', () {
    test('stops after the last attempt with curl\'s own words, and keeps nothing', () async {
      // Ended at the first tick, before a byte is written: the attempts cannot add up to the file.
      final CuttingStore store = CuttingStore(
        body: _bodyOf(1000),
        bytesPerSecond: 1000000,
        cutAfter: Duration.zero,
      );
      await store.start();
      addTearDown(store.stop);
      final HostMachine machine = HostMachine();
      final InstallPinnedTool step = _stepFor(store.address, _plantedDigest, machineDirectory(0));

      await expectLater(
        step.apply(machine.contextFor(under, Arguments.none, hostAnswers, local)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed failed) => failed.message,
            'message',
            contains('curl: ('),
          ),
        ),
      );

      expect(machine.said, hasLength(InstallPinnedTool.fetchAttempts));
      expect(
        machine.said.last,
        contains(
          'attempt ${InstallPinnedTool.fetchAttempts} of ${InstallPinnedTool.fetchAttempts}',
        ),
      );
      expect(machine.clock.slept, hasLength(InstallPinnedTool.fetchAttempts - 1));
      expect(File(step.path).existsSync(), isFalse);
      expect(machine.files.deleted, contains(step.incoming));
    });

    test('is told with the address and never with a credential written in it', () async {
      final HostMachine machine = HostMachine();
      machine.shell.fails(
        'curl --silent --show-error --fail --location --continue-at - --output '
        '/opt/x/stand-cli.incoming https://who:secret@store.example.invalid/v3.5.5/stand-cli',
        exitCode: 92,
        stderr: 'curl: (92) HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR (err 2)',
      );
      const InstallPinnedTool step = InstallPinnedTool(
        tool: 'stand-cli',
        version: 'v3.5.5',
        url:
            'https://who:secret@store.example.invalid/${InstallPinnedTool.versionPlaceholder}/stand-cli',
        sha256: _plantedDigest,
        directory: '/opt/x',
        archive: null,
        versionCommand: <String>['--version'],
        pinPrefixes: <String>['v'],
      );

      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));

      final String told = machine.said.join('\n');
      expect(told, contains('https://store.example.invalid/v3.5.5/stand-cli'));
      expect(told, contains('curl: (92) HTTP/2 stream 1 was not closed cleanly'));
      expect(told, isNot(contains('secret')));
      expect(told, isNot(contains('who')));
    });
  });
}
