import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_http/ansiwise_http.dart';

/// reversibility — every step of [httpRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
///
/// Two of the steps only measure, so the question does not arise for them. The one that sends a
/// changing request is irreversible on purpose: what the request changed is the other end's own
/// state, and only the interface that was spoken to knows its own inverse — a general
/// take-it-back request does not exist in the protocol, and an undo that pretended one does would
/// claim a capability the code does not have.
void main() => auditReversibility(httpRegistry);
