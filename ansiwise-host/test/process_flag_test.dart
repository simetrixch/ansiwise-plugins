import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The two halves of writing one flag that the file's own content cannot show: where a flag lands
/// when the file carries none of it, and that the process is made to read the file again.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = '/var/snap/microk8s/current/args/kube-proxy';

  // The row a program writes. Which file, which flag, what it is set to, and — because the step
  // knows no product — with which permissions the file is written and which command makes the
  // process read it again.
  const SetProcessFlag clusterCidr = SetProcessFlag(
    argsPath: argsPath,
    flag: '--cluster-cidr',
    value: '10.244.0.0/16',
    fileMode: 384,
    restart: <String>['snap', 'restart', 'microk8s.daemon-kubelite'],
  );

  test('a file carrying no such flag gains the line at the end', () async {
    // The other half of the replace-in-place rule: a file already carrying the flag is edited where
    // it stands, and one carrying none grows by exactly this line. Writing the line at the top
    // instead would still satisfy every "carries it once" assertion while reordering a file the
    // process reads in order.
    final HostMachine machine = HostMachine();
    machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

    await clusterCidr.apply(machine.contextFor(under));
    expect(
      machine.files.contents[argsPath],
      '--proxy-mode=nftables\n--cluster-cidr=10.244.0.0/16\n',
    );
  });

  test('the command the row named is what runs, so the process reads the file again', () async {
    // A flag written into a start-up file changes nothing by itself — the process read its flags
    // when it started. Which command makes it read them again is a fact about the machine in front
    // of the run, so it comes from the row and the step runs exactly that.
    final HostMachine machine = HostMachine();
    machine.files.contents[argsPath] = '';

    await clusterCidr.apply(machine.contextFor(under));
    expect(machine.changing, contains('snap restart microk8s.daemon-kubelite'));
  });
}
