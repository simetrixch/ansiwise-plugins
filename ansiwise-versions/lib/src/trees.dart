/// How a program row maps the tree labels a declaration writes to the checkouts of one machine.
///
/// A declaration names its trees by LABEL — this product's own tree, the sibling repository whose
/// build states a version this declaration decides — because where those checkouts stand is a
/// fact of one machine and of nothing else. The row maps each label either to a PATH, where an
/// installation keeps the checkout in one known place, or to the NAME of an answer, where the
/// place is the operator's to say per run. The reading happens in the step, the same shape every
/// answer-reading row in this system has.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// One tree label's binding: a path outright, or the name of the answer that holds it.
final class TreeBinding {
  /// Binds a label to [path] or to the answer named [answer].
  const TreeBinding({this.answer, this.path});

  /// The name of the answer holding the checkout's path, or null.
  final String? answer;

  /// The checkout's path, or null.
  final String? path;

  /// The bindings a row declares, refusing anything that is not one.
  static Map<String, TreeBinding> readFrom(Object? declared) {
    if (declared is! Map<String, Object?>) {
      throw ArgumentError.value(
        declared,
        'trees',
        'is a mapping of tree label to {answer: name} or {path: /where/it/stands}',
      );
    }
    return <String, TreeBinding>{
      for (final MapEntry<String, Object?> each in declared.entries) each.key: _one(each),
    };
  }

  static TreeBinding _one(MapEntry<String, Object?> entry) {
    final Object? body = entry.value;
    if (body is! Map<String, Object?>) {
      throw ArgumentError.value(
        body,
        entry.key,
        'names where the checkout stands, as {answer: name} or {path: /where/it/stands}',
      );
    }
    final Object? answer = body['answer'];
    final Object? path = body['path'];
    final bool oneOfTwo = (answer is String) != (path is String);
    if (!oneOfTwo || body.length != 1) {
      throw ArgumentError.value(
        body,
        entry.key,
        'holds exactly one of {answer: name} and {path: /where/it/stands}',
      );
    }
    return TreeBinding(answer: answer as String?, path: path as String?);
  }
}

/// The checkouts this run reaches each label at, or every reason it cannot.
///
/// All problems at once, because a mapping refused one absent answer per run is a mapping fixed
/// in three runs.
({Map<String, String>? roots, List<String> problems}) resolveTrees(
  Map<String, TreeBinding> trees,
  Arguments answers,
) {
  final Map<String, String> roots = <String, String>{};
  final List<String> problems = <String>[];
  for (final MapEntry<String, TreeBinding> each in trees.entries) {
    final TreeBinding binding = each.value;
    final String? path = binding.path ?? answers.optionalText(binding.answer!);
    if (path == null || path.isEmpty) {
      problems.add(
        'this run holds no answer called "${binding.answer}", and that is where the row says the '
        'checkout of tree "${each.key}" stands',
      );
      continue;
    }
    roots[each.key] = path;
  }
  return problems.isEmpty
      ? (roots: roots, problems: const <String>[])
      : (roots: null, problems: problems);
}

/// [file] under the checkout root [root], with one separator between them whatever [root] ends in.
String underTree(String root, String file) {
  String trimmed = root;
  while (trimmed.endsWith('/') || trimmed.endsWith('\\')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return '$trimmed/$file';
}
