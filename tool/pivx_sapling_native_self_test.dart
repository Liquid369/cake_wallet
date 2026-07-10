import 'dart:io';

import 'package:cw_pivx/src/sapling/sapling_ffi.dart';

void main() {
  final generatedAt = DateTime.now().toUtc().toIso8601String();
  final result = runSaplingNativeSelfTest();

  stdout.writeln('# PIVX Sapling Native Self-Test');
  stdout.writeln();
  stdout.writeln('- generated_at_utc: `$generatedAt`');
  stdout.writeln('- platform: `${Platform.operatingSystem}`');
  stdout.writeln(
    '- library_override: `${Platform.environment['PIVX_SAPLING_LIBRARY_PATH'] ?? 'none'}`',
  );
  stdout.writeln('- passed: `${result.passed}`');
  stdout.writeln('- loaded: `${result.loaded}`');
  stdout.writeln('- symbols_ready: `${result.symbolsReady}`');
  stdout.writeln('- fee_matches_policy: `${result.feeMatchesPolicy}`');
  stdout.writeln('- version: `${result.version ?? 'missing'}`');
  stdout.writeln('- error: `${_formatError(result.error)}`');
  stdout.writeln();

  if (!result.passed) {
    exitCode = 1;
  }
}

String _formatError(String? error) {
  if (error == null || error.isEmpty) {
    return 'none';
  }
  return error.replaceAll('`', "'");
}
