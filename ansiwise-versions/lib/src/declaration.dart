/// The declaration of what a component is: its pinned version, where the pin is written, and
/// where its upstream lives.
///
/// **One declaration, two readers, and that is the whole reason this grammar exists.** The step
/// that stamps the pins and the step that reports them against upstream both read this one file.
/// The predecessor of this pair had the report parse the stamper's own source to learn where a pin
/// was written; renaming one function there silently turned the report's whole charts section into
/// "stamped nowhere" — the report kept working and stopped being true, which is the worst failure
/// shape there is. Here both sides read the same data, so they cannot disagree about what a
/// component is.
///
/// **The file is the product's, the grammar is this package's.** A declaration file lives in a
/// product tree and names that product's components, files and registries — everything this
/// package may never carry. What this package owns is only the shape: groups, components,
/// versions, stamps and upstreams. That split is what lets a completely different product point
/// the same two steps at a declaration of its own.
///
/// The grammar, in the file's own words:
///
/// ```yaml
/// <group>:                     # any name; it heads a section of the report
///   <component>:               # any name, unique within its group
///     version: "1.2.3"         # the pin — always quoted, so YAML cannot re-read it as a number
///     note: one line the report appends to this component's upstream cell   # optional
///     upstream:                # optional; without it the report answers "?" for this component
///       kind: github_release | docker_hub | oci_tags | chart_repository | helm_index
///             | snap_channel | hashicorp_release
///       ...                    # the fields of that kind, and nothing else
///     stamps:                  # optional; without it nothing writes this pin anywhere
///       - kind: yaml_value | chart_dependency | list_pin | dockerfile_from | dockerfile_arg
///         tree: <name>         # which checkout, by the label a program row maps to a path
///         file: <path>         # inside that tree
///         ...                  # the fields of that kind, and nothing else
/// ```
///
/// A top-level entry that carries `version` directly is a component of its own, outside every
/// group — for the odd fact that fits no section.
///
/// **Everything unknown is refused, and every problem is reported at once.** A loader that ignores
/// what it does not recognise turns a typo into a stamp that silently went missing — `stamp:` for
/// `stamps:` would pin a version nothing ever writes, with no symptom until the drift is found by
/// hand. That is the exact failure the predecessor had, so this parser refuses any key it does not
/// know, anywhere, and collects the whole list before throwing.
library;

import 'package:yaml/yaml.dart';

/// A declaration that could not be read, with everything wrong with it at once.
final class DeclarationInvalid implements Exception {
  /// Refuses a declaration for [problems].
  DeclarationInvalid(this.problems, {required this.where});

  /// One problem per line, in file order.
  final List<String> problems;

  /// The file the declaration came from.
  final String where;

  @override
  String toString() => '$where:\n  ${problems.join('\n  ')}';
}

/// Every component the declaration pins, in file order.
final class VersionsDeclaration {
  /// Holds the parsed components.
  const VersionsDeclaration(this.components);

  /// The components, each carrying its group.
  final List<PinnedComponent> components;

  /// The group names, in the order the file states them, each once.
  List<String> get groups {
    final List<String> seen = <String>[];
    for (final PinnedComponent component in components) {
      if (!seen.contains(component.group)) {
        seen.add(component.group);
      }
    }
    return seen;
  }

  /// The components of [group], in file order.
  List<PinnedComponent> ofGroup(String group) => <PinnedComponent>[
    for (final PinnedComponent component in components)
      if (component.group == group) component,
  ];
}

/// One pinned component: its version, where the pin is written, and where its upstream lives.
final class PinnedComponent {
  /// Declares one component.
  const PinnedComponent({
    required this.group,
    required this.name,
    required this.version,
    this.note,
    this.upstream,
    this.stamps = const <PinStamp>[],
  });

  /// The section this component stands in. A component declared at the top level is its own group.
  final String group;

  /// The name the declaration writes.
  final String name;

  /// The pinned version, exactly as the stamps write it.
  final String version;

  /// One line the report appends beside this component's upstream answer, or null.
  ///
  /// For the pin that is deliberate — held back for a measured reason — so the report says so in
  /// the same row instead of inviting a bump the file's own comments argue against.
  final String? note;

  /// Where the upstream lives, or null when nothing can be asked.
  final Upstream? upstream;

  /// Every place the pin is written. A component with none is carried by nothing and the report
  /// says so.
  final List<PinStamp> stamps;

  /// How refusals name this component.
  String get label => group == name ? name : '$group/$name';
}

