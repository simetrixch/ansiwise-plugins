import 'package:ansiwise_api/ansiwise_api.dart';
import 'stage_config.dart';

/// Whether one part of the platform is switched on for this installation.
///
/// **A condition and not a step, because what an operator has to see is the skipping.** A phase that
/// is switched off must leave nothing behind — no namespace, no release, no credential file, not a
/// half-built one — and the way to be sure of that is to have the steps never run rather than to
/// have each of them decide for itself and report success without doing anything. Those two look
/// identical in a record. A condition puts the answer in the plan before the first step runs, beside
/// the name of the condition that skipped each row.
///
/// **The default is what the stage config leaves unsaid, and the two toggles differ.** Vault has to
/// be asked for: a cluster whose config says nothing about it gets none, because bringing up the
/// platform's only secret store on a machine nobody asked to hold one is not a default anybody
/// chose. The identity provider is the other way round — an installation that says nothing gets one,
/// and a cluster without it stands and simply cannot log anybody in yet.
///
/// **UNSAID MEANS ABSENT OR EMPTY, and the second half is the one that was got wrong.** The stage
/// config is not written by hand: it is a template filled in place, and a template stands with every
/// key at a placeholder. So `ENABLE_IDP=` is what a machine holds until somebody answers it, and
/// reading that as a stated "no" turns the default above upside down — the installation that said
/// nothing gets nothing, which is the opposite of what it is promised. The writer of that same file
/// already reads it this way: to it, empty and absent and still-the-template are one state.
final class StageToggle implements Predicate {
  /// Reads [key] from the stage config, treating an unset value as [whenUnset].
  const StageToggle({required this.key, required this.part, required this.whenUnset});

  /// The variable the stage config writes.
  final String key;

  /// What is switched, in the words the plan reads.
  final String part;

  /// What an installation that says nothing about [key] gets.
  final bool whenUnset;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final StageConfig config = await readStageConfig(context);
    if (config.refusal case final String refusal) {
      return PredicateResult.doesNotHold('$part is not deployed: $refusal');
    }

    final String? written = config.values[key];
    if (written == null || written.isEmpty) {
      final String how = written == null
          ? 'does not name $key'
          : 'leaves $key empty, which is where a filled template stands until somebody answers it';
      return whenUnset
          ? PredicateResult.holds(
              '${config.path} $how, and $part is deployed unless an installation says otherwise',
            )
          : PredicateResult.doesNotHold(
              '${config.path} $how, and $part is deployed only where an installation asks for it',
            );
    }

    // Compared against the one value and not against a list of things that read as yes. A config
    // that says `1`, `yes` or `True` says something this installation never defined, and reading it
    // as agreement is how a cluster ends up running a component nobody switched on.
    return written == 'true'
        ? PredicateResult.holds('${config.path} sets $key to "true", so $part is deployed')
        : PredicateResult.doesNotHold(
            '${config.path} sets $key to "$written" rather than "true", so $part is not deployed '
            'and nothing belonging to it runs',
          );
  }
}
