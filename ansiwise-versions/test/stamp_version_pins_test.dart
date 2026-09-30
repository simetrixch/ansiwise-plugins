import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The stamp, driven over a fake machine holding a declaration and the files it names.
///
/// This is the coverage the idempotence ledger points at: the audit's probe cannot line its
/// invented tree labels up with the row's declaration tree, so the property is proven here, where
/// the files can be arranged — applied once the pins land, applied again there is nothing to do,
/// and undone the files are byte for byte what they were.
void main() {
  const String declaration = '''
appliances:
  widget:
    version: "1.2.3"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: parts/widget/values.yaml
        key: tag
        anchor: 'repository: library/widget'
      - kind: chart_dependency
        tree: alpha
        file: parts/bundle/Chart.yaml
        dependency: widget
      - kind: dockerfile_arg
        tree: beta
        file: build/tools.containerfile
        argument: WIDGET_SERIES
        segments: 2
''';
  const String values = '''
image:
  repository: library/widget
  tag: "1.2.2"
''';
  const String chart = '''
dependencies:
  - name: widget
    version: 1.2.2
    repository: https://charts.example.com/stable
''';
  const String build = '''
ARG WIDGET_SERIES=1.1
RUN echo built
''';

  const StampVersionPins step = StampVersionPins(
    declarationTree: 'alpha',
    declarationPath: 'pins.yaml',
    trees: <String, TreeBinding>{
      'alpha': TreeBinding(answer: 'alpha_checkout'),
      'beta': TreeBinding(path: '/srv/beta'),
    },
    fileMode: 420,
  );

  const Arguments answers = Arguments(<String, Object>{'alpha_checkout': '/srv/alpha'});

  FakeFiles filesOn() => FakeFiles(<String, String>{
    '/srv/alpha/pins.yaml': declaration,
    '/srv/alpha/parts/widget/values.yaml': values,
    '/srv/alpha/parts/bundle/Chart.yaml': chart,
    '/srv/beta/build/tools.containerfile': build,
  });

  StepContext contextOn(FakeFiles files, {Arguments held = answers}) => StepContext(
    shell: FakeShell(),
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: CollectedLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: held,
    facts: Facts.none,
  );

  test('stamps every site, and a second run has nothing left to do', () async {
    final FakeFiles files = filesOn();
    final StepContext context = contextOn(files);

    expect(await step.check(context), isA<Ready>());
    final Map<String, String> captured = await step.capture(context);
    await step.apply(context);

    expect(
      files.contents['/srv/alpha/parts/widget/values.yaml'],
      values.replaceFirst('tag: "1.2.2"', 'tag: "1.2.3"'),
    );
    expect(
      files.contents['/srv/alpha/parts/bundle/Chart.yaml'],
      chart.replaceFirst('version: 1.2.2', 'version: 1.2.3'),
    );
    // The series site carries the first two segments, cut by the declaration and nothing else.
    expect(
      files.contents['/srv/beta/build/tools.containerfile'],
      build.replaceFirst('WIDGET_SERIES=1.1', 'WIDGET_SERIES=1.2'),
    );

    final CheckResult again = await step.check(context);
    expect(again, isA<Satisfied>());
    expect((again as Satisfied).because, contains('already stands'));

    // The undo puts back what capture read, byte for byte — the files as they were, not a
    // re-derivation from a machine that has changed since.
    await step.undo(context, captured);
    expect(files.contents['/srv/alpha/parts/widget/values.yaml'], values);
    expect(files.contents['/srv/alpha/parts/bundle/Chart.yaml'], chart);
    expect(files.contents['/srv/beta/build/tools.containerfile'], build);
  });

  test('the plan names every line that would change, per file', () async {
    final StepContext context = contextOn(filesOn());
    final StepPlan plan = await step.plan(context);
    expect(plan, isA<DiffPlan>());
    final DiffPlan diff = plan as DiffPlan;
    expect(diff.before, contains('tag: "1.2.2"'));
    expect(diff.after, contains('tag: "1.2.3"'));
    expect(diff.before, contains('WIDGET_SERIES=1.1'));
    expect(diff.after, contains('WIDGET_SERIES=1.2'));
  });

  test('a declaration site the tree lost is a refusal naming it, and nothing is written', () async {
    // The planted defect: the chart no longer declares the dependency the declaration stamps. A
    // stamper matching loosely prints success here while the pin goes nowhere, which is exactly
    // what the refusal above prevents.
    final FakeFiles files = filesOn();
    files.contents['/srv/alpha/parts/bundle/Chart.yaml'] = chart.replaceFirst(
      '- name: widget',
      '- name: renamed',
    );
    final StepContext context = contextOn(files);
    final CheckResult refused = await step.check(context);
    expect(refused, isA<Blocked>());
    expect((refused as Blocked).reason, contains('"widget"'));
    expect(files.written, isEmpty);
  });

  test('a run without the answer a tree binding names is refused naming the answer', () async {
    final CheckResult refused = await step.check(contextOn(filesOn(), held: Arguments.none));
    expect(refused, isA<Blocked>());
    expect((refused as Blocked).reason, contains('"alpha_checkout"'));
  });

  group('a digest beside its pin', () {
    const String old = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
    const String bumped = 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2';
    const String other = 'c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3';
    const String pinned =
        '''
tools:
  widget-cli:
    version: "v1.3.0"
    sha256: "$bumped"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: version
        anchor: 'tool: widget-cli'
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: sha256
        anchor: 'tool: widget-cli'
        writes: sha256
''';
    const String program =
        '''
steps:
  - step: fetch_tool
    tool: widget-cli
    version: v1.2.0
    sha256: $old
  - step: fetch_tool
    tool: gadget-cli
    version: v9.9.9
    sha256: $other
''';

    FakeFiles filesHolding(String rows) => FakeFiles(<String, String>{
      '/srv/alpha/pins.yaml': pinned,
      '/srv/alpha/programs/setup.yaml': rows,
    });

    test('lands in the one row the anchor names', () async {
      // Two rows of the same step, so the anchor is what separates them: the digest of one tool
      // written into the other's row would be a fetch refused on every machine.
      final FakeFiles files = filesHolding(program);
      final StepContext context = contextOn(files);

      await step.apply(context);

      expect(
        files.contents['/srv/alpha/programs/setup.yaml'],
        program
            .replaceFirst('version: v1.2.0', 'version: v1.3.0')
            .replaceFirst('sha256: $old', 'sha256: $bumped'),
      );
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a row with no digest line is refused, and nothing is written', () async {
      // The row as it stood before digests: the stamp edits a value and never adds a key, so the
      // row gains its sha256 line by hand once, and a stamp that finds none says so rather than
      // stamping the version alone.
      final FakeFiles files = filesHolding(program.replaceFirst('    sha256: $old\n', ''));

      final CheckResult refused = await step.check(contextOn(files));

      expect(refused, isA<Blocked>());
      expect((refused as Blocked).reason, allOf(contains('widget-cli'), contains('sha256')));
      expect(files.written, isEmpty);
    });
  });

  test('a missing target file is a refusal naming file and component', () async {
    final FakeFiles files = filesOn();
    files.contents.remove('/srv/beta/build/tools.containerfile');
    final CheckResult refused = await step.check(contextOn(files));
    expect(refused, isA<Blocked>());
    expect(
      (refused as Blocked).reason,
      allOf(contains('/srv/beta/build/tools.containerfile'), contains('widget')),
    );
  });
}