/// Where one component's upstream lives, by the kind of source it is.
sealed class Upstream {
  const Upstream();
}

/// The newest release of a project on github.com whose tag matches a pattern.
///
/// For a CLI TOOL this is the right question: the release is what the install fetches. For an
/// IMAGE it is the wrong one — a project can tag a release with no image behind it, and a cluster
/// runs the image — which is why the image kinds below ask the registry instead.
final class GithubRelease extends Upstream {
  /// Asks the release list of [project] for the releases matching [matching].
  const GithubRelease({required this.project, required this.matching});

  /// The `owner/name` of the project.
  final String project;

  /// The anchored expression a release tag must match whole to be a candidate.
  ///
  /// A release list carries every shape a project ever published, and the channel a release was
  /// cut on is usually part of that shape — so this is where a pin says whether it is willing to
  /// be told about a pre-release at all. Without it a release candidate competes with the stable
  /// versions beside it and reads as a version to bump to.
  ///
  /// It has no default, because which channel a pin follows is the product's decision and a
  /// package that guessed it would answer confidently for a question nobody was asked.
  final String matching;
}

/// The newest tag of an image on hub.docker.com that matches a pattern.
final class DockerHubTags extends Upstream {
  /// Asks the tag list of [image] for tags matching [matching].
  const DockerHubTags({required this.image, required this.matching});

  /// The `namespace/name` of the image; official images are under `library/`.
  final String image;

  /// The anchored expression a tag must match whole to be a candidate.
  ///
  /// A tag list carries every shape a project ever published; without the pattern the maximum is
  /// taken over shapes that are not this pin's, and the answer looks newer or older than it is.
  final String matching;
}

/// The newest tag of an image on any registry speaking the distribution protocol.
final class OciTags extends Upstream {
  /// Asks the registry at [host] for the tags of [image] matching [matching].
  const OciTags({required this.host, required this.image, required this.matching});

  /// The registry host.
  final String host;

  /// The image path on that registry.
  final String image;

  /// The anchored expression a tag must match whole to be a candidate.
  final String matching;
}

/// The newest version in the index of the chart repository the STAMPED Chart.yaml itself names.
///
/// Deliberately carrying no address: the repository a dependency comes from is declared in the
/// Chart.yaml this component's `chart_dependency` stamp writes, and it differs per chart in ways
/// that are easy to guess wrong — two repositories of one vendor are not the same repository.
/// Naming it here as well would be the same fact twice, and the two would drift. A component with
/// this upstream and no `chart_dependency` stamp is answered "?" naming the gap.
final class ChartRepository extends Upstream {
  /// Asks the repository the stamped Chart.yaml names.
  const ChartRepository();
}

/// The newest version of a chart in a repository named outright.
///
/// For the chart nothing in any stamped tree declares as a dependency — one a program row installs
/// directly — where there is no Chart.yaml to read the address out of.
final class HelmIndex extends Upstream {
  /// Asks the index of [repository] for [chart].
  const HelmIndex({required this.repository, required this.chart});

  /// The chart repository, as an http(s) address or `oci://host/path`.
  final String repository;

  /// The chart's name in that repository.
  final String chart;
}

/// The newest stable track of a snap in the snap store.
///
/// Answered in the pin's own shape, `<track>/stable`, so the two columns of the report read
/// against each other without translation.
final class SnapChannel extends Upstream {
  /// Asks the store about [snap].
  const SnapChannel({required this.snap});

  /// The snap's name in the store.
  final String snap;
}

/// The latest release of a product on the hashicorp releases feed.
///
/// Its own kind rather than a github release because the feed is what the install fetches from,
/// and the honest question is asked of the source actually served.
final class HashicorpRelease extends Upstream {
  /// Asks the releases feed about [product].
  const HashicorpRelease({required this.product});

  /// The product's name in the feed.
  final String product;
}

/// One place a pin is written: which tree, which file, and how the value is found in it.
sealed class PinStamp {
  const PinStamp({required this.tree, required this.file, this.segments});

  /// The label of the checkout this file lives in. A program row maps every label to a path.
  final String tree;

  /// The file inside that tree.
  final String file;

  /// How many leading dot-separated segments of the version this site carries, or null for all.
  ///
  /// For the site that states a version's series rather than the version — a client that follows
  /// the server's `major.minor`, a major alone — so cutting it HERE is what keeps that site from
  /// restating a version the declaration already decides.
  final int? segments;

