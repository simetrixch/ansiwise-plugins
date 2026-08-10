import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The values that used to be decided here and are now stated by whoever runs the steps.
///
/// Each of these stood in this package as a `defaultValue` — a file name, a routing table, a packet
/// mark, a rule number, the shape a release tag is written with, the command a cluster hands its
/// credentials over with. Every one of them is a value another vendor, on another machine, would
/// want different, and a default made this package decide it for them.
///
/// **A demotion nothing measures is a demotion that comes back.** A default is one line, and the
/// next person adding it back would break nothing anybody would notice: every row that already
/// states the value goes on working, and only the row that forgot it silently picks up somebody
/// else's number. So the property is asserted directly — the argument is DECLARED, it is REQUIRED,
/// and it carries NO default — and then the refusal itself is driven, so what is proven is that a
/// row leaving the value out is stopped before anything runs rather than that a field has a
/// particular shape.
void main() {
  /// Which arguments of which step carry no answer of this package's own.
  ///
  /// Read against the registry rather than against the classes, because the registry is what a
  /// program file reaches: a step whose declaration stops matching this is a step whose rows would
  /// resolve with a value nobody wrote.
  const Map<String, List<String>> demoted = <String, List<String>>{
    'activate_public_src_routing': <String>['mark', 'table'],
    'apply_netplan': <String>['table'],
    'assert_cli_tool_versions': <String>['pin_prefixes'],
    'assert_netplan_merged': <String>['installer_key', 'drop_in_key'],
    'export_kubeconfig': <String>['credentials_command'],
    'install_pinned_tool': <String>['pin_prefixes'],
    'write_connmark_nft_table': <String>['mark'],
    'write_netplan_public_src_routing': <String>['path', 'table'],
    'write_public_src_routing_script': <String>['mark', 'table', 'priority'],
    'write_public_src_routing_unit': <String>['mark', 'table', 'priority'],
  };

  /// The registry entry for [step], or a failure naming it.
  ///
  /// A name nothing is registered under FAILS here rather than being passed over: a table of steps
  /// that quietly stopped matching the registry is a table that measures nothing.
  RegisteredStep entryFor(String step) {
    final RegisteredStep? entry = hostRegistry.step(StepName(step));
    if (entry == null) {
      throw StateError('$step is not registered, so nothing here measures anything about it');
    }
    return entry;
  }

  ArgumentSpec specOf(String step, String argument) {
    final Iterable<ArgumentSpec> found = entryFor(
      step,
    ).arguments.where((ArgumentSpec spec) => spec.name == argument);
    expect(found, hasLength(1), reason: '$step declares no argument called $argument');
    return found.first;
  }

  for (final MapEntry<String, List<String>> step in demoted.entries) {
    for (final String argument in step.value) {
      test('${step.key} takes "$argument" from the row and has no answer of its own', () {
        final ArgumentSpec spec = specOf(step.key, argument);
        expect(
          spec.required,
          isTrue,
          reason: 'an optional value with nothing behind it is a value the step reads as absent',
        );
        expect(
          spec.hasDefault,
          isFalse,
          reason:
              'a default here is this package deciding for a product it must not know — the value '
              'belongs in the row that runs the step',
        );
      });

      test('${step.key} is refused when a row leaves "$argument" out', () {
        // The refusal the framework performs before the first step runs, driven here against this
        // step's own declaration. Every other argument is filled, so what is reported is this one
        // and nothing else.
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

  group('the one demotion that is not required', () {
    // `provided_by` names the commands whose package is called something else, and a machine where
    // none of them is missing needs no entry at all. Its default is the EMPTY list, which is not a
    // product's choice but the neutral truth: every missing command is reported under its own name.
    test('require_commands pairs nothing until a row says so', () {
      final ArgumentSpec spec = specOf('require_commands', 'provided_by');
      expect(spec.required, isFalse);
      expect(spec.defaultValue, isEmpty);
    });
  });
}
