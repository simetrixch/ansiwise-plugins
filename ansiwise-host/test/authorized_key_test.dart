import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The pair that turns a machine reached with a password into one reached with a key: the step that
/// installs the key, and the gate that proves the login it makes possible.
void main() {
  test('the gate proves the key that was installed, not a second one', () {
    // A second pair of names would let the gate pass on a key nobody installed: it would read an
    // account and a key the run never wrote, find them in order, and report a login that was never
    // made possible. It reads what the install wrote, so it reads it under the same two names.
    expect(RequireKeyLoginPossible.answers, same(InstallAuthorizedKey.answers));
  });
}
