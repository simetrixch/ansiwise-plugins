import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

/// How every command line that reaches the cluster is put together.
///
/// One caller for all of them, so how the client is invoked is answered once rather than differently
/// in different files.
void main() {
  group('a client that answers nobody but root', () {
    // The case that made this necessary rather than convenient. A client wrapped by a distribution
    // usually keeps its configuration where only root may read it — and it refuses everyone else on
    // its OUTPUT while exiting ZERO. So a step reading the answer sees an answer, and the failure
    // arrives as whatever that step concluded from it. Measured on a machine as "the pods on this
    // cluster could not be counted", three steps away from the reason.
    const Kubectl asRoot = Kubectl(<String>['wrapped', 'kubectl'], true);
    const Kubectl asMe = Kubectl(<String>['wrapped', 'kubectl']);

    test('a changing command is run as root', () {
      expect(asRoot.command(<String>['apply', '-f', '-']).elevated, isTrue);
    });

    test('AND SO IS A READING ONE, which is the half that is easy to forget', () {
      // Running as root does not make a reading command change anything: it makes it able to reach
      // the cluster at all. So an observing call stays observing and a dry run still performs it.
      expect(asRoot.observing(<String>['get', 'pods']).elevated, isTrue);
      expect(asRoot.observing(<String>['get', 'pods']).observes, isTrue);
    });

    test('THE INNOCENT NEIGHBOUR: a client that needs nothing is not elevated', () {
      // Without this, elevating unconditionally would pass both assertions above while running every
      // cluster call of every installation as root, including those that never needed it.
      expect(asMe.command(<String>['apply']).elevated, isFalse);
      expect(asMe.observing(<String>['get']).elevated, isFalse);
    });

    test('the words of the invocation are untouched by it', () {
      expect(asRoot.argv(<String>['get', 'pods']), <String>['wrapped', 'kubectl', 'get', 'pods']);
    });
  });

  group('what the row says', () {
    test('absent means not elevated, which is what a plain client needs', () {
      expect(
        Kubectl.fromArguments(
          const Arguments(<String, Object>{
            'kubectl': <String>['kubectl'],
          }),
        ).elevated,
        isFalse,
      );
    });

    test('and a row that says so gets a client that runs as root', () {
      expect(
        Kubectl.fromArguments(
          const Arguments(<String, Object>{
            'kubectl': <String>['wrapped', 'kubectl'],
            'kubectl_needs_root': true,
          }),
        ).elevated,
        isTrue,
      );
    });
  });
}
