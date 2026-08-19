import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The report, driven over a fake network serving each kind of upstream.
///
/// Three properties carry the step's whole character and each is asserted against real traps:
/// the newest tag is found on the SECOND page of a paginated list, so a reader that stopped at
/// one page fails here; the chart repository asked is the one the stamped Chart.yaml names, so
/// the coupling the shared declaration exists for is measured and not assumed; and a feed that
/// answers 500 makes a "?" row while the step still ends satisfied, because a report that can
/// go red stops meaning what a report means.
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
      kind: github_release
      project: example/liner
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
    // topped by an older one — the exact shape that once made a one-page reader report a version
    // two minors old.
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
    // The release feed answers a server error today; the row reads "?" and the report stands.
    http.answers('GET https://api.github.com/repos/example/liner/releases/latest', status: 500);
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
    expect((verdict as Satisfied).because, contains('3 pin(s)'));
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
    // Both pages were really fetched.
    expect(
      http.sent,
      containsAll(<String>[
        'GET https://hub.docker.com/v2/repositories/library/widget/tags'
            '?page_size=100&ordering=last_updated',
        'GET https://hub.docker.com/v2/repositories/library/widget/tags?page=2',
        'GET https://charts.example.com/stable/index.yaml',
      ]),
    );
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
