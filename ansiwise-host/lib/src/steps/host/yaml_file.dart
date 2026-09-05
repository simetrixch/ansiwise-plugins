import 'package:yaml/yaml.dart';

/// The node a parsed YAML document carries under a dotted path, or null where it carries none.
///
/// ONE reader for the whole package, beside `KeyValueFile` which does the same job for the other
/// file grammar this package reads. A dotted path is how a caller addresses a nested key without
/// this reader knowing anything about the shape of the file: `certificates.issuer.name` is three
/// map lookups, and which three is the caller's business.
///
/// **A MISSING PATH AND A PATH THAT LEAVES THE MAPS ARE THE SAME ANSWER HERE.** Both are null, and
/// the caller says what that costs: a step that has a fallback treats it as "not written down", and
/// a condition refuses. Telling them apart in this function would put a second vocabulary in front
/// of every caller for a distinction only one of them can act on.
///
/// The node is returned rather than its value, because a caller that has to tell a scalar from a
/// list needs the node to do it.
YamlNode? yamlNodeAt(YamlNode document, String path) {
  YamlNode? at = document;
  for (final String name in path.split('.')) {
    if (at case final YamlMap map) {
      at = map.nodes[name];
      continue;
    }
    return null;
  }
  return at;
}
