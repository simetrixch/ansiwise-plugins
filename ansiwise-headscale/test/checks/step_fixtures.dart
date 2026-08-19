/// A fake coordinator arranged for the one step here, so its second run can be measured at all.
///
/// The idempotence audit runs every registered step twice against a fake machine. On a BLANK fake
/// this step is blocked before it starts: a coordinator that answers its user listing with nothing
/// is a coordinator that cannot be asked, and the step refuses to mint on silence — which is the
/// step working, not the audit measuring it. What is here closes that: the fake coordinator answers
/// its listings, and the create flips the key listing to redeemable exactly the way a real
/// coordinator's state does, which is what lets the second run find the credential standing.
library;

import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_core/testing.dart';

/// The user the probe's planted answer names: the audit hands every text answer its one-character
/// value, read from the package that hands it over rather than restated, so the fixture and the
/// prober cannot disagree about it.
const String _machine = plausibleText;

/// The fake machine each named step meets, by the name a program file writes.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  // The coordinator holds the user and no redeemable key until the create, after which its key
  // listing carries one — the state change the real coordinator makes, without which the second
  // run could never find the credential standing.
  'tailnet_join_credential': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers('headscale users list -o json', '[{"name":"$_machine","id":1}]');
    shell.answers('headscale preauthkeys list --user 1 -o json', 'null');
    shell.answers(
      'headscale preauthkeys create --user 1 --expiration 24h -o json',
      '{"key":"k-redeemable"}',
    );
    shell.changes('headscale preauthkeys create --user 1 --expiration 24h -o json', () {
      shell.answers(
        'headscale preauthkeys list --user 1 -o json',
        '[{"key":"k-redeemable","used":false}]',
      );
    });
  },

  // The coordinator holds the user and one node until the destroy, after which its user listing no
  // longer carries it — the state change a real coordinator makes, without which the second run
  // could never find the membership gone.
  'remove_tailnet_user': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell.answers('headscale users list -o json', '[{"name":"$_machine","id":1}]');
    shell.answers('headscale nodes list --user 1 -o json', '[{"id":9,"name":"$_machine"}]');
    shell.changes('headscale nodes delete --identifier 9 --force', () {
      shell.answers('headscale nodes list --user 1 -o json', 'null');
    });
    shell.changes('headscale users destroy --identifier 1 --force', () {
      shell.answers('headscale users list -o json', '[]');
    });
  },
};
