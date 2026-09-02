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