  /// The version as this site writes it.
  String valueOf(String version) {
    final int? take = segments;
    if (take == null) {
      return version;
    }
    final List<String> parts = version.split('.');
    return parts.take(take).join('.');
  }

  /// How refusals name this site.
  String get label => '$tree:$file';
}

/// A scalar in a YAML file: the value of `key`, found under an anchor line where one is named.
///
/// The edit is surgical — only the value token changes, quoting, comments and formatting stay —
/// because these files are comment-heavy and a rewrite through a YAML printer reflows them.
final class YamlValueStamp extends PinStamp {
  /// Stamps the value of [key], scoped under [anchor] where one is named.
  const YamlValueStamp({
    required super.tree,
    required super.file,
    required this.key,
    this.anchor,
    super.segments,
  });

  /// The key whose value is the pin.
  final String key;

  /// The exact trimmed line that opens the block the key stands in, or null for a top-level key.
  ///
  /// An anchor must match exactly one line, and the key exactly once under it — a stamp that could
  /// mean two places is refused rather than guessed about.
  final String? anchor;
}

/// The `version:` of one dependency in a Chart.yaml, found by the dependency's name.
///
/// Its own kind rather than a [YamlValueStamp] spelling the anchor by hand, because the report's
/// [ChartRepository] upstream reads the SAME dependency's `repository:` out of the same block —
/// one declared name serves both, so the two cannot drift into naming different dependencies.
final class ChartDependencyStamp extends PinStamp {
  /// Stamps the version of [dependency].
  const ChartDependencyStamp({required super.tree, required super.file, required this.dependency});

  /// The dependency's `name:` in the Chart.yaml.
  final String dependency;
}

/// One `- name=value` entry in a YAML list, found by the entry's name under the list's key line.
///
/// For the row that holds several pins as one list. The anchor is required because two lists in
/// one file may carry the same names for different purposes — the pins and the words each tool is
/// asked its version with are exactly that pair.
final class ListPinStamp extends PinStamp {
  /// Stamps the value of the entry named [entry] in the list under [anchor].
  const ListPinStamp({
    required super.tree,
    required super.file,
    required this.anchor,
    required this.entry,
    super.segments,
  });

  /// The exact trimmed line that opens the list.
  final String anchor;

  /// The name on the left of the `=`.
  final String entry;
}

/// The reference after the colon on the `FROM` line naming one image.
///
/// Matched on the image path so the other FROM lines of a multi-stage file are left alone. The
/// value replaced is everything after the first colon of the token, INCLUDING a digest where the
/// file pins one — stamping a bare tag over a digest would silently undo that pin, so the
/// declaration's version must carry the digest too where one is wanted.
final class DockerfileFromStamp extends PinStamp {
  /// Stamps the reference of the FROM line whose image path contains [image].
  const DockerfileFromStamp({required super.tree, required super.file, required this.image});

  /// The image path the FROM line names, without a tag.
  final String image;
}

/// The default of one `ARG name=value` line.
///
/// Unlike every other site this one is usually in ANOTHER repository: a version this declaration
/// decides but a sibling repository's build has to state as a literal, because a build cannot read
/// a file across a repository boundary and a copy of the declaration there would be a second
/// source. A missing ARG is a refusal, never a skip — a silent miss leaves that image building on
/// whatever it says today, with no diff anywhere.
final class DockerfileArgStamp extends PinStamp {
  /// Stamps the default of the ARG named [argument].
  const DockerfileArgStamp({
    required super.tree,
    required super.file,
    required this.argument,
    super.segments,
  });

  /// The ARG's name.
  final String argument;
}

