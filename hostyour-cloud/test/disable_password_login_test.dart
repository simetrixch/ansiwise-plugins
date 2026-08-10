import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// WHEN the password door is closed, which is a decision of these program files.
///
/// HOW it is closed is a machine's business and moved to the machine plugin with the step that
/// writes the drop-in. What is left here is the ordering that keeps an operator from being locked
/// out: the key login is proven first, and the program that provisions a machine never closes the
/// door at all.
void main() {
  test('the program proves the key works before it takes the password away', () {
    final Program program = loadProgram(
      File(programAt('disable-password-login.yaml')).readAsStringSync(),
      where: 'disable-password-login.yaml',
    );
    final List<StepName> order = <StepName>[for (final ProgramStep s in program.steps) s.step];

    expect(
      order.indexOf(const StepName('require_key_login_possible')),
      lessThan(order.indexOf(const StepName('disable_password_login'))),
      reason: 'taking the password away before the key is proven locks the operator out',
    );
    expect(
      program.steps.every((ProgramStep s) => s.onFailure == OnFailure.exit),
      isTrue,
      reason: 'nothing in this program may be carried past as a warning',
    );
  });

  test('deploy-host does NOT take the password away', () {
    // The machine cannot prove the operator's key login works, because the private half never comes
    // here. So the two are two programs, and this is what keeps them apart.
    final Program deployHost = loadProgram(
      File(programAt('deploy-host.yaml')).readAsStringSync(),
      where: 'deploy-host.yaml',
    );
    expect(
      deployHost.steps.map((ProgramStep s) => s.step),
      isNot(contains(const StepName('disable_password_login'))),
    );
  });
}
