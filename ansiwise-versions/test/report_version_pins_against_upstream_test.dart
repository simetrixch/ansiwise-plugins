import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The report, driven over a fake network serving each kind of upstream.
///
/// Four properties carry the step's whole character and each is asserted against real traps:
/// the newest tag is found on the SECOND page of a paginated list, so a reader that stopped at
/// one page fails here; the chart repository asked is the one the stamped Chart.yaml names, so
/// the coupling the shared declaration exists for is measured and not assumed; a feed that
/// answers 500 makes a "?" row while the step still ends satisfied, because a report that can
/// go red stops meaning what a report means; and a pin written in a pre-release shape resolves to
/// a version, with the row saying the answer is a Git source tag.
void main() {
  const String declaration = '''
appliances:
  widget:
    version: "1.2.2"
    note: held back on purpose
    upstream:
      kind: docker_hub
      image: library/widget
      matching: '^[0-9]+\\.[0-9]+\\.[0-9]+\$'
    stamps:
      - kind: yaml_value
        tree: alpha
        file: parts/widget/values.yaml
        key: tag
        anchor: 'repository: library/widget'
  gadget:
    version: "4.5.6"
    upstream:
      kind: chart_repository
    stamps:
      - kind: chart_dependency
        tree: alpha
        file: parts/bundle/Chart.yaml
        dependency: gadget
tools:
  liner:
    version: "v9.0.0"
    upstream:
      kind: git_tags
      project: example/liner
      matching: '^v[0-9]+\\.[0-9]+\\.[0-9]+\$'
  planer:
    version: "0.3.0-alpha-20260825130748"
    upstream:
      kind: git_tags
      project: example/planer
      matching: '^[0-9]+\\.[0-9]+\\.[0-9]+-alpha-[0-9]{14}\$'
    stamps:
      - kind: yaml_value
        tree: alpha
        file: parts/planer/values.yaml
        key: version
''';
  const String chart = '''
dependencies:
  - name: gadget
    version: 4.5.6
    repository: https://charts.example.com/stable
''';

  const ReportVersionPinsAgainstUpstream step = ReportVersionPinsAgainstUpstream(
    declarationTree: 'alpha',
    declarationPath: 'pins.yaml',
    trees: <String, TreeBinding>{'alpha': TreeBinding(path: '/srv/alpha')},
    timeoutSeconds: 5,
  );

  FakeFiles filesOn() => FakeFiles(<String, String>{
    '/srv/alpha/pins.yaml': declaration,
    '/srv/alpha/parts/bundle/Chart.yaml': chart,
  });

  FakeHttp networkOn() {
    final FakeHttp http = FakeHttp();
    // The image's tag list, PAGINATED, with the newest tag on the second page and the first page
    // topped by an older one — the exact shape that makes a one-page reader report a version two
    // minors old.
    http.answers(
      'GET https://hub.docker.com/v2/repositories/library/widget/tags'
      '?page_size=100&ordering=last_updated',
      body:
          '{"next": "https://hub.docker.com/v2/repositories/library/widget/tags?page=2", '
          '"results": [{"name": "1.2.9"}, {"name": "latest"}, {"name": "0.9.0"}]}',
    );
    http.answers(
      'GET https://hub.docker.com/v2/repositories/library/widget/tags?page=2',
      body: '{"next": null, "results": [{"name": "1.3.0"}, {"name": "1.2.10"}]}',
    );
    // The chart repository the stamped Chart.yaml names — and no other address is asked.
    http.answers(
      'GET https://charts.example.com/stable/index.yaml',
      body: '''
entries:
  gadget:
    - version: 4.5.6
    - version: 4.6.0
    - version: 4.5.9
''',
    );
    // The ref list answers a server error today; the row reads "?" and the report stands.
    http.answers(refsOf('example/liner'), status: 500);
    // A project that cuts every tag on a pre-release channel: the pin is written in that shape, so
    // the tag competes, and the row has to say that a tag is source and nothing more.
    http.answers(
      refsOf('example/planer'),
      body: refList(<String>[
        'HEAD',
        'refs/heads/main',
        'refs/tags/0.5.0-alpha-20260825232305',
        'refs/tags/0.5.1-alpha-20260826000332',
      ]),
    );
    return http;
  }

  StepContext contextOn({required Files files, required Http http, required Logger log}) =>
      StepContext(
        shell: FakeShell(),
        files: files,
        http: http,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: log,
        step: const StepName('under_test'),
        arguments: Arguments.none,
        answers: Arguments.none,
        facts: Facts.none,
      );

  test('reports every pin, follows every page, and asks the declared chart repository', () async {
    final CollectedLog log = CollectedLog();
    final FakeHttp http = networkOn();
    final CheckResult verdict = await step.check(contextOn(files: filesOn(), http: http, log: log));

    // NEVER a failure: one feed answered 500 and the step is still satisfied, saying how much of
    // the report is a question mark.
    expect(verdict, isA<Satisfied>());
    expect((verdict as Satisfied).because, contains('4 pin(s)'));
    expect(verdict.because, contains('1 of them unresolved'));

    String rowOf(String component) => log.lines.firstWhere(
      (String line) => line.trimLeft().startsWith(component),
      orElse: () => fail('the report has no row for $component'),
    );

    // The newest tag stood on the second page; 1.2.9 topped the first and must not be the answer.
    expect(rowOf('widget'), allOf(contains('1.2.2'), contains('1.3.0')));
    expect(rowOf('widget'), contains('held back on purpose'));
    // The chart's answer comes from the repository the Chart.yaml names, maximum over an unsorted
    // index, not the last entry.
    expect(rowOf('gadget'), allOf(contains('4.5.6'), contains('4.6.0')));
    // The broken feed is a finding about the report, and it says so in the row — and the pin
    // nothing stamps anywhere is named as such.
    expect(rowOf('liner'), allOf(contains('v9.0.0'), contains('?'), contains('answered 500')));
    expect(rowOf('liner'), contains('stamped nowhere'));
    // The pin written in a pre-release shape RESOLVES, and the row names what the answer is, so a
    // reader is never handed a tag as proof that an artifact was published.
    expect(
      rowOf('planer'),
      allOf(
        contains('0.3.0-alpha-20260825130748'),
        contains('0.5.1-alpha-20260826000332'),
        contains('a Git source tag'),
      ),
    );
    // Both pages were really fetched.
    expect(
      http.sent,
      containsAll(<String>[
        'GET https://hub.docker.com/v2/repositories/library/widget/tags'
            '?page_size=100&ordering=last_updated',
        'GET https://hub.docker.com/v2/repositories/library/widget/tags?page=2',
        'GET https://charts.example.com/stable/index.yaml',
        refsOf('example/liner'),
        refsOf('example/planer'),
      ]),
    );
    // A tag list is Git content. The host's API is asked by nothing here, and a reader that quietly
    // went back to it would pass every assertion above.
    expect(http.sent.where((String asked) => asked.contains('api.github.com')), isEmpty);
  });

  test('a list the registry cuts short is answered from what it served, saying so', () async {
    // Measured live: the largest images' tag lists are rationed, and around page eleven the
    // registry starts answering 403. An answer of "?" for exactly the images most worth watching
    // would gut the report, and trusting one page is the lie pagination invites — so the reading
    // asks newest-updated first, takes the maximum over what WAS served, and carries the
    // truncation as a caveat the row prints.
    final FakeHttp http = FakeHttp();
    http.answers(
      'GET https://hub.docker.com/v2/repositories/library/widget/tags'
      '?page_size=100&ordering=last_updated',
      body:
          '{"next": "https://hub.docker.com/v2/repositories/library/widget/tags?page=2", '
          '"results": [{"name": "1.3.0"}, {"name": "1.2.9"}]}',
    );
    http.answers(
      'GET https://hub.docker.com/v2/repositories/library/widget/tags?page=2',
      status: 403,
    );
    final UpstreamReading reading = await dockerHubNewestTag(
      http,
      'library/widget',
      r'^[0-9]+\.[0-9]+\.[0-9]+$',
      timeout: const Duration(seconds: 5),
    );
    expect(reading.newest, '1.3.0');
    expect(reading.caveat, contains('refused the rest of the list after 1 page(s)'));
  });

  group('the tags of a Git repository', () {
    const String stable = r'^v[0-9]+\.[0-9]+\.[0-9]+$';
    const Duration timeout = Duration(seconds: 5);
    const String caveat = 'a Git source tag: no artifact is known to be served for it';

    test('a matching stable tag is the answer, saying a tag is source', () async {
      final FakeHttp http = FakeHttp()
        ..answers(
          refsOf('example/liner'),
          body: refList(<String>['HEAD', 'refs/heads/main', 'refs/tags/v1.2.3']),
        );
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/liner',
        stable,
        timeout: timeout,
      );
      expect(reading.newest, 'v1.2.3');
      expect(reading.caveat, caveat);
      // One request, to the address a `git ls-remote` asks: the whole list comes in one answer.
      expect(http.sent, <String>[refsOf('example/liner')]);
    });

    test(
      'a stable pin is told of neither a candidate, a stray tag, a branch nor a peeled line',
      () async {
        // Git lists refs in byte order, so the newest version is neither the first nor the last
        // line: v3.10.0 stands before v3.4.7 as text, a candidate stands above both, and a branch
        // named like a version is not a tag at all.
        final FakeHttp http = FakeHttp()
          ..answers(
            refsOf('example/liner'),
            body: refList(<String>[
              'HEAD',
              'refs/heads/main',
              'refs/heads/v9.9.9',
              'refs/tags/nightly',
              'refs/tags/v3.10.0',
              'refs/tags/v3.4.7',
              'refs/tags/v3.4.7^{}',
              'refs/tags/v3.9.0',
              'refs/tags/v4.0.0-rc1',
            ]),
          );
        final UpstreamReading reading = await gitNewestTag(
          http,
          'example/liner',
          stable,
          timeout: timeout,
        );
        expect(reading.newest, 'v3.10.0');
        expect(reading.caveat, caveat);
      },
    );

    test('a peeled line is the tag it peels and never a candidate of its own', () async {
      // A pattern loose enough to admit the peeled spelling would otherwise read it as a version
      // tying with the tag and winning the tie on its text.
      final FakeHttp http = FakeHttp()
        ..answers(
          refsOf('example/liner'),
          body: refList(<String>[
            'HEAD',
            'refs/tags/v0.9.0',
            'refs/tags/v1.0.0',
            'refs/tags/v1.0.0^{}',
          ]),
        );
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/liner',
        r'^v.+$',
        timeout: timeout,
      );
      expect(reading.newest, 'v1.0.0');
    });

    test('the first group of the pattern is the version a tag stands for', () async {
      // One repository carries the tags of several charts, each with its own name in front of the
      // number, so the pin spells the number alone and the tags of the other charts do not compete.
      final FakeHttp http = FakeHttp()
        ..answers(
          refsOf('example/charts'),
          body: refList(<String>[
            'HEAD',
            'refs/tags/other-chart-99.0.0',
            'refs/tags/stack-87.2.0',
            'refs/tags/stack-87.21.0',
            'refs/tags/stack-88.0.0-rc1',
          ]),
        );
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/charts',
        r'^stack-([0-9]+\.[0-9]+\.[0-9]+)$',
        timeout: timeout,
      );
      expect(reading.newest, '87.21.0');
      expect(reading.caveat, caveat);
    });

    test('the capabilities after the NUL of the first line are no part of a tag', () async {
      // A repository with no HEAD advertises its capabilities on whichever ref comes first.
      final FakeHttp http = FakeHttp()
        ..answers(refsOf('example/liner'), body: refList(<String>['refs/tags/v1.0.0']));
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/liner',
        stable,
        timeout: timeout,
      );
      expect(reading.newest, 'v1.0.0');
    });

    test('a list holding no tag of the declared shape is unresolved, with the pattern', () async {
      final FakeHttp http = FakeHttp()
        ..answers(
          refsOf('example/liner'),
          body: refList(<String>['HEAD', 'refs/heads/main', 'refs/tags/v1.0.0-rc1']),
        );
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/liner',
        stable,
        timeout: timeout,
      );
      expect(reading.newest, isNull);
      expect(reading.unresolved, allOf(contains('example/liner'), contains(stable)));
    });

    test('a project with no repository is unresolved, with the status', () async {
      final FakeHttp http = FakeHttp()..answers(refsOf('example/missing'), status: 404);
      final UpstreamReading reading = await gitNewestTag(
        http,
        'example/missing',
        stable,
        timeout: timeout,
      );
      expect(reading.newest, isNull);
      expect(reading.unresolved, contains('answered 404'));
    });

    test('an empty answer and a page that is no ref list are unresolved', () async {
      for (final String body in <String>[
        '',
        '001e# service=git-upload-pack\n00000000',
        '<html><body>Not a repository</body></html>',
      ]) {
        final FakeHttp http = FakeHttp()..answers(refsOf('example/liner'), body: body);
        final UpstreamReading reading = await gitNewestTag(
          http,
          'example/liner',
          stable,
          timeout: timeout,
        );
        expect(reading.newest, isNull, reason: 'body: $body');
        expect(reading.unresolved, contains('not a Git ref list'), reason: 'body: $body');
      }
    });

    test('a host that cannot be asked is unresolved, with the failure', () async {
      final UpstreamReading reading = await gitNewestTag(
        _Unreachable(),
        'example/liner',
        stable,
        timeout: timeout,
      );
      expect(reading.newest, isNull);
      expect(
        reading.unresolved,
        allOf(contains(refsOf('example/liner').substring(4)), contains('no route')),
      );
    });
  });

  test('a registry speaking the distribution protocol is asked with its own token flow', () async {
    final _AnonymousThenTokened registry = _AnonymousThenTokened();
    final UpstreamReading reading = await registryNewestTag(
      registry,
      'registry.example.com',
      'parts/widget',
      r'^v[0-9]+\.[0-9]+\.[0-9]+$',
      timeout: const Duration(seconds: 5),
    );
    // The anonymous ask was refused, the token endpoint the refusal itself named was asked, and
    // the retried ask carried the minted token — so the tags arrived and the maximum is over
    // BOTH pages the registry served, linked by its own headers.
    expect(reading.newest, 'v2.0.0');
    expect(registry.sent, <String>[
      'GET https://registry.example.com/v2/parts/widget/tags/list?n=1000',
      'GET https://registry.example.com/token?scope=repository:parts/widget:pull'
          '&service=registry.example.com',
      'GET https://registry.example.com/v2/parts/widget/tags/list?n=1000',
      'GET https://registry.example.com/v2/parts/widget/tags/list?n=1000&page=2',
    ]);
  });

  test('a declaration that does not parse refuses the step — a defect of the file, not the '
      'feeds', () async {
    final FakeFiles files = filesOn();
    files.contents['/srv/alpha/pins.yaml'] = 'ground:\n  version: 26.04\n';
    final CheckResult refused = await step.check(
      contextOn(files: files, http: FakeHttp(), log: CollectedLog()),
    );
    expect(refused, isA<Blocked>());
    expect((refused as Blocked).reason, contains('write it quoted'));
  });
}

