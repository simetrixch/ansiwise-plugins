import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:test/test.dart';

/// The declaration grammar: everything it accepts is carried whole, and everything it does not is
/// refused by name, all problems at once.
///
/// The refusals are the point, not a nicety. A report that parses a stamper's source to learn where
/// a pin is written is emptied silently by a rename; here the shared file is the only coupling, so
/// a typo in it must be a loud stop — `stamp:` for `stamps:` accepted quietly would be a pin
/// nothing ever writes, with no symptom anywhere.
void main() {
  const String whole = '''
appliances:
  widget:
    version: "1.2.3"
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
      - kind: dockerfile_arg
        tree: beta
        file: build/tools.containerfile
        argument: WIDGET_SERIES
        segments: 2
  gadget:
    version: "4.5.6"
    upstream:
      kind: chart_repository
    stamps:
      - kind: chart_dependency
        tree: alpha
        file: parts/gadget/Chart.yaml
        dependency: gadget
ground:
  version: "26.04"
''';

  test('a whole declaration is carried whole', () {
    final VersionsDeclaration declaration = parseDeclaration(whole, where: 'pins.yaml');
    expect(declaration.groups, <String>['appliances', 'ground']);
    expect(declaration.ofGroup('appliances').map((PinnedComponent c) => c.name), <String>[
      'widget',
      'gadget',
    ]);
    final PinnedComponent widget = declaration.components.first;
    expect(widget.version, '1.2.3');
    expect(widget.note, 'held back on purpose');
    expect(widget.upstream, isA<DockerHubTags>());
    expect(widget.stamps, hasLength(2));
    expect(widget.stamps.last, isA<DockerfileArgStamp>());
    // The series site takes the first two segments of the pin, and the whole pin stays elsewhere.
    expect(widget.stamps.last.valueOf(widget.version), '1.2');
    expect(widget.stamps.first.valueOf(widget.version), '1.2.3');
    // A component declared at the top level is its own group, for the odd fact that fits none.
    expect(declaration.ofGroup('ground').single.label, 'ground');
    expect(declaration.ofGroup('ground').single.stamps, isEmpty);
  });

  test('a key the grammar does not know is refused by name — on a stamp', () {
    // The planted defect: `ancher` for `anchor`. Accepted quietly, this stamp would fall back to
    // the top level and stamp a different line than the author aimed at, or refuse at the tree
    // with a message about the file rather than about the typo that caused it.
    const String misspelled = '''
appliances:
  widget:
    version: "1.2.3"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: parts/widget/values.yaml
        key: tag
        ancher: 'repository: library/widget'
''';
    expect(
      () => parseDeclaration(misspelled, where: 'pins.yaml'),
      throwsA(
        isA<DeclarationInvalid>().having(
          (DeclarationInvalid refused) => refused.toString(),
          'the refusal',
          contains('"ancher"'),
        ),
      ),
    );
  });

  test('a version that is not text is refused, because the parser would have changed it', () {
    // 26.04 read as a number is 26.04 the float — the trailing zero is gone before anything can
    // stamp it, so the refusal has to come before the reading is believed.
    const String bare = '''
ground:
  version: 26.04
''';
    expect(
      () => parseDeclaration(bare, where: 'pins.yaml'),
      throwsA(
        isA<DeclarationInvalid>().having(
          (DeclarationInvalid refused) => refused.toString(),
          'the refusal',
          contains('write it quoted'),
        ),
      ),
    );
  });

  test('an upstream kind nobody wrote is refused with the kinds that exist', () {
    const String unknown = '''
appliances:
  widget:
    version: "1.2.3"
    upstream:
      kind: word_of_mouth
''';
    expect(
      () => parseDeclaration(unknown, where: 'pins.yaml'),
      throwsA(
        isA<DeclarationInvalid>().having(
          (DeclarationInvalid refused) => refused.toString(),
          'the refusal',
          allOf(contains('word_of_mouth'), contains('docker_hub')),
        ),
      ),
    );
  });

  test('a release-feed upstream that says which shapes it will see is carried whole', () {
    const String channelled = '''
tools:
  liner:
    version: "v9.0.0"
    upstream:
      kind: github_release
      project: example/liner
      matching: '^v[0-9]+\\.[0-9]+\\.[0-9]+\$'
''';
    final VersionsDeclaration declaration = parseDeclaration(channelled, where: 'pins.yaml');
    final Upstream? upstream = declaration.components.single.upstream;
    expect(upstream, isA<GithubRelease>());
    expect((upstream! as GithubRelease).matching, r'^v[0-9]+\.[0-9]+\.[0-9]+$');
  });

  test('a release-feed upstream naming no shape it will see is refused', () {
    // A release list carries every channel a project ever cut, so a pin that says nothing about
    // which of them it follows would be answered with whichever one happens to sort highest — a
    // release candidate read as a version to move to. The pin has to say, and there is no default
    // to fall back on: which channel a component follows is the product's decision.
    const String silent = '''
tools:
  liner:
    version: "v9.0.0"
    upstream:
      kind: github_release
      project: example/liner
''';
    expect(
      () => parseDeclaration(silent, where: 'pins.yaml'),
      throwsA(
        isA<DeclarationInvalid>().having(
          (DeclarationInvalid refused) => refused.toString(),
          'the refusal',
          contains('"matching"'),
        ),
      ),
    );
  });

  group('the digest beside a pin', () {
    const String digest = '3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b';

    /// A component named [name] whose digest is written as [written], with a stamp that writes it.
    String writtenAs(String name, String written) =>
        '''
  $name:
    version: "v1.0.0"
    sha256: $written
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: sha256
        anchor: 'tool: $name'
        writes: sha256
''';

    test('is carried, and only the stamp that says so writes it', () {
      const String pinned =
          '''
tools:
  widget-cli:
    version: "v1.2.3"
    sha256: "$digest"
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
      - kind: yaml_value
        tree: alpha
        file: programs/manifest.yaml
        key: tag
        writes: version
''';
      final PinnedComponent widget = parseDeclaration(pinned, where: 'pins.yaml').components.single;
      expect(widget.sha256, digest);
      final List<YamlValueStamp> sites = widget.stamps.cast<YamlValueStamp>();
      expect(sites.map((YamlValueStamp site) => site.writesSha256), <bool>[false, true, false]);
    });

    test('every way of writing it wrong is refused by name, each once, all at once', () {
      // The planted defects, one per component so each refusal is about one thing: a digest cut
      // short, one a digit too long, one in capitals, one carrying the name of its algorithm, an
      // empty one, a digest no stamp writes, a stamp writing a digest its component never
      // declared, a stamp naming a value nothing writes, and a digest site told to cut the digest
      // into segments. Each would put a value into a row that no fetched file can match.
      final String wrong =
          'tools:\n'
          '${writtenAs('short-cli', '"${digest.substring(1)}"')}'
          '${writtenAs('long-cli', '"${digest}0"')}'
          '${writtenAs('loud-cli', '"${digest.toUpperCase()}"')}'
          '${writtenAs('named-cli', '"sha256:$digest"')}'
          '${writtenAs('empty-cli', '')}'
          '''
  unwritten-cli:
    version: "v1.0.0"
    sha256: "$digest"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: version
        anchor: 'tool: unwritten-cli'
  bare-cli:
    version: "v1.0.0"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: sha256
        writes: sha256
  odd-cli:
    version: "v1.0.0"
    sha256: "$digest"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: checksum
        writes: checksum
  cut-cli:
    version: "v1.0.0"
    sha256: "$digest"
    stamps:
      - kind: yaml_value
        tree: alpha
        file: programs/setup.yaml
        key: sha256
        writes: sha256
        segments: 1
''';
      try {
        parseDeclaration(wrong, where: 'pins.yaml');
        fail('a declaration with nine wrong digests parsed');
      } on DeclarationInvalid catch (refused) {
        expect(refused.problems, hasLength(9), reason: refused.toString());
        for (final String name in <String>['short-cli', 'long-cli', 'loud-cli', 'named-cli']) {
          expect(
            refused.problems.where(
              (String each) =>
                  each.contains('"tools/$name"') && each.contains('64 lowercase hexadecimal'),
            ),
            hasLength(1),
            reason: name,
          );
        }
        expect(refused.toString(), contains('"tools/empty-cli" has a sha256 that is not text'));
        expect(
          refused.toString(),
          contains('"tools/unwritten-cli" declares a sha256, and no stamp writes it'),
        );
        expect(refused.toString(), contains('"tools/bare-cli" has a stamp that writes its sha256'));
        expect(refused.toString(), contains('writes "checksum"'));
        expect(refused.toString(), contains('names segments'));
      }
    });
  });

  test('every problem is reported at once, not one per run', () {
    const String twiceWrong = '''
appliances:
  widget:
    version: 1
    stamp: []
  gadget:
    version: "4.5.6"
    stamps:
      - kind: list_pin
        tree: alpha
        file: parts/list.yaml
''';
    try {
      parseDeclaration(twiceWrong, where: 'pins.yaml');
      fail('a declaration with four problems parsed');
    } on DeclarationInvalid catch (refused) {
      expect(refused.problems, hasLength(4));
      expect(refused.toString(), contains('"stamp"'));
      expect(refused.toString(), contains('write it quoted'));
      expect(refused.toString(), contains('"anchor"'));
      expect(refused.toString(), contains('"entry"'));
    }
  });
}
