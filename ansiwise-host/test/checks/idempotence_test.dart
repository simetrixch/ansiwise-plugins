import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_host/ansiwise_host.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [hostRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  hostRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// `snap install`, `netplan apply` or `systemctl enable` would leave behind never sees it become
/// true; a step whose precondition is a mounted disk or a fetched archive is blocked before it
/// starts. Neither is a defect in the step, and neither is evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{
  'activate_public_src_routing',
  'add_shell_alias',
  'add_user_to_group',
  'apply_netplan',
  // Nothing about the fake machine keeps it from being exercised: the PROBE does, and no fixture can
  // reach it. Every text argument with no default is handed the same one-character value, so the
  // template this step is told to read and the file it is told to create are the same path — the
  // file is therefore already there and the step is satisfied before it ever has work. A fixture
  // arranges files and commands and cannot change what the probe hands over, so this closes only by
  // the probe being able to hand two text arguments two different values. It is driven twice
  // directly instead, over a machine where the two paths differ, in create_file_from_template_test.
  'create_file_from_template',
  // Nothing about the fake machine keeps it from being exercised: the answer does. Every program
  // that runs it declares `storage_directory` with an empty default, so a run that says nothing
  // about it takes the early return — the machine has no separate data filesystem and there is no
  // directory to make — and the step is satisfied before it ever has work. It was reported as
  // exercised while the probe handed it a placeholder path no installation gives, which measured a
  // branch the product does not take. Closing it needs a program that answers a path, not a fixture.
  'create_storage_directory',
  // Both leave their postcondition behind with `microk8s enable` or `microk8s disable`, and a fake
  // shell records those without carrying them out — so the status it answers after the apply is the
  // status it answered before, and nothing about the second run would be measured.
  'disable_addons',
  'enable_addons',
  'ensure_tool_prerequisites',
  'export_kubeconfig',
  // It has a fixture, and it is still not covered: its apply ends in a `chown` of the key file and
  // its directory, and a fake shell records that command rather than carrying it out. The fixture
  // gets it as far as being applied; nothing here can make the ownership afterwards true.
  'install_authorized_key',
  'install_pinned_tool',
  'install_snap',
  'install_tailscale_client',
  'link_microk8s_storage_path',
  'remove_snap',
  // Its apply restarts the service that reads the file it wrote, and a fake shell records a restart
  // without carrying it out.
  'set_process_flag',
  'set_process_flags',
  'write_connmark_nft_table',
  // Nothing about the fake machine keeps it from being exercised: the ROW does. Which machine this
  // is, and which machine the mirror runs on, are read out of the run under the names the row
  // gives, and a probe hands those two arguments the placeholder text — so the run holds no answer
  // under either name and the step refuses before it starts. That refusal is the step working:
  // reading an absent name as an empty one would decide this machine IS the mirror and leave every
  // pull on the rate-limited public path with nothing saying so. Closing this needs a probe that
  // can plant an answer whose NAME comes out of an argument, which nothing here can do.
  'write_containerd_registry_mirror',
  'write_netplan_public_src_routing',
  'write_public_src_routing_script',
  'write_public_src_routing_unit',
};
