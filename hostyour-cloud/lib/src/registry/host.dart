import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/host/clean_package_cache.dart';
import '../steps/host/disable_password_login.dart';
import '../steps/host/install_authorized_key.dart';
import '../steps/host/install_packages.dart';
import '../steps/host/remove_unused_packages.dart';
import '../steps/host/require_commands.dart';
import '../steps/host/require_key_login_possible.dart';
import '../steps/host/require_free_disk.dart';
import '../steps/host/require_machine_size.dart';
import '../steps/host/require_pinned_ubuntu.dart';

/// Every step that acts on a machine as a machine — before anything about a cluster exists.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
const Map<StepName, RegisteredStep> hostSteps = <StepName, RegisteredStep>{
  StepName('require_pinned_ubuntu'): RegisteredStep(
    name: StepName('require_pinned_ubuntu'),
    source: 'lib/src/steps/host/require_pinned_ubuntu.dart:12',
    create: RequirePinnedUbuntu.fromArguments,
    arguments: RequirePinnedUbuntu.arguments,
  ),
  StepName('require_machine_size'): RegisteredStep(
    name: StepName('require_machine_size'),
    source: 'lib/src/steps/host/require_machine_size.dart:12',
    create: RequireMachineSize.fromArguments,
    arguments: RequireMachineSize.arguments,
  ),
  StepName('require_free_disk'): RegisteredStep(
    name: StepName('require_free_disk'),
    source: 'lib/src/steps/host/require_free_disk.dart:8',
    create: RequireFreeDisk.fromArguments,
    arguments: RequireFreeDisk.arguments,
  ),
  StepName('require_commands'): RegisteredStep(
    name: StepName('require_commands'),
    source: 'lib/src/steps/host/require_commands.dart:16',
    create: RequireCommands.fromArguments,
    arguments: RequireCommands.arguments,
  ),
  StepName('install_packages'): RegisteredStep(
    name: StepName('install_packages'),
    source: 'lib/src/steps/host/install_packages.dart:14',
    create: InstallPackages.fromArguments,
    arguments: InstallPackages.arguments,
  ),
  StepName('remove_unused_packages'): RegisteredStep(
    name: StepName('remove_unused_packages'),
    source: 'lib/src/steps/host/remove_unused_packages.dart:8',
    create: RemoveUnusedPackages.fromArguments,
    arguments: RemoveUnusedPackages.arguments,
  ),
  StepName('clean_package_cache'): RegisteredStep(
    name: StepName('clean_package_cache'),
    source: 'lib/src/steps/host/clean_package_cache.dart:10',
    create: CleanPackageCache.fromArguments,
    arguments: CleanPackageCache.arguments,
  ),
  StepName('disable_password_login'): RegisteredStep(
    name: StepName('disable_password_login'),
    source: 'lib/src/steps/host/disable_password_login.dart:15',
    create: DisablePasswordLogin.fromArguments,
    arguments: DisablePasswordLogin.arguments,
  ),
  StepName('install_authorized_key'): RegisteredStep(
    name: StepName('install_authorized_key'),
    source: 'lib/src/steps/host/install_authorized_key.dart:12',
    create: InstallAuthorizedKey.fromArguments,
    arguments: InstallAuthorizedKey.arguments,
    answers: InstallAuthorizedKey.answers,
  ),
  StepName('require_key_login_possible'): RegisteredStep(
    name: StepName('require_key_login_possible'),
    source: 'lib/src/steps/host/require_key_login_possible.dart:20',
    create: RequireKeyLoginPossible.fromArguments,
    arguments: RequireKeyLoginPossible.arguments,
    answers: RequireKeyLoginPossible.answers,
  ),
};