/// A registry that refuses the anonymous ask, mints a token, and then serves two linked pages.
///
/// Written out rather than arranged on [FakeHttp], because that fake keys an answer by address
/// alone and this flow answers ONE address differently before and after the token — which is the
/// very thing the flow is about.
final class _AnonymousThenTokened implements Http {
  /// Every request, as `METHOD url`, in order.
  final List<String> sent = <String>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    sent.add('${request.method} ${request.url}');
    if (request.url.contains('/token?')) {
      return _answer(200, '{"token": "minted"}');
    }
    if (request.headers['Authorization'] != 'Bearer minted') {
      return const HttpAnswer(
        status: 401,
        body: '',
        headers: <String, String>{
          'www-authenticate':
              'Bearer realm="https://registry.example.com/token",service="registry.example.com"',
        },
        elapsed: Duration.zero,
      );
    }
    if (request.url.endsWith('page=2')) {
      return _answer(200, '{"tags": ["v2.0.0", "v1.0.1"]}');
    }
    return const HttpAnswer(
      status: 200,
      body: '{"tags": ["v1.9.9", "unrelated-shape"]}',
      headers: <String, String>{'link': '</v2/parts/widget/tags/list?n=1000&page=2>; rel="next"\r'},
      elapsed: Duration.zero,
    );
  }

  HttpAnswer _answer(int status, String body) => HttpAnswer(
    status: status,
    body: body,
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );
}

/// The request that asks the Git refs of [project], as the fake network keys it.
String refsOf(String project) =>
    'GET https://github.com/$project.git/info/refs?service=git-upload-pack';

/// What github.com answers for the refs of a repository: the service line, a flush, one pkt-line per
/// ref, and a flush — the first ref carrying the server's capabilities after a NUL.
String refList(List<String> refs) {
  final StringBuffer body = StringBuffer('001e# service=git-upload-pack\n0000');
  for (int index = 0; index < refs.length; index++) {
    final String ref = index == 0
        ? '${refs[index]}\u0000multi_ack thin-pack side-band agent=git/test'
        : refs[index];
    final String line = '${index.toRadixString(16).padLeft(40, '0')} $ref\n';
    body.write('${(line.length + 4).toRadixString(16).padLeft(4, '0')}$line');
  }
  body.write('0000');
  return body.toString();
}

/// A network with no route to anywhere.
final class _Unreachable implements Http {
  @override
  Future<HttpAnswer> send(HttpRequest request) => Future<HttpAnswer>.error('no route to host');
}