/// Reads [text] as a declaration, refusing everything wrong with it at once.
VersionsDeclaration parseDeclaration(String text, {required String where}) {
  final Object? root;
  try {
    root = loadYaml(text);
  } on YamlException catch (broken) {
    throw DeclarationInvalid(<String>[broken.message], where: where);
  }
  final List<String> problems = <String>[];
  final List<PinnedComponent> components = <PinnedComponent>[];
  if (root is! YamlMap) {
    throw DeclarationInvalid(<String>[
      'a declaration is a map of groups and components',
    ], where: where);
  }
  for (final MapEntry<Object?, Object?> entry in root.nodes.entries) {
    final Object? name = (entry.key as YamlNode?)?.value;
    final Object? body = entry.value;
    if (name is! String) {
      problems.add('a top-level name is text, and one is ${_kindOf(entry.key)}');
      continue;
    }
    if (body is! YamlMap) {
      problems.add(
        '"$name" is neither a group nor a component — it holds ${_kindOf(body)} instead of a map',
      );
      continue;
    }
    if (body.containsKey('version')) {
      final PinnedComponent? component = _component(name, name, body, problems);
      if (component != null) {
        components.add(component);
      }
      continue;
    }
    for (final MapEntry<Object?, Object?> inner in body.nodes.entries) {
      final Object? innerName = (inner.key as YamlNode?)?.value;
      if (innerName is! String) {
        problems.add('"$name" holds a component whose name is ${_kindOf(inner.key)}');
        continue;
      }
      final Object? innerBody = inner.value;
      if (innerBody is! YamlMap || !innerBody.containsKey('version')) {
        problems.add(
          '"$name/$innerName" declares no "version", and a component is nothing without its pin',
        );
        continue;
      }
      final PinnedComponent? component = _component(name, innerName, innerBody, problems);
      if (component != null) {
        components.add(component);
      }
    }
  }
  if (problems.isNotEmpty) {
    throw DeclarationInvalid(problems, where: where);
  }
  return VersionsDeclaration(components);
}

PinnedComponent? _component(String group, String name, YamlMap body, List<String> problems) {
  final String label = group == name ? name : '$group/$name';
  bool whole = true;
  for (final Object? key in body.keys) {
    if (key is! String || !const <String>{'version', 'note', 'upstream', 'stamps'}.contains(key)) {
      problems.add(
        '"$label" carries "$key", and a component holds version, note, upstream and stamps',
      );
      whole = false;
    }
  }
  final Object? version = body['version'];
  if (version is! String) {
    // The quoting is load-bearing, not pedantry: YAML reads an unquoted 8.8 as a number and an
    // unquoted 26.04 as a number that has lost its trailing zero — and a pin that changed by
    // being read is a pin nothing can stamp faithfully.
    problems.add('"$label" has a version that is not text — write it quoted');
    whole = false;
  }
  final Object? note = body['note'];
  if (note != null && note is! String) {
    problems.add('"$label" has a note that is not text');
    whole = false;
  }
  final Upstream? upstream = switch (body.nodes['upstream']) {
    null => null,
    final YamlNode node => _upstream(label, node, problems),
  };
  if (body.containsKey('upstream') && upstream == null) {
    whole = false;
  }
  final List<PinStamp> stamps = <PinStamp>[];
  final YamlNode? stampsNode = body.nodes['stamps'];
  if (stampsNode != null) {
    if (stampsNode is! YamlList) {
      problems.add('"$label" has stamps that are not a list');
      whole = false;
    } else {
      for (final YamlNode element in stampsNode.nodes) {
        final PinStamp? stamp = _stamp(label, element, problems);
        if (stamp == null) {
          whole = false;
        } else {
          stamps.add(stamp);
        }
      }
    }
  }
  if (!whole) {
    return null;
  }
  return PinnedComponent(
    group: group,
    name: name,
    version: version! as String,
    note: note as String?,
    upstream: upstream,
    stamps: stamps,
  );
}

Upstream? _upstream(String label, YamlNode node, List<String> problems) {
  if (node is! YamlMap) {
    problems.add('"$label" has an upstream that is not a map');
    return null;
  }
  final _Fields fields = _Fields(label, 'upstream', node, problems);
  final String? kind = fields.text('kind');
  if (kind == null) {
    return null;
  }
  final Upstream? upstream = switch (kind) {
    'github_release' => () {
      final String? project = fields.text('project');
      final String? matching = fields.text('matching');
      return project == null || matching == null
          ? null
          : GithubRelease(project: project, matching: matching);
    }(),
    'docker_hub' => () {
      final String? image = fields.text('image');
      final String? matching = fields.text('matching');
      return image == null || matching == null
          ? null
          : DockerHubTags(image: image, matching: matching);
    }(),
    'oci_tags' => () {
      final String? host = fields.text('host');
      final String? image = fields.text('image');
      final String? matching = fields.text('matching');
      return host == null || image == null || matching == null
          ? null
          : OciTags(host: host, image: image, matching: matching);
    }(),
    'chart_repository' => const ChartRepository(),
    'helm_index' => () {
      final String? repository = fields.text('repository');
      final String? chart = fields.text('chart');
      return repository == null || chart == null
          ? null
          : HelmIndex(repository: repository, chart: chart);
    }(),
    'snap_channel' => () {
      final String? snap = fields.text('snap');
      return snap == null ? null : SnapChannel(snap: snap);
    }(),
    'hashicorp_release' => () {
      final String? product = fields.text('product');
      return product == null ? null : HashicorpRelease(product: product);
    }(),
    _ => () {
      problems.add(
        '"$label" has an upstream of kind "$kind", and the kinds are github_release, docker_hub, '
        'oci_tags, chart_repository, helm_index, snap_channel and hashicorp_release',
      );
      return null;
    }(),
  };
  fields.refuseLeftovers();
  return upstream;
}

