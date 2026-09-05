import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

/// The values this package does not decide, and that whoever runs the steps states instead.
///
/// Each is a fact about how ONE installation put its cluster together: the file a rendered issuer
/// stands in, the namespace a certificate service was installed into, the names its release gave
/// the deployments, and what the issuer itself is called and asks. None of them is mandated by
/// cert-manager, so a value here agrees with the cluster in front of it only for as long as nobody
/// names a release differently.
///
/// **A demotion nothing measures is a demotion that comes back.** A default is one line, and adding
/// it back breaks nothing anybody would notice: every row that already states the value goes on
/// working, and only the row that forgot it silently picks up somebody else's arrangement. So the
/// property is asserted directly — DECLARED, REQUIRED, no default — and then the refusal itself is
/// driven, so what is proven is that a row leaving the value out is stopped before anything runs.
void main() {
  const Map<String, List<String>> demoted = <String, List<String>>{
    'apply_cluster_issuer': <String>['issuer_manifest_path'],
    'restart_cert_manager_and_reapply_cluster_issuer': <String>[
      'issuer_manifest_path',
      'namespace',
      'deployments',
    ],
    // What the issuer is called, which ingress answers the challenge, and where the rendered file
    // goes. cert-manager mandates none of the three: each is one product's choice, and a value here
    // makes this package make that choice for every caller.
    //
    // The authority and the mailbox are not in this list, because each of them has TWO sources and
    // a row states one of the two: an answer, or a key of a settings file. Neither source can be
    // required on its own without forbidding the other. What holds them is the group below.
    'write_cluster_issuer_manifest': <String>['name', 'ingress_class', 'issuer_manifest_path'],
  };

  /// The values with two sources, and the argument that carries each.
  const Map<String, List<String>> twoSourced = <String, List<String>>{
    'write_cluster_issuer_manifest': <String>[
      'acme_server_answer',
      'acme_server_key',
      'email_answer',
      'email_key',
    ],
  };

  /// The registry entry for [step], or a failure naming it.
  ///
  /// A name nothing is registered under FAILS here rather than being passed over: a table of steps
  /// that quietly stopped matching the registry is a table that measures nothing.
  RegisteredStep entryFor(String step) {
    final RegisteredStep? entry = kubernetesRegistry.step(StepName(step));
    if (entry == null) {
      throw StateError('$step is not registered, so nothing here measures anything about it');
    }
    return entry;
  }

  for (final MapEntry<String, List<String>> step in demoted.entries) {
    for (final String argument in step.value) {
      test('${step.key} takes "$argument" from the row and has no answer of its own', () {
        final Iterable<ArgumentSpec> found = entryFor(
          step.key,
        ).arguments.where((ArgumentSpec spec) => spec.name == argument);
        expect(found, hasLength(1), reason: '${step.key} declares no argument called $argument');
        expect(
          found.first.required,
          isTrue,
          reason: 'an optional value with nothing behind it is a value the step reads as absent',
        );
        expect(
          found.first.hasDefault,
          isFalse,
          reason:
              'a default here is this package deciding how a cluster was put together, which is '
              'exactly what it is not allowed to know',
        );
      });

      test('${step.key} is refused when a row leaves "$argument" out', () {
        // The refusal the framework performs before the first step runs, driven here against this
        // step's own declaration. Every other argument is filled, so what is reported is this one.
        final RegisteredStep entry = entryFor(step.key);
        final Arguments filled = plausibleArguments(entry.arguments);
        final Arguments without = Arguments(<String, Object>{
          for (final String name in filled.names)
            if (name != argument)
              if (filled.raw(name) case final Object value) name: value,
        });
        expect(
          argumentProblems(
            where: step.key,
            given: without,
            declared: entry.arguments,
            noun: 'argument',
          ),
          <Matcher>[contains('needs the argument "$argument"')],
        );
      });
    }
  }

  for (final MapEntry<String, List<String>> step in twoSourced.entries) {
    for (final String argument in step.value) {
      test('${step.key} declares "$argument" optional and with no default', () {
        // OPTIONAL BECAUSE THERE ARE TWO OF THEM, never because the value may be left out. A row
        // that states neither source is refused when the step is asked, by a sentence naming the
        // value — which the group below drives.
        final Iterable<ArgumentSpec> found = entryFor(
          step.key,
        ).arguments.where((ArgumentSpec spec) => spec.name == argument);
        expect(found, hasLength(1), reason: '${step.key} declares no argument called $argument');
        expect(found.first.required, isFalse);
        expect(
          found.first.hasDefault,
          isFalse,
          reason:
              'a default here is this package deciding how a cluster was put together, which is '
              'exactly what it is not allowed to know',
        );
      });
    }
  }

  test('a row that states every one of them is refused for nothing', () {
    // The other half: without it, a check that reported a problem about every step would pass the
    // refusals above while saying nothing about the one value each of them is meant to be about.
    for (final String step in demoted.keys) {
      final RegisteredStep entry = entryFor(step);
      expect(
        argumentProblems(
          where: step,
          given: plausibleArguments(entry.arguments),
          declared: entry.arguments,
          noun: 'argument',
        ),
        isEmpty,
        reason: '$step refuses a row that fills everything it declares',
      );
    }
  });

  test('every step that touches the issuer takes the same file, under the same name', () {
    // The whole point of the demotion: one name, so a program states the path once and the step
    // that renders it, the step that applies it and the step that applies it again cannot come to
    // mean three different files.
    for (final String step in demoted.keys) {
      expect(
        entryFor(step).arguments.where((ArgumentSpec spec) => spec.name == 'state_directory'),
        isEmpty,
        reason:
            '$step composing a path out of a directory would put the base name back in this '
            'package, where cert-manager mandates none',
      );
    }
  });
}
