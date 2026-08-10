/// A value for every answer the steps of this plugin read out of a run.
///
/// A step reads an answer BY NAME, and the KIND of that value is declared by the program file of the
/// product that runs the step — never by the step and never by this package, which ships no program
/// file at all. So an audit here cannot read the kinds the way the product's audits read them out of
/// its `programs/` directory; what it can read is the NAMES, because every entry of the registry
/// declares which answers its step reaches for. No step of this package declares one today, and
/// this is what answers for the first that does.
///
/// Each of those names is given a text value. That is a statement about this package rather than a
/// guess: every answer read anywhere in it is read with `Arguments.text`. A step that one day reads
/// one as a number gets an `ArgumentError` from the accessor, and the audit driving it reports that
/// step instead of passing over it — so the assumption cannot fail silently.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

/// A value for every answer any step of [registry] declares.
Arguments answersDeclaredBy(Registry registry) {
  final Set<String> names = <String>{
    for (final RegisteredStep entry in registry.steps.values) ...entry.answers,
  };
  return plausibleArguments(<ArgumentSpec>[
    for (final String name in names)
      ArgumentSpec(
        name: name,
        kind: ArgumentKind.text,
        describes: 'a value an audit hands the step in place of the run it is not part of',
      ),
  ]);
}
