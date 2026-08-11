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

  group('waiting for the restarted process to answer again', () {
    // Found on a real machine and findable nowhere else. A service manager reports success when it
    // has ACCEPTED the restart, not when the thing is serving — so the step returned, and the very
    // next row asked the process a question 234 milliseconds later and got a failure carrying no
    // output at all, which it reported as something true about its own subject and false about the
    // machine. Every check by hand a minute later answered perfectly, which is why it survived.
    const SetProcessFlag waiting = SetProcessFlag(
      argsPath: argsPath,
      flag: '--cluster-cidr',
      value: '10.244.0.0/16',
      fileMode: 384,
      restart: <String>['snap', 'restart', 'microk8s.daemon-kubelite'],
      ready: <String>['microk8s', 'status', '--wait-ready'],
      readyTimeout: Duration(seconds: 30),
    );

    test('it keeps asking until the process answers, and only then returns', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      // Down at first, up on the third ask: the shape a restart really has.
      // The effect runs BEFORE the answer is looked up, so the third ask is the one that succeeds.
      int asked = 0;
      const String ask = 'microk8s status --wait-ready';
      machine.shell.fails(ask);
      machine.shell.changes(ask, () {
        asked += 1;
        if (asked >= 3) {
          machine.shell.answers(ask, 'microk8s is running');
        }
      });

      await waiting.apply(machine.contextFor(under));

      expect(asked, 3, reason: 'it stopped at the first success rather than asking on');
      expect(
        machine.shell.ran.indexOf('snap restart microk8s.daemon-kubelite'),
        lessThan(machine.shell.ran.indexOf('microk8s status --wait-ready')),
        reason: 'the wait is after the restart, which is the only order that means anything',
      );
    });

    test('a process that never answers fails loudly, naming both commands', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      machine.shell.fails('microk8s status --wait-ready');

      await expectLater(
        waiting.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>()
              .having((StateError e) => e.message, 'names what did not answer', contains('microk8s status --wait-ready'))
              .having((StateError e) => e.message, 'names what was restarted', contains('snap restart')),
        ),
        reason: 'the rows behind this one would otherwise fail one by one on a process nobody said '
            'was down',
      );
    });

    test('a row that named no ready command returns at once, and SAYS it did not wait', () async {
      // The innocent neighbour, and the honest half: a caller that has not said what answering
      // means cannot be given a guess — but it must not be left believing the wait happened.
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';

      await clusterCidr.apply(machine.contextFor(under));

      expect(machine.said.any((String line) => line.contains('nothing here waits')), isTrue);
    });
  });
}
