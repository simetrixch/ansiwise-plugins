import 'package:ansiwise_api/ansiwise_api.dart';
import 'stage_config.dart';

/// Whether the build plane runs on this cluster, or on another one.
///
/// One installation has exactly one build plane, and the cluster it runs on is the one whose own
/// domain is the build plane's. Two policies and one auth role exist only there, and each of them
/// grants something that would be wrong anywhere else: a credential for the two platform
/// repositories a release bump pushes to, and read access to a build unit's own credential — some
/// build units belong to external parties.
///
/// **A build is stage-free, so the tier it reads cannot be made per-stage.** The one build plane
/// sits on a cluster of a single stage and can authenticate only against its local secret store, so
/// a per-stage form of these grants leaves every unit of every other stage with no credential at
/// all. That is why this is a condition about the cluster rather than a value in a program file.
///
/// **Both answers are named conditions, and neither is the other one negated in a program file.**
/// Two grants of the platform are written whole and differ between the two kinds of cluster — the
/// cluster manager's own policy carries a write on the build tier here and must not carry one
/// elsewhere. A file that could say "not" could also say "or", and then what is being read is an
/// expression rather than a list of steps.
final class BuildPlane implements Predicate {
  /// Answers whether the build plane runs here, when [here] — or elsewhere, when it does not.
  const BuildPlane({required this.here});

  /// The variable the stage config names the build plane's domain in.
  static const String buildPlaneKey = 'BUILD_PLANE_FQDN';

  /// The variable the stage config names this cluster's own domain in.
  static const String domainKey = 'DOMAIN_SUFFIX';

  /// Which of the two clusters this condition holds on.
  final bool here;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final StageConfig config = await readStageConfig(context);
    if (config.refusal case final String refusal) {
      return PredicateResult.doesNotHold(
        'which cluster the build plane runs on is unknown: $refusal',
      );
    }

    final String? buildPlane = config.values[buildPlaneKey];
    final String? domain = config.values[domainKey];
    if (buildPlane == null || domain == null) {
      return PredicateResult.doesNotHold(
        '${config.path} does not set both $buildPlaneKey and $domainKey, and which cluster the '
        'build plane runs on is the comparison of those two',
      );
    }

    final bool isHere = buildPlane == domain;
    final String found = isHere
        ? '${config.path} names $buildPlane as the build plane and as this cluster, so the build '
              'tier lives here'
        : '${config.path} names $buildPlane as the build plane and $domain as this cluster, so the '
              'build tier lives on the other one';
    return isHere == here ? PredicateResult.holds(found) : PredicateResult.doesNotHold(found);
  }
}
