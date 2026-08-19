import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/cloudflare_a_record.dart';
import 'steps/cloudflare_dkim_record.dart';
import 'steps/cloudflare_dmarc_record.dart';
import 'steps/cloudflare_spf_record.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> cloudflareSteps = <StepName, RegisteredStep>{
  StepName('cloudflare_a_record'): RegisteredStep(
    name: StepName('cloudflare_a_record'),
    source: 'lib/src/steps/cloudflare_a_record.dart:23',
    create: CloudflareARecord.fromArguments,
    arguments: CloudflareARecord.arguments,
  ),
  StepName('cloudflare_spf_record'): RegisteredStep(
    name: StepName('cloudflare_spf_record'),
    source: 'lib/src/steps/cloudflare_spf_record.dart:25',
    create: CloudflareSpfRecord.fromArguments,
    arguments: CloudflareSpfRecord.arguments,
  ),
  StepName('cloudflare_dkim_record'): RegisteredStep(
    name: StepName('cloudflare_dkim_record'),
    source: 'lib/src/steps/cloudflare_dkim_record.dart:21',
    create: CloudflareDkimRecord.fromArguments,
    arguments: CloudflareDkimRecord.arguments,
  ),
  StepName('cloudflare_dmarc_record'): RegisteredStep(
    name: StepName('cloudflare_dmarc_record'),
    source: 'lib/src/steps/cloudflare_dmarc_record.dart:16',
    create: CloudflareDmarcRecord.fromArguments,
    arguments: CloudflareDmarcRecord.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about one product's state, and that is what this
/// package deliberately knows nothing about.
const Registry cloudflareRegistry = Registry(
  steps: cloudflareSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
