import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The two halves of writing one flag that the file's own content cannot show: where a flag lands
/// when the file carries none of it, and that the process is made to read the file again.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = '/etc/proxy/args';

  // The row a program writes. Which file, which flag, what it is set to, and — because the step
  // knows no product — with which permissions the file is written and which command makes the
  // process read it again.
  const SetProcessFlag clusterCidr = SetProcessFlag(
    argsPath: argsPath,
    flag: '--cluster-cidr',
    value: '10.244.0.0/16',
    fileMode: 384,
    restart: <String>['snap', 'restart', 'proxy-daemon'],
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
    expect(machine.changing, contains('snap restart proxy-daemon'));
  });

  group('waiting for the restarted process to answer again', () {
    // Findable on a real machine and nowhere else. A service manager reports success when it
    // has ACCEPTED the restart, not when the thing is serving — so the step returned, and the very
    // next row asked the process a question 234 milliseconds later and got a failure carrying no
    // output at all, which it reported as something true about its own subject and false about the
    // machine. Every check by hand a minute later answered perfectly, which is why it survived.
    const SetProcessFlag waiting = SetProcessFlag(
      argsPath: argsPath,
      flag: '--cluster-cidr',
      value: '10.244.0.0/16',
      fileMode: 384,
      restart: <String>['snap', 'restart', 'proxy-daemon'],
      ready: <String>['cluster', 'status', '--wait-ready'],
      readyTimeout: Duration(seconds: 30),
    );

    test('it keeps asking until the process answers, and only then returns', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      // Down at first, up on the third ask: the shape a restart really has.
      // The effect runs BEFORE the answer is looked up, so the third ask is the one that succeeds.
      int asked = 0;
      const String ask = 'cluster status --wait-ready';
      machine.shell.fails(ask);
      machine.shell.changes(ask, () {
        asked += 1;
        if (asked >= 3) {
          machine.shell.answers(ask, 'the node is running');
        }
      });

      await waiting.apply(machine.contextFor(under));

      expect(asked, 3, reason: 'it stopped at the first success rather than asking on');
      expect(
        machine.shell.ran.indexOf('snap restart proxy-daemon'),
        lessThan(machine.shell.ran.indexOf('cluster status --wait-ready')),
        reason: 'the wait is after the restart, which is the only order that means anything',
      );
    });

    test('a process that never answers fails loudly, naming both commands', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      machine.shell.fails('cluster status --wait-ready');

      await expectLater(
        waiting.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>()
              .having(
                (StateError e) => e.message,
                'names what did not answer',
                contains('cluster status --wait-ready'),
              )
              .having(
                (StateError e) => e.message,
                'names what was restarted',
                contains('snap restart'),
              ),
        ),
        reason:
            'the rows behind this one would otherwise fail one by one on a process nobody said '
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

  group('a restart command the machine refuses', () {
    // THE SHAPE THIS CATCHES, taken from the machine it was found on. The row named a service the
    // snap in front of it does not carry — a neighbouring name, off by one word — so the manager
    // answered `has no service of that name` and exited non-zero. The result was thrown away, and
    // then the wait found the process answering at the FIRST ask, because it had never gone down.
    // Six flags stood written in the file, the running process carried none of them, and the step
    // reported that the machine now runs on them. What an operator saw was a console that returned
    // them to the sign-in dialog and a run record saying there was nothing to do.
    const SetProcessFlag flag = SetProcessFlag(
      argsPath: argsPath,
      flag: '--cluster-cidr',
      value: '10.244.0.0/16',
      fileMode: 384,
      restart: <String>['snap', 'restart', 'proxy-daemon'],
      ready: <String>['proxy', 'status'],
      readyTimeout: Duration(seconds: 30),
    );

    test('a restart that failed is a failed step, not a waited-for one', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      machine.shell
        ..fails('snap restart proxy-daemon')
        // The trap in one line: what the wait asks answers perfectly, because nothing restarted.
        ..answers('proxy status', 'running\n');

      await expectLater(
        flag.apply(machine.contextFor(under)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed e) => e.message,
            'names the command the machine refused',
            contains('snap restart proxy-daemon'),
          ),
        ),
        reason:
            'the file now carries a flag nothing has read, and only the failure says so — the '
            'wait cannot, because a process that never went down answers at once',
      );
    });

    test('a restart the machine accepts is waited for and finishes', () async {
      // The innocent case. Without it a green run might mean the refusal above is reported for
      // every restart rather than for a refused one.
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '';
      machine.shell.answers('proxy status', 'running\n');

      await flag.apply(machine.contextFor(under));

      expect(machine.changing, contains('snap restart proxy-daemon'));
      expect(machine.files.contents[argsPath], contains('--cluster-cidr=10.244.0.0/16'));
    });
  });

  group('a flag whose value only a run holds', () {
    // ONE NOTATION, and the reason it matters. What stood here was a private pattern inside this
    // step: any characters between angle brackets, the name looked up verbatim, and nothing said
    // where an answer was missing. So `<build_plane>` worked in a flag and meant nothing in a
    // template — the same text, two meanings, which is what one grammar exists to prevent.
    const SetProcessFlags bound = SetProcessFlags(
      argsPath: argsPath,
      flags: <String>['--issuer-url=https://idp.<books-cluster>/o/x/', '--client-id=headlamp'],
      fileMode: 384,
      restart: <String>['snap', 'restart', 'proxy-daemon'],
      ready: <String>['proxy', 'status'],
      readyTimeout: Duration(seconds: 30),
      values: <String, KeyBinding>{'books-cluster': KeyBinding(answer: 'books_cluster')},
    );

    StepContext runWith(HostMachine machine, Map<String, Object> answers) =>
        machine.contextFor(under, Arguments.none, Arguments(answers));

    test('THE INNOCENT CASE: the slot holds the answer the row bound to it', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

      await bound.apply(runWith(machine, <String, Object>{'books_cluster': 'm1.example.com'}));

      final String written = machine.files.contents[argsPath]!;
      expect(written, contains('--issuer-url=https://idp.m1.example.com/o/x/'));
      expect(written, contains('--client-id=headlamp'));
    });

    test('a slot NOTHING fills is refused, never written out as text', () async {
      // The dangerous case. Written out, the process reads --issuer-url=<books-cluster> as that
      // literal address, and every token check fails for a reason nothing on the machine explains.
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';
      const SetProcessFlags unbound = SetProcessFlags(
        argsPath: argsPath,
        flags: <String>['--issuer-url=https://idp.<books-cluster>/o/x/'],
        fileMode: 384,
        restart: <String>['snap', 'restart', 'proxy-daemon'],
        ready: <String>['proxy', 'status'],
        readyTimeout: Duration(seconds: 30),
      );

      expect(
        () => unbound.apply(runWith(machine, <String, Object>{'books_cluster': 'm1.example.com'})),
        throwsA(isA<TemplateRefused>()),
      );
    });

    test('one restart for all the flags, not one each', () async {
      // The reason the plural step exists at all. A restart between two flags leaves the process
      // running on half of them, which is what an `echo` standing in for a restart command hid.
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

      await bound.apply(runWith(machine, <String, Object>{'books_cluster': 'm1.example.com'}));

      expect(
        machine.shell.ran.where((String c) => c.contains('restart')).length,
        1,
        reason: 'both flags are written, then the process is restarted once',
      );
    });
  });
}
