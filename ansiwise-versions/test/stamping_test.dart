import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

/// The surgical stampers: one value token changes, everything else stays byte for byte, and a
/// site that cannot be found — or could mean two places — refuses instead of guessing.
///
/// Every refusal asserted here is the planted-defect half of its pair: the same content with the
/// site present is stamped in the innocent case beside it, so a refusal that stopped firing would
/// fail the red half and a stamper that started guessing would fail the green one.
void main() {
  group('yaml_value under an anchor', () {
    const YamlValueStamp tag = YamlValueStamp(
      tree: 'alpha',
      file: 'values.yaml',
      key: 'tag',
      anchor: 'repository: library/widget',
    );
    const String values = '''
spares:
  image:
    repository: library/spare
    tag: "9.9.9"
  replicas: 1
widget:
  image:
    repository: library/widget
    # Managed centrally — do not hand-edit this tag.
    tag: "1.2.2"
    pullPolicy: IfNotPresent
''';

    test('replaces exactly the anchored value and keeps every other byte', () {
      final StampOutcome outcome = stampInto(values, tag, '1.2.3');
      expect(outcome, isA<StampReady>());
      final StampReady ready = outcome as StampReady;
      expect(ready.content, values.replaceFirst('tag: "1.2.2"', 'tag: "1.2.3"'));
      // The neighbour image's tag — same key, other anchor — stands untouched.
      expect(ready.content, contains('tag: "9.9.9"'));
      // The comment above the value survived the edit that changed the line below it.
      expect(ready.content, contains('# Managed centrally — do not hand-edit this tag.'));
    });

    test('stands when the pin is already there', () {
      final StampOutcome outcome = stampInto(values, tag, '1.2.2');
      expect(outcome, isA<StampStands>());
    });

    test('refuses a file that lost the anchor, instead of stamping something else', () {
      final String drifted = values.replaceFirst(
        'repository: library/widget',
        'repository: elsewhere/widget',
      );
      final StampOutcome outcome = stampInto(drifted, tag, '1.2.3');
      expect(outcome, isA<StampRefused>());
      expect((outcome as StampRefused).reason, contains('repository: library/widget'));
    });

    test('refuses an anchor that stands twice, instead of picking one', () {
      const String doubled = '$values$values';
      final StampOutcome outcome = stampInto(doubled, tag, '1.2.3');
      expect(outcome, isA<StampRefused>());
      expect((outcome as StampRefused).reason, contains('not exactly once'));
    });

    test('keeps carriage returns where a working copy carries them', () {
      final String windows = values.replaceAll('\n', '\r\n');
      final StampReady ready = stampInto(windows, tag, '1.2.3') as StampReady;
      expect(ready.content, windows.replaceFirst('tag: "1.2.2"', 'tag: "1.2.3"'));
    });

    test('keeps the quoting style each line already has', () {
      const YamlValueStamp channel = YamlValueStamp(
        tree: 'alpha',
        file: 'program.yaml',
        key: 'channel',
        // The whole trimmed line, dash included: a row's opening line IS a list item.
        anchor: '- step: install_widget',
      );
      const String program = '''
steps:
  - step: install_widget
    channel: 1.35/stable
    classic: true
  - step: wait_for_widget
    channel: ignored/stable
''';
      final StampReady ready = stampInto(program, channel, '1.36/stable') as StampReady;
      // Unquoted stays unquoted, and the block ends at the next row: the second row's channel is
      // another row's business.
      expect(ready.content, program.replaceFirst('channel: 1.35/stable', 'channel: 1.36/stable'));
    });
  });

  group('yaml_value at the top level', () {
    const YamlValueStamp appVersion = YamlValueStamp(
      tree: 'alpha',
      file: 'Chart.yaml',
      key: 'appVersion',
    );
    const String chart = '''
apiVersion: v2
name: widget
version: 1.0.0
appVersion: "1.2.2"
dependencies:
  - name: liner
    version: 1.0.0
''';

    test('finds the one top-level key and leaves the dependency versions alone', () {
      final StampReady ready = stampInto(chart, appVersion, '1.2.3') as StampReady;
      expect(ready.content, chart.replaceFirst('appVersion: "1.2.2"', 'appVersion: "1.2.3"'));
    });
  });

  group('chart_dependency', () {
    const ChartDependencyStamp gadget = ChartDependencyStamp(
      tree: 'alpha',
      file: 'Chart.yaml',
      dependency: 'gadget',
    );
    const String chart = '''
apiVersion: v2
name: bundle
version: 1.0.0
dependencies:
  - name: liner
    version: 1.0.0
    repository: file://../liner

  # The wrapped upstream chart.
  - name: gadget
    version: 4.5.5
    repository: https://charts.example.com/stable
  - name: gadget-extras
    version: 0.1.0
    repository: https://charts.example.com/stable
''';

    test('stamps the named dependency and no other', () {
      final StampReady ready = stampInto(chart, gadget, '4.5.6') as StampReady;
      expect(ready.content, chart.replaceFirst('version: 4.5.5', 'version: 4.5.6'));
      // `gadget-extras` merely begins with the name; the anchor is the whole trimmed line, so it
      // is a different dependency and untouched.
      expect(ready.content, contains('- name: gadget-extras\n    version: 0.1.0'));
    });

    test('refuses a dependency the chart does not declare — the silent-miss defect', () {
      // The planted defect this kind exists for: the predecessor's stamper matched nothing and
      // printed success, and the pin went nowhere.
      const ChartDependencyStamp missing = ChartDependencyStamp(
        tree: 'alpha',
        file: 'Chart.yaml',
        dependency: 'nowhere',
      );
      final StampOutcome outcome = stampInto(chart, missing, '4.5.6');
      expect(outcome, isA<StampRefused>());
      expect((outcome as StampRefused).reason, contains('"nowhere"'));
    });

    test('reads the repository of the same block for the report', () {
      final ({String? repository, String? whyNot}) named = chartDependencyRepository(
        chart,
        'gadget',
      );
      expect(named.repository, 'https://charts.example.com/stable');
      final ({String? repository, String? whyNot}) absent = chartDependencyRepository(
        chart,
        'nowhere',
      );
      expect(absent.repository, isNull);
      expect(absent.whyNot, contains('"nowhere"'));
    });
  });

  group('list_pin', () {
    const ListPinStamp widget = ListPinStamp(
      tree: 'alpha',
      file: 'program.yaml',
      anchor: 'tools:',
      entry: 'widget',
    );
    const String program = '''
  - step: assert_tool_versions
    tools:
      - widget=v1.2.2
      - gadget=v4.5.6
    version_commands:
      - widget=version --client
      - gadget=version
    on_failure: continue
''';

    test('stamps the entry in the anchored list and not its namesake in the next list', () {
      // The trap this anchor exists for: the same name opens an entry in TWO lists of one row —
      // the pins and the words each tool is asked its version with — and only the first is a pin.
      final StampReady ready = stampInto(program, widget, 'v1.2.3') as StampReady;
      expect(ready.content, program.replaceFirst('- widget=v1.2.2', '- widget=v1.2.3'));
      expect(ready.content, contains('- widget=version --client'));
    });

    test('refuses an entry the list does not carry', () {
      const ListPinStamp absent = ListPinStamp(
        tree: 'alpha',
        file: 'program.yaml',
        anchor: 'tools:',
        entry: 'liner',
      );
      final StampOutcome outcome = stampInto(program, absent, 'v1.2.3');
      expect(outcome, isA<StampRefused>());
      expect((outcome as StampRefused).reason, contains('"liner="'));
    });
  });

  group('dockerfile_from', () {
    const DockerfileFromStamp base = DockerfileFromStamp(
      tree: 'beta',
      file: 'tools.containerfile',
      image: 'library/base',
    );
    const String build = '''
FROM docker.io/library/toolchain:9 AS tools

FROM docker.io/library/base:12-slim
RUN echo built
''';

    test('restamps the one FROM naming the image and leaves the other stage alone', () {
      final StampReady ready = stampInto(build, base, '13-slim') as StampReady;
      expect(ready.content, build.replaceFirst('library/base:12-slim', 'library/base:13-slim'));
      expect(ready.content, contains('library/toolchain:9 AS tools'));
    });

    test('refuses a file with no FROM naming the image', () {
      const DockerfileFromStamp other = DockerfileFromStamp(
        tree: 'beta',
        file: 'tools.containerfile',
        image: 'library/nowhere',
      );
      expect(stampInto(build, other, '13-slim'), isA<StampRefused>());
    });
  });

  group('dockerfile_arg', () {
    const DockerfileArgStamp series = DockerfileArgStamp(
      tree: 'beta',
      file: 'tools.containerfile',
      argument: 'WIDGET_SERIES',
      segments: 2,
    );
    const String build = '''
ARG WIDGET_SERIES=1.1
ARG OTHER_MAJOR=18
RUN echo built
''';

    test('stamps the named ARG with the cut the declaration states', () {
      final StampReady ready = stampInto(build, series, series.valueOf('1.2.3')) as StampReady;
      expect(ready.content, build.replaceFirst('WIDGET_SERIES=1.1', 'WIDGET_SERIES=1.2'));
    });

    test('MUST find its target: a missing ARG refuses instead of skipping', () {
      // The out-of-repository write the pair's ticket names: a silent miss here leaves a sibling
      // repository's image building on whatever its file says today, with no diff anywhere.
      const DockerfileArgStamp absent = DockerfileArgStamp(
        tree: 'beta',
        file: 'tools.containerfile',
        argument: 'ABSENT_SERIES',
      );
      final StampOutcome outcome = stampInto(build, absent, '1.2');
      expect(outcome, isA<StampRefused>());
      expect((outcome as StampRefused).reason, contains('states no ARG "ABSENT_SERIES"'));
    });
  });
}
