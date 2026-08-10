/// What the MicroK8s snap is called on a machine, where what it starts reads its arguments, and how
/// it says the node is up.
///
/// **These are facts about MicroK8s, and no single step owns them.** Some steps name the snap to the
/// snap client and to the account tools; others write one file into the arguments directory, and one
/// capability writes any of those files a program row names. They stood on the step that happened to
/// install the snap, which made every one of them depend on an installer to learn a path. A snap
/// installed at a channel is a capability now and knows nothing about MicroK8s, so the names stand
/// here — in one place, next to the steps that read them, and behind no class.
library;

/// The name the snap is published under, and the name of the command it puts on the path.
const String microk8sSnap = 'microk8s';

/// The directory holding the arguments every MicroK8s service is started with.
///
/// Several steps write one file in here, and the path is the same for all of them because the
/// snap's `current` symlink is what the services read through.
const String microk8sArgumentsDirectory = '/var/snap/$microk8sSnap/current/args';

/// The file holding the arguments kube-proxy is started with.
const String microk8sKubeProxyArguments = '$microk8sArgumentsDirectory/kube-proxy';

/// `0600` — an argument file the services read as root, and nothing else has business in.
const int microk8sArgumentsFileMode = 0x180;

/// The service that has to be restarted for an argument file to be read again.
///
/// The services under the snap are not processes of their own — they run inside kubelite — so
/// nothing about restarting one of them by its own name would work. This is what the argument files
/// under the snap are read by.
const String microk8sKubelite = 'microk8s.daemon-kubelite';

/// The line the status writes when the node is up.
///
/// The line and not the exit code: the status returns zero on a node that answered, whatever the
/// answer was, so anything reading the code would read a node reporting itself down as a success.
const String microk8sRunningLine = 'microk8s is running';
