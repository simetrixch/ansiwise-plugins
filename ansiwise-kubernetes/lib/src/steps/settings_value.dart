/// Where one value a row needs comes from: an answer this run holds, or a key of a settings file.
///
/// **Two sources, one per value, and the row says which.** A caller that HOLDS the value states it
/// as an answer, the way every row of this package states one today. A value that already stands
/// written in a settings file on the machine is read there instead, and then no caller can copy it
/// wrongly: there is only one place it is written, and the row names that place.
///
/// **WHERE A ROW NAMES BOTH, THE ANSWER WINS AND THE RECORD SAYS SO.** That is the same precedence
/// `fill_key_value_file` already applies to the same question — what this run was told beats what a
/// file records — so one rule covers both places. It is a precedence and not a refusal because
/// every registry check of this repository builds each step with EVERY argument it declares set at
/// once: a step that refused two sources together could not be built by any of them, and the
/// package would go red on a row nobody wrote. The step writes a line naming the key it did not
/// read, so a row carrying a stale answer beside a live key is visible in the record rather than
/// silent.
///
/// **The file is read as YAML and the key is a dotted path**, each segment one map lookup. There is
/// no index, no wildcard and no expression: a name standing for exactly one value is a mechanism,
/// and anything more is a language a program file may not become.
///
/// **Nothing here is answered with silence.** A row naming no source at all, a path still carrying
/// an unfilled slot, a missing file, a file that is not YAML, a key the file does not carry, a key
/// holding a list or a map, and a key holding nothing are seven refusals, each naming what it read.
/// An empty value handed on instead would compose an address out of a host that is not there, and
/// the row would report itself green.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:yaml/yaml.dart';

/// One value of one step, and where the row said it comes from.
final class SettingsValue {
  /// Takes [what] from [answer], or from [key] of the file at [settingsPath].
  ///
  /// [what] is how the value is named in every refusal, in the words the operator reading it uses.
  /// [runAnswer] is the answer whose value fills the slot spelled with that name in [settingsPath].
  const SettingsValue({
    required this.what,
    required this.answer,
    required this.key,
    required this.settingsPath,
    required this.runAnswer,
  });

  /// How this value is named in a refusal.
  final String what;

  /// The name of the answer holding it, or null where a settings file carries it.
  final String? answer;

  /// The dotted key of the settings file holding it, or null where an answer does.
  final String? key;

  /// Where that settings file stands, or null where an answer carries the value.
  final String? settingsPath;

  /// Which answer fills the slot in [settingsPath], or null where the path carries none.
  final String? runAnswer;

  /// The value this run holds for it, or the sentence that refuses the row.
  Future<({String? value, String? refusal})> valueIn(StepContext context) async {
    if (answer case final String name) {
      if (key case final String ignored) {
        context.log.warn(
          'this row names both an answer and a key for $what: "$name" is read and "$ignored" is '
          'not. Take one of the two out of the row',
        );
      }
      if (!context.answers.has(name)) {
        return (
          value: null,
          refusal:
              'this run holds no answer called "$name", and it is $what — the program has to '
              'declare an answer of that name for the operator to be asked for one',
        );
      }
      final String held = context.answers.text(name);
      return held.isEmpty
          ? (value: null, refusal: '"$name" was answered with nothing, and it is $what')
          : (value: held, refusal: null);
    }
    if (key == null) {
      return (
        value: null,
        refusal:
            'this row names neither an answer nor a key of a settings file for $what, so nothing '
            'says where its value comes from',
      );
    }
    if (settingsPath == null) {
      return (
        value: null,
        refusal:
            'this row names the key "$key" for $what and no settings file, so nothing says which '
            'file that key stands in — write "settings_path" beside it',
      );
    }
    return _readIn(context);
  }

  /// The value the settings file records under [key], or the sentence that refuses the row.
  Future<({String? value, String? refusal})> _readIn(StepContext context) async {
    final String path = filledSlots(settingsPath!, <String, String>{
      if (runAnswer case final String name)
        if (context.answers.optionalText(name) case final String held) name: held,
    });
    if (leftoverSlotIn(path) case final String slot) {
      return (
        value: null,
        refusal:
            '"$settingsPath" still carries $slot after this run filled what it could, so it names '
            'no file — "run_answer" says which answer fills it',
      );
    }
    if (!await context.files.exists(path)) {
      return (
        value: null,
        refusal: '$path is not on this machine, and its $key is where $what stands',
      );
    }
    final YamlNode document;
    try {
      document = loadYamlNode(await context.files.read(path));
    } on YamlException catch (broken) {
      return (
        value: null,
        refusal:
            '$path is not readable as YAML, and its $key is where $what stands — repair the file: '
            '$broken',
      );
    }
    YamlNode? at = document;
    for (final String segment in key!.split('.')) {
      if (at case final YamlMap map) {
        at = map.nodes[segment];
        continue;
      }
      at = null;
      break;
    }
    if (at == null) {
      return (
        value: null,
        refusal: '$path carries nothing under $key, and that is where $what stands',
      );
    }
    if (at.value is List || at.value is Map) {
      return (
        value: null,
        refusal: '$path carries a list or a map under $key, and $what is one value',
      );
    }
    final String held = at.value == null ? '' : '${at.value}'.trim();
    return held.isEmpty
        ? (
            value: null,
            refusal: '$path assigns $key nothing at all, and that is where $what stands',
          )
        : (value: held, refusal: null);
  }
}