PinStamp? _stamp(String label, YamlNode node, List<String> problems) {
  if (node is! YamlMap) {
    problems.add('"$label" has a stamp that is not a map');
    return null;
  }
  final _Fields fields = _Fields(label, 'stamp', node, problems);
  final String? kind = fields.text('kind');
  final String? tree = fields.text('tree');
  final String? file = fields.text('file');
  if (kind == null || tree == null || file == null) {
    return null;
  }
  final PinStamp? stamp = switch (kind) {
    'yaml_value' => () {
      final String? key = fields.text('key');
      return key == null
          ? null
          : YamlValueStamp(
              tree: tree,
              file: file,
              key: key,
              anchor: fields.optionalText('anchor'),
              segments: fields.optionalCount('segments'),
            );
    }(),
    'chart_dependency' => () {
      final String? dependency = fields.text('dependency');
      return dependency == null
          ? null
          : ChartDependencyStamp(tree: tree, file: file, dependency: dependency);
    }(),
    'list_pin' => () {
      final String? anchor = fields.text('anchor');
      final String? entry = fields.text('entry');
      return anchor == null || entry == null
          ? null
          : ListPinStamp(
              tree: tree,
              file: file,
              anchor: anchor,
              entry: entry,
              segments: fields.optionalCount('segments'),
            );
    }(),
    'dockerfile_from' => () {
      final String? image = fields.text('image');
      return image == null ? null : DockerfileFromStamp(tree: tree, file: file, image: image);
    }(),
    'dockerfile_arg' => () {
      final String? argument = fields.text('argument');
      return argument == null
          ? null
          : DockerfileArgStamp(
              tree: tree,
              file: file,
              argument: argument,
              segments: fields.optionalCount('segments'),
            );
    }(),
    _ => () {
      problems.add(
        '"$label" has a stamp of kind "$kind", and the kinds are yaml_value, chart_dependency, '
        'list_pin, dockerfile_from and dockerfile_arg',
      );
      return null;
    }(),
  };
  fields.refuseLeftovers();
  return stamp;
}

/// One small map being read field by field, so that whatever was not read is refused by name.
final class _Fields {
  _Fields(this.label, this.what, YamlMap node, this.problems)
    : _held = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in node.nodes.entries)
          if ((entry.key as YamlNode?)?.value case final String name)
            name: (entry.value as YamlNode?)?.value,
      };

  final String label;
  final String what;
  final List<String> problems;
  final Map<String, Object?> _held;
  final Set<String> _read = <String>{};

  String? text(String name) {
    _read.add(name);
    final Object? value = _held[name];
    if (value is String) {
      return value;
    }
    if (_held.containsKey(name)) {
      problems.add('"$label": the $what has a "$name" that is not text');
    } else {
      problems.add('"$label": the $what names no "$name"');
    }
    return null;
  }

  String? optionalText(String name) {
    _read.add(name);
    final Object? value = _held[name];
    if (value == null && !_held.containsKey(name)) {
      return null;
    }
    if (value is String) {
      return value;
    }
    problems.add('"$label": the $what has a "$name" that is not text');
    return null;
  }

  int? optionalCount(String name) {
    _read.add(name);
    final Object? value = _held[name];
    if (value == null && !_held.containsKey(name)) {
      return null;
    }
    if (value is int && value >= 1) {
      return value;
    }
    problems.add('"$label": the $what has a "$name" that is not a count of segments');
    return null;
  }

  void refuseLeftovers() {
    for (final String name in _held.keys) {
      if (!_read.contains(name)) {
        problems.add('"$label" has a $what carrying "$name", which its kind does not take');
      }
    }
  }
}

String _kindOf(Object? node) {
  final Object? value = node is YamlNode ? node.value : node;
  return switch (value) {
    null => 'nothing',
    String() => 'text',
    num() => 'a number',
    bool() => 'true or false',
    _ => value.runtimeType.toString(),
  };
}
