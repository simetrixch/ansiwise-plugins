import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

import 'plugin.dart';

/// Every plugin this product's binary is compiled with.
///
/// **Compiled in here, switched on in the configuration.** Dart ahead of time loads no code that was
/// not built in, so this list is a fact of the BUILD. Which of them an installation turns on is a
/// fact of that installation and is read from its configuration file, which is why the two are
/// separate: a binary that carried only what one installation wanted would have to be rebuilt to
/// change its mind.
///
/// **It stands in the library and not in the binary so a test resolves what the binary resolves.**
/// A program file is checked against the registry the plugins compose, and a test composing its own
/// list would prove a program correct against a set of steps nobody ships.
const PluginSet compiledPlugins = PluginSet(<Plugin>[
  HostPlugin(),
  KubernetesPlugin(),
  VaultPlugin(),
  HelmPlugin(),
  HostyourCloudPlugin(),
]);
