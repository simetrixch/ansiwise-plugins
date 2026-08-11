import 'package:ansiwise_api/ansiwise_api.dart';

import '../../branch/fqdn_selection.dart';

/// Refuses a run whose domain answer is not a domain, before any machine is asked anything.
///
/// **One answer becomes four things**, and every one of them is written by a different step: the git
/// branch this installation is generated on, the name of its cluster map, the domain in every
/// manifest it deploys, and the host every certificate is issued for. So the question "is this a
/// domain at all" is asked once, here, at the front of the program — a value refused after the
/// branch is cut is a value refused after the run has already changed the checkout, and taking that
/// back is work an operator did not ask for.
///
/// **The grammar is this product's and not git's.** What git will take as a branch name is a far
/// wider set, and `git_branch` asks git itself about that. `m1_test.example.com` passes there and
/// will never resolve anywhere: an underscore is legal in a branch name and illegal in a host name,
/// which is how a typo used to survive as far as the first failed lookup. That difference is the
/// whole reason this step exists beside that one.
///
/// **It only measures.** Nothing about a machine decides its answer — the run's own answer does —
/// so it is the cheapest refusal this program has and it stands first.
final class RequireInstallationDomain extends ObservingStep {
  /// Refuses a run whose domain answer could not name this installation.
  const RequireInstallationDomain();

  /// Builds the step from what the program gave it, which is nothing.
  ///
  /// It declares no argument: what it measures is an ANSWER of the run, and which answer that is, is
  /// this product's own rather than something a row varies.
  factory RequireInstallationDomain.fromArguments(Arguments arguments) =>
      const RequireInstallationDomain();

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// **It is also what keeps the resolver's refusal over this program.** `git_branch` is told by its
  /// row which answer holds the branch name, so its own entry can declare none and a program that
  /// forgot to declare that answer would only be caught on the machine. This entry declares it
  /// statically, so a deploy-branch program without an `fqdn` answer is refused before a run starts.
  static const List<String> answers = <String>['fqdn'];

  /// Whether [value] is a domain name this program will write anywhere.
  ///
  /// The one grammar every domain-shaped value of an installation is measured against — the branch
  /// name here, and the build plane, the unit apex and the platform domain in the cluster map. They
  /// are the same kind of thing, so a second grammar for the others would let one of them accept
  /// what the first refuses.
  ///
  /// Lower case, because these values are written into manifests that compare them literally, and
  /// at least two labels, because a single label is a machine name rather than a domain. An
  /// underscore is refused: it is legal in a git branch name and illegal in a host name.
  static bool isFqdn(String value) => _fqdn.hasMatch(value);

  @override
  Future<CheckResult> check(StepContext context) async {
    // Read here and nowhere else. It is an answer and not an argument — the one value nobody can put
    // in a file that ships to every installation — and every other step that touches it is handed
    // the NAME of this answer by its own row rather than reaching for a reader kept here. So the
    // branch and everything stamped into it are named from one place, and that place is the program
    // file.
    final String fqdn = context.answers.text('fqdn');
    if (fqdn == FqdnSelection.placeholder) {
      return const CheckResult.blocked(
        '"${FqdnSelection.placeholder}" is what the product carries instead of a domain, and an '
        'installation cannot be named after it — give the domain this installation is reached under',
      );
    }
    if (!isFqdn(fqdn)) {
      return CheckResult.blocked(
        '"$fqdn" is not a domain name, and it would become this installation\'s branch name, its '
        'cluster map and every host in its manifests — lower case labels of letters, digits and '
        'dashes, at least two of them',
      );
    }
    return CheckResult.satisfied('this installation is $fqdn');
  }
}

/// Labels of letters, digits and dashes, joined by dots, at least two of them.
final RegExp _fqdn = RegExp(
  r'^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$',
);
