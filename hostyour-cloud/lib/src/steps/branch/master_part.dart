import 'package:ansiwise_api/ansiwise_api.dart';

/// Whether a cluster holds the master part, and which cluster holds it — stated once.
///
/// Two answers state this together. `role` says whether this cluster holds the master part; `master`
/// names the cluster that does, on a cluster that does not. What makes a pair of them legal is a
/// property of the PAIR and of neither answer alone: a cluster that does not hold the master part
/// has to name one, and a cluster that holds it cannot also name another. Neither declaration can
/// express that on its own, because a declaration is about one answer.
///
/// **It was written out twice and the two copies said different things.** The step that writes the
/// map refused both halves. The step that writes the profile refused only the missing name, so a
/// cluster that held the master part and ALSO named another one had that name silently dropped from
/// the profile. Both run in the same program against the same answers, so the stricter one went on
/// catching the pair — which is what latent harm looks like, and it ends at the first reordering or
/// at the next person tightening one list and not the other.
///
/// WHY A CLASS OF ITS OWN AND NOT A METHOD OF A STEP. Three callers need this answer for three
/// reasons: the gate at the head of the program refuses a contradictory pair before anything runs,
/// the map writes the name where one is held, and the profile hangs every service provided once per
/// installation off the cluster that holds the master part. A rule each of them states for itself is
/// a rule each of them can state differently, and the second one is written by somebody who did not
/// know about the first. There is nothing to compare now, because there is nothing stated twice.
///
/// NO PORTS AND NO CONTEXT. It takes the answers and nothing else, so a test can drive every pair
/// directly and a step asking it costs no reading of anything.
final class MasterPart {
  /// The pair exactly as this run answered it.
  const MasterPart({required this.role, required this.named});

  /// Reads the pair out of the answers a run holds.
  factory MasterPart.of(Arguments given) =>
      MasterPart(role: given.text(roleAnswer), named: _stated(given, masterAnswer));

  /// The answer saying whether this cluster holds the master part.
  static const String roleAnswer = 'role';

  /// The answer naming the cluster that holds it, where this one does not.
  static const String masterAnswer = 'master';

  /// The role of a cluster that holds the master part itself.
  static const String holdsIt = 'master';

  /// The role of a cluster that belongs to one holding it.
  static const String belongsToAnother = 'slave';

  /// The two roles a cluster may state, in the order a message lists them.
  static const List<String> roles = <String>[holdsIt, belongsToAnother];

  /// The answers this rule reads, which is what the registry entry of every step asking it declares.
  static const List<String> answers = <String>[roleAnswer, masterAnswer];

  /// What this cluster answered for its role.
  final String role;

  /// The cluster this run named as holding the master part, or null where it named none.
  final String? named;

  /// Whether this cluster holds the master part itself.
  bool get holdsMaster => role == holdsIt;

  /// Everything wrong about the pair, both halves, all of it at once.
  ///
  /// An operator correcting one refusal per run is an operator running it twice, and the two halves
  /// are corrected in the same place — the pair of answers this run was started with.
  List<String> get problems => <String>[
    if (role == belongsToAnother && named == null)
      'this cluster does not hold the master part and names no cluster that does, so there is '
          'nowhere for its books, its Vault or its tailnet to be',
    if (named case final String other when holdsMaster)
      'this cluster holds the master part itself, so it cannot also name another one, and "$other" '
          'would reach nothing that reads it',
  ];

  /// The cluster holding the master part, for an installation whose own domain is [fqdn].
  ///
  /// On a cluster that holds it, that is this cluster; on one that does not, the name this run gave.
  /// Everything provided ONCE per installation — the books, the secret store, the tailnet
  /// coordinator, the central observability — hangs off this one value.
  ///
  /// Throws where the pair names none, which is the state [problems] refuses. The alternative is a
  /// value standing in for it, and a profile carrying an empty address is read downstream as an
  /// address that resolves to nothing rather than as the missing answer it is.
  String holderFor(String fqdn) {
    if (holdsMaster) {
      return fqdn;
    }
    if (named case final String other) {
      return other;
    }
    throw StateError(
      'this run names no cluster holding the master part, and the pair of answers that says so is '
      'refused before any step reads it',
    );
  }

  /// The answer named [name], or null where it was left blank.
  ///
  /// An answer left empty and an answer nobody gave are the same thing here. The client renders an
  /// optional field as an empty box, and an operator who tabbed past it sends the empty string —
  /// which as a value would name a cluster called nothing.
  static String? _stated(Arguments given, String name) {
    final String? value = given.optionalText(name);
    return value == null || value.isEmpty ? null : value;
  }
}
