import 'package:ansiwise_core/ansiwise_core.dart';
import 'conditions/key_has_value.dart';
import 'conditions/key_is_true.dart';
import 'conditions/answers_compare.dart';
import 'conditions/keys_compare.dart';
import 'conditions/yaml_key_has_value.dart';
import 'steps/host/activate_public_src_routing.dart';
import 'steps/host/add_shell_alias.dart';
import 'steps/host/add_user_to_group.dart';
import 'steps/host/apply_netplan.dart';
import 'steps/host/clean_package_cache.dart';
import 'steps/host/create_group.dart';
import 'steps/host/create_storage_directory.dart';
import 'steps/host/password_login.dart';
import 'steps/host/enable_addons.dart';
import 'steps/host/enable_service.dart';
import 'steps/host/export_kubeconfig.dart';
import 'steps/host/fill_key_value_file.dart';
import 'steps/host/hand_directory_to_account.dart';
import 'steps/host/install_authorized_key.dart';
import 'steps/host/install_packages.dart';
import 'steps/host/install_pinned_tool.dart';
import 'steps/host/install_snap.dart';
import 'steps/host/install_tailscale_client.dart';
import 'steps/host/install_tool_prerequisites.dart';
import 'steps/host/link_storage_path.dart';
import 'steps/host/measure_host_iptables_backend.dart';
import 'steps/host/measure_host_addresses.dart';
import 'steps/host/measure_host_local_port_range.dart';
import 'steps/host/measure_public_nic.dart';
import 'steps/host/remove_snap.dart';
import 'steps/host/remove_unused_packages.dart';
import 'steps/host/require_answer_matches.dart';
import 'steps/host/require_cli_tool_versions.dart';
import 'steps/host/require_commands.dart';
import 'steps/host/require_free_disk.dart';
import 'steps/host/require_key_login_possible.dart';
import 'steps/host/require_machine_size.dart';
import 'steps/host/require_netplan_merged.dart';
import 'steps/host/require_pinned_ubuntu.dart';
import 'steps/host/require_registry_pull_credential.dart';
import 'steps/host/require_storage_mount.dart';
import 'steps/host/set_process_flag.dart';
import 'steps/host/set_process_flags.dart';
import 'steps/host/stamp_tailnet_address_in_certificate.dart';
import 'steps/host/stamp_variable_value_in_manifest.dart';
import 'steps/host/tailnet_join.dart';
import 'steps/host/tailnet_leave.dart';
import 'steps/host/tailnet_logout.dart';
import 'steps/host/tailnet_reconnect.dart';
import 'steps/host/wait_for_addons_enabled.dart';
import 'steps/host/write_connmark_nft_table.dart';
import 'steps/host/write_containerd_registry_mirror.dart';
import 'steps/host/write_file_from_template.dart';
import 'steps/host/write_netplan_public_src_routing.dart';
import 'steps/host/write_public_src_routing_script.dart';
import 'steps/host/write_public_src_routing_unit.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection, which is what lets a
/// check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> hostSteps = <StepName, RegisteredStep>{
  // Gates that refuse a machine before anything is written to it.
  StepName('require_pinned_ubuntu'): RegisteredStep(
    name: StepName('require_pinned_ubuntu'),
    source: 'lib/src/steps/host/require_pinned_ubuntu.dart:11',
    create: RequirePinnedUbuntu.fromArguments,
    arguments: RequirePinnedUbuntu.arguments,
  ),
  StepName('require_machine_size'): RegisteredStep(
    name: StepName('require_machine_size'),
    source: 'lib/src/steps/host/require_machine_size.dart:15',
    create: RequireMachineSize.fromArguments,
    arguments: RequireMachineSize.arguments,
  ),
  StepName('require_answer_matches'): RegisteredStep(
    name: StepName('require_answer_matches'),
    source: 'lib/src/steps/host/require_answer_matches.dart:7',
    create: RequireAnswerMatches.fromArguments,
    arguments: RequireAnswerMatches.arguments,
  ),
  StepName('require_free_disk'): RegisteredStep(
    name: StepName('require_free_disk'),
    source: 'lib/src/steps/host/require_free_disk.dart:13',
    create: RequireFreeDisk.fromArguments,
    arguments: RequireFreeDisk.arguments,
  ),
  StepName('require_commands'): RegisteredStep(
    name: StepName('require_commands'),
    source: 'lib/src/steps/host/require_commands.dart:18',
    create: RequireCommands.fromArguments,
    arguments: RequireCommands.arguments,
  ),
  // The package manager.
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
  // The key login, and the door that closes only after it is proven.
  StepName('install_authorized_key'): RegisteredStep(
    name: StepName('install_authorized_key'),
    source: 'lib/src/steps/host/install_authorized_key.dart:113',
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
  // TWO NAMES OVER ONE CLASS, for the reason the condition pairs of this package carry: closing the
  // door and opening it again are the same capability at two values — the same drop-in, the same
  // reload, the same question to sshd, and one word different in each. The opening direction is
  // what a person needs after a key is lost, and it is not made safer by living in somebody's shell
  // script instead of in a row a dry run can show.
  StepName('disable_password_login'): RegisteredStep(
    name: StepName('disable_password_login'),
    source: 'lib/src/steps/host/password_login.dart:38',
    create: PasswordLogin.refusing,
    arguments: PasswordLogin.arguments,
  ),
  StepName('enable_password_login'): RegisteredStep(
    name: StepName('enable_password_login'),
    source: 'lib/src/steps/host/password_login.dart:38',
    create: PasswordLogin.allowing,
    arguments: PasswordLogin.arguments,
  ),
  // Snaps.
  StepName('remove_snap'): RegisteredStep(
    name: StepName('remove_snap'),
    source: 'lib/src/steps/host/remove_snap.dart:22',
    create: RemoveSnap.fromArguments,
    arguments: RemoveSnap.arguments,
  ),
  StepName('install_snap'): RegisteredStep(
    name: StepName('install_snap'),
    source: 'lib/src/steps/host/install_snap.dart:37',
    create: InstallSnap.fromArguments,
    arguments: InstallSnap.arguments,
  ),
  StepName('set_process_flag'): RegisteredStep(
    name: StepName('set_process_flag'),
    source: 'lib/src/steps/host/set_process_flag.dart:31',
    create: SetProcessFlag.fromArguments,
    arguments: SetProcessFlag.arguments,
  ),
  // The two files an installation's answers become: what the rest of it reads about itself, and
  // what its secret store is seeded from. ONE entry for both, because they are the same act on
  // different files — the template, the target, the permissions, the keys and the word every
  // refusal uses are all values the row states. It declares no answer of its own: which answer
  // fills which key is what the row says, so a list here would name one product's questions.
  StepName('fill_key_value_file'): RegisteredStep(
    name: StepName('fill_key_value_file'),
    source: 'lib/src/steps/host/fill_key_value_file.dart:31',
    create: FillKeyValueFile.fromArguments,
    arguments: FillKeyValueFile.arguments,
  ),
  StepName('set_process_flags'): RegisteredStep(
    name: StepName('set_process_flags'),
    source: 'lib/src/steps/host/set_process_flags.dart:9',
    create: SetProcessFlags.fromArguments,
    arguments: SetProcessFlags.arguments,
  ),
  // The mirror this machine pulls images through. The gate stands first and the write second, and
  // that order is a constraint rather than a preference: a credential that is merely unfilled is
  // refused while nothing is installed, and refusing it where the mirror is written would stop a
  // run with the machine half built. Both entries declare no answer of their own — which machine
  // this is, and which machine the mirror runs on, are read out of the run under the names the row
  // gives, so this package carries neither name.
  StepName('require_registry_pull_credential'): RegisteredStep(
    name: StepName('require_registry_pull_credential'),
    source: 'lib/src/steps/host/require_registry_pull_credential.dart:28',
    create: RequireRegistryPullCredential.fromArguments,
    arguments: RequireRegistryPullCredential.arguments,
  ),
  StepName('write_containerd_registry_mirror'): RegisteredStep(
    name: StepName('write_containerd_registry_mirror'),
    source: 'lib/src/steps/host/write_containerd_registry_mirror.dart:25',
    create: WriteContainerdRegistryMirror.fromArguments,
    arguments: WriteContainerdRegistryMirror.arguments,
  ),
  // The addons the snap ships, and the manifest one of them builds its address pool from. The
  // entries stand in the order a program runs them: the pod range is stamped before anything is
  // given an address out of it, the addons go on, the wait proves they took, and whatever must
  // stay off is switched off last because some of them come on by themselves.
  StepName('stamp_variable_value_in_manifest'): RegisteredStep(
    name: StepName('stamp_variable_value_in_manifest'),
    source: 'lib/src/steps/host/stamp_variable_value_in_manifest.dart:23',
    create: StampVariableValueInManifest.fromArguments,
    arguments: StampVariableValueInManifest.arguments,
  ),
  StepName('enable_addons'): RegisteredStep(
    name: StepName('enable_addons'),
    source: 'lib/src/steps/host/enable_addons.dart:32',
    create: EnableAddons.fromArguments,
    arguments: EnableAddons.arguments,
  ),
  StepName('wait_for_addons_enabled'): RegisteredStep(
    name: StepName('wait_for_addons_enabled'),
    source: 'lib/src/steps/host/wait_for_addons_enabled.dart:29',
    create: WaitForAddonsEnabled.fromArguments,
    arguments: WaitForAddonsEnabled.arguments,
  ),
  // The group an account is put into, which has to be on the machine before anything can name it.
  StepName('create_group'): RegisteredStep(
    name: StepName('create_group'),
    source: 'lib/src/steps/host/create_group.dart:18',
    create: CreateGroup.fromArguments,
    arguments: CreateGroup.arguments,
  ),
  // The operator's account.
  StepName('add_user_to_group'): RegisteredStep(
    name: StepName('add_user_to_group'),
    source: 'lib/src/steps/host/add_user_to_group.dart:12',
    create: AddUserToGroup.fromArguments,
    arguments: AddUserToGroup.arguments,
    answers: AddUserToGroup.answers,
  ),
  StepName('enable_service'): RegisteredStep(
    name: StepName('enable_service'),
    source: 'lib/src/steps/host/enable_service.dart:32',
    create: EnableService.fromArguments,
    arguments: EnableService.arguments,
  ),
  StepName('add_shell_alias'): RegisteredStep(
    name: StepName('add_shell_alias'),
    source: 'lib/src/steps/host/add_shell_alias.dart:11',
    create: AddShellAlias.fromArguments,
    arguments: AddShellAlias.arguments,
    answers: AddShellAlias.answers,
  ),
  StepName('export_kubeconfig'): RegisteredStep(
    name: StepName('export_kubeconfig'),
    source: 'lib/src/steps/host/export_kubeconfig.dart:20',
    create: ExportKubeconfig.fromArguments,
    arguments: ExportKubeconfig.arguments,
    answers: ExportKubeconfig.answers,
  ),
  // A directory a real account on this machine has to be able to write into. The account is named in
  // an answer, because which number an installation gave it is that machine's own fact.
  StepName('hand_directory_to_account'): RegisteredStep(
    name: StepName('hand_directory_to_account'),
    source: 'lib/src/steps/host/hand_directory_to_account.dart:27',
    create: HandDirectoryToAccount.fromArguments,
    arguments: HandDirectoryToAccount.arguments,
  ),
  // Storage.
  StepName('require_storage_mount'): RegisteredStep(
    name: StepName('require_storage_mount'),
    source: 'lib/src/steps/host/require_storage_mount.dart:12',
    create: RequireStorageMount.fromArguments,
    arguments: RequireStorageMount.arguments,
    answers: RequireStorageMount.answers,
  ),
  StepName('create_storage_directory'): RegisteredStep(
    name: StepName('create_storage_directory'),
    source: 'lib/src/steps/host/create_storage_directory.dart:9',
    create: CreateStorageDirectory.fromArguments,
    arguments: CreateStorageDirectory.arguments,
    answers: CreateStorageDirectory.answers,
  ),
  StepName('link_storage_path'): RegisteredStep(
    name: StepName('link_storage_path'),
    source: 'lib/src/steps/host/link_storage_path.dart:13',
    create: LinkStoragePath.fromArguments,
    arguments: LinkStoragePath.arguments,
    answers: LinkStoragePath.answers,
  ),
  // Tools fetched onto the machine.
  StepName('install_tool_prerequisites'): RegisteredStep(
    name: StepName('install_tool_prerequisites'),
    source: 'lib/src/steps/host/install_tool_prerequisites.dart:16',
    create: InstallToolPrerequisites.fromArguments,
    arguments: InstallToolPrerequisites.arguments,
  ),
  StepName('install_pinned_tool'): RegisteredStep(
    name: StepName('install_pinned_tool'),
    source: 'lib/src/steps/host/install_pinned_tool.dart:39',
    create: InstallPinnedTool.fromArguments,
    arguments: InstallPinnedTool.arguments,
  ),
  StepName('install_tailscale_client'): RegisteredStep(
    name: StepName('install_tailscale_client'),
    source: 'lib/src/steps/host/install_tailscale_client.dart:18',
    create: InstallTailscaleClient.fromArguments,
    arguments: InstallTailscaleClient.arguments,
  ),
  StepName('require_cli_tool_versions'): RegisteredStep(
    name: StepName('require_cli_tool_versions'),
    source: 'lib/src/steps/host/require_cli_tool_versions.dart:28',
    create: RequireCliToolVersions.fromArguments,
    arguments: RequireCliToolVersions.arguments,
  ),
  // Steering replies on a machine whose public address arrives on one interface while another
  // owns the default route. The entries stand in the order a program runs them.
  StepName('measure_public_nic'): RegisteredStep(
    name: StepName('measure_public_nic'),
    source: 'lib/src/steps/host/measure_public_nic.dart:20',
    create: MeasurePublicNic.fromArguments,
    arguments: MeasurePublicNic.arguments,
  ),
  StepName('write_netplan_public_src_routing'): RegisteredStep(
    name: StepName('write_netplan_public_src_routing'),
    source: 'lib/src/steps/host/write_netplan_public_src_routing.dart:26',
    create: WriteNetplanPublicSrcRouting.fromArguments,
    arguments: WriteNetplanPublicSrcRouting.arguments,
  ),
  StepName('require_netplan_merged'): RegisteredStep(
    name: StepName('require_netplan_merged'),
    source: 'lib/src/steps/host/require_netplan_merged.dart:15',
    create: RequireNetplanMerged.fromArguments,
    arguments: RequireNetplanMerged.arguments,
  ),
  StepName('apply_netplan'): RegisteredStep(
    name: StepName('apply_netplan'),
    source: 'lib/src/steps/host/apply_netplan.dart:12',
    create: ApplyNetplan.fromArguments,
    arguments: ApplyNetplan.arguments,
  ),
  StepName('write_connmark_nft_table'): RegisteredStep(
    name: StepName('write_connmark_nft_table'),
    source: 'lib/src/steps/host/write_connmark_nft_table.dart:21',
    create: WriteConnmarkNftTable.fromArguments,
    arguments: WriteConnmarkNftTable.arguments,
  ),
  StepName('write_public_src_routing_script'): RegisteredStep(
    name: StepName('write_public_src_routing_script'),
    source: 'lib/src/steps/host/write_public_src_routing_script.dart:16',
    create: WritePublicSrcRoutingScript.fromArguments,
    arguments: WritePublicSrcRoutingScript.arguments,
  ),
  StepName('write_public_src_routing_unit'): RegisteredStep(
    name: StepName('write_public_src_routing_unit'),
    source: 'lib/src/steps/host/write_public_src_routing_unit.dart:15',
    create: WritePublicSrcRoutingUnit.fromArguments,
    arguments: WritePublicSrcRoutingUnit.arguments,
  ),
  StepName('activate_public_src_routing'): RegisteredStep(
    name: StepName('activate_public_src_routing'),
    source: 'lib/src/steps/host/activate_public_src_routing.dart:10',
    create: ActivatePublicSrcRouting.fromArguments,
    arguments: ActivatePublicSrcRouting.arguments,
  ),
  // Measurements the network conversion of a cluster asks for.
  StepName('measure_host_iptables_backend'): RegisteredStep(
    name: StepName('measure_host_iptables_backend'),
    source: 'lib/src/steps/host/measure_host_iptables_backend.dart:13',
    create: MeasureHostIptablesBackend.fromArguments,
    arguments: MeasureHostIptablesBackend.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('backend'),
        describes: 'the packet-filtering backend this machine is on',
      ),
    ],
  ),
  // WHERE THIS MACHINE CAN BE REACHED, for whatever has to draw a boundary around it. It declares no
  // answer: a machine's own addresses are read off the machine. Which interfaces are not the
  // machine's own is a row argument rather than a list here, because that depends on what the
  // machine runs and this package carries no name of anything a machine might run.
  StepName('measure_host_addresses'): RegisteredStep(
    name: StepName('measure_host_addresses'),
    source: 'lib/src/steps/host/measure_host_addresses.dart:46',
    create: MeasureHostAddresses.fromArguments,
    arguments: MeasureHostAddresses.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasureHostAddresses.published,
        describes:
            'the addresses this machine can be reached at, each as a /32, written as a list on one '
            'line with a comma and a space between them',
      ),
    ],
  ),
  StepName('measure_host_local_port_range'): RegisteredStep(
    name: StepName('measure_host_local_port_range'),
    source: 'lib/src/steps/host/measure_host_local_port_range.dart:31',
    create: MeasureHostLocalPortRange.fromArguments,
    arguments: MeasureHostLocalPortRange.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('local_port_range'),
        describes: 'the ports this machine opens its own outgoing connections from',
      ),
    ],
  ),
  // The file system as a tool. It declares no answer of its own: which file, where it goes and
  // which axis a caller wants one of them per are read out of the row, so this package carries no
  // name of any file a product keeps.
  StepName('write_file_from_template'): RegisteredStep(
    name: StepName('write_file_from_template'),
    source: 'lib/src/steps/host/write_file_from_template.dart:28',
    create: WriteFileFromTemplate.fromArguments,
    arguments: WriteFileFromTemplate.arguments,
  ),
  // The private-network client's four acts, in the order a repair uses them: leave, come back with
  // what the machine holds, discard what it holds, join with a fresh credential. The join is the
  // one that declares answers: where the coordinator serves and the credential minted there are
  // facts of one run, and neither may stand in a program file — one names an installation, the
  // other is a secret.
  StepName('tailnet_leave'): RegisteredStep(
    name: StepName('tailnet_leave'),
    source: 'lib/src/steps/host/tailnet_leave.dart:16',
    create: TailnetLeave.fromArguments,
    arguments: TailnetLeave.arguments,
  ),
  StepName('tailnet_reconnect'): RegisteredStep(
    name: StepName('tailnet_reconnect'),
    source: 'lib/src/steps/host/tailnet_reconnect.dart:21',
    create: TailnetReconnect.fromArguments,
    arguments: TailnetReconnect.arguments,
  ),
  StepName('tailnet_logout'): RegisteredStep(
    name: StepName('tailnet_logout'),
    source: 'lib/src/steps/host/tailnet_logout.dart:16',
    create: TailnetLogout.fromArguments,
    arguments: TailnetLogout.arguments,
  ),
  StepName('tailnet_join'): RegisteredStep(
    name: StepName('tailnet_join'),
    source: 'lib/src/steps/host/tailnet_join.dart:21',
    create: TailnetJoin.fromArguments,
    arguments: TailnetJoin.arguments,
    answers: TailnetJoin.answers,
  ),
  // What makes the machine reachable at the address the join handed it: the serving certificate
  // everything verified dials it by.
  StepName('stamp_tailnet_address_in_certificate'): RegisteredStep(
    name: StepName('stamp_tailnet_address_in_certificate'),
    source: 'lib/src/steps/host/stamp_tailnet_address_in_certificate.dart:32',
    create: StampTailnetAddressInCertificate.fromArguments,
    arguments: StampTailnetAddressInCertificate.arguments,
  ),
};

/// Every condition this plugin carries.
///
/// ONE entry, and it is GENERIC: it still has to be told which file and which key before a program
/// row may name it. That is the whole of what this package may know about a condition. What the
/// answer is CALLED — the word a program writes behind `when:` — and what it is pointed at are
/// properties of one installation, and they are said on that installation's own configuration under
/// `conditions:`, where the framework binds them onto this entry under the name it chose.
const Map<PredicateName, RegisteredPredicate> hostConditions = <PredicateName, RegisteredPredicate>{
  // Two names for one reading, for the reason the pair below carries: a `not:` behind `when:` would
  // be an operator, and a program row writes one bare word. An installation gates on a switch being
  // off as often as on its being on.
  PredicateName('key_is_true'): RegisteredPredicate.taking(
    name: PredicateName('key_is_true'),
    source: 'lib/src/conditions/key_is_true.dart:53',
    create: KeyIsTrue.holdingTrue,
    describes: 'whether a key in a KEY=value file holds true',
    arguments: KeyIsTrue.arguments,
  ),
  PredicateName('key_is_false'): RegisteredPredicate.taking(
    name: PredicateName('key_is_false'),
    source: 'lib/src/conditions/key_is_true.dart:53',
    create: KeyIsTrue.holdingFalse,
    describes: 'whether a key in a KEY=value file holds false',
    arguments: KeyIsTrue.arguments,
  ),
  // The third shape, for a fact that is neither a truth nor a relation but a CHOICE among named
  // things — which authority a cluster issues from, named rather than asserted. Two names again,
  // for the same reason as the pairs around it.
  PredicateName('key_has_value'): RegisteredPredicate.taking(
    name: PredicateName('key_has_value'),
    source: 'lib/src/conditions/key_has_value.dart:50',
    create: KeyHasValue.matching,
    describes: 'whether a key in a KEY=value file carries one stated value',
    arguments: KeyHasValue.arguments,
  ),
  PredicateName('key_lacks_value'): RegisteredPredicate.taking(
    name: PredicateName('key_lacks_value'),
    source: 'lib/src/conditions/key_has_value.dart:50',
    create: KeyHasValue.differing,
    describes: 'whether a key in a KEY=value file carries anything but one stated value',
    arguments: KeyHasValue.arguments,
  ),
  // The same third shape over the other file grammar this package reads. A `KEY=value` file is what
  // a shell sources; a YAML file is what a declarative tree is written in, and the six entries above
  // answer ConditionUnanswerable on one — a file of no `KEY=value` lines carries no line assigning
  // anything. The path is dotted, because a YAML file nests and a `KEY=value` file does not.
  PredicateName('yaml_key_has_value'): RegisteredPredicate.taking(
    name: PredicateName('yaml_key_has_value'),
    source: 'lib/src/conditions/yaml_key_has_value.dart:44',
    create: YamlKeyHasValue.matching,
    describes: 'whether a key of a YAML file, at a dotted path, carries one stated value',
    arguments: YamlKeyHasValue.arguments,
  ),
  PredicateName('yaml_key_lacks_value'): RegisteredPredicate.taking(
    name: PredicateName('yaml_key_lacks_value'),
    source: 'lib/src/conditions/yaml_key_has_value.dart:44',
    create: YamlKeyHasValue.differing,
    describes:
        'whether a key of a YAML file, at a dotted path, carries anything but one stated value',
    arguments: YamlKeyHasValue.arguments,
  ),
  // Two names for one comparison, because a `not:` behind `when:` would be an operator and an
  // operator is where a program file starts being a language.
  PredicateName('key_values_agree'): RegisteredPredicate.taking(
    name: PredicateName('key_values_agree'),
    source: 'lib/src/conditions/keys_compare.dart:41',
    create: KeysAgree.agreeing,
    describes: 'whether two keys of a KEY=value file carry the same value',
    arguments: KeysAgree.arguments,
  ),
  PredicateName('key_values_differ'): RegisteredPredicate.taking(
    name: PredicateName('key_values_differ'),
    source: 'lib/src/conditions/keys_compare.dart:41',
    create: KeysAgree.differing,
    describes: 'whether two keys of a KEY=value file carry different values',
    arguments: KeysAgree.arguments,
  ),
  // The same relation over the RUN rather than over a file, for the one case a file cannot serve: a
  // condition that has to hold before the first step, because it decides whether an answer had to be
  // given at all. A file is written by a step, and a step runs after the answers are validated.
  PredicateName('answer_values_agree'): RegisteredPredicate.taking(
    name: PredicateName('answer_values_agree'),
    source: 'lib/src/conditions/answers_compare.dart:31',
    create: AnswersAgree.agreeing,
    describes: 'whether two answers of the run carry the same value',
    arguments: AnswersAgree.arguments,
  ),
  PredicateName('answer_values_differ'): RegisteredPredicate.taking(
    name: PredicateName('answer_values_differ'),
    source: 'lib/src/conditions/answers_compare.dart:31',
    create: AnswersAgree.differing,
    describes: 'whether two answers of the run carry different values',
    arguments: AnswersAgree.arguments,
  ),
};

/// Everything this plugin teaches the framework.
const Registry hostRegistry = Registry(steps: hostSteps, predicates: hostConditions);
