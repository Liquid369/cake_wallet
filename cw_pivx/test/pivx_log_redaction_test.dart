import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PIVX sensitive log redaction', () {
    final filesToScan = <String>[
      'cw_bitcoin/lib/electrum.dart',
      'cw_pivx/lib/src/pending_pivx_shielded_transaction.dart',
      'cw_pivx/lib/src/pivx_wallet.dart',
      'cw_pivx/lib/src/pivx_wallet_service.dart',
      'cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart',
      'cw_pivx/lib/src/sapling/sapling_factories.dart',
      'cw_pivx/lib/src/sapling/sapling_note_storage.dart',
      'lib/view_model/send/send_view_model.dart',
    ];

    final statementStart = RegExp(r'\b(?:print|printV)\s*\(');
    final interpolation = RegExp(r'\$[A-Za-z_{]|toString\(\)');
    final sensitiveTerms = RegExp(
      r'\b(seed|mnemonic|rseed|nullifier|cmu|witness|txid|anchor|'
      r'address|balance|note|value|position|ciphertext|commitment)\b',
      caseSensitive: false,
    );

    String collectStatement(List<String> lines, int startIndex) {
      final buffer = StringBuffer(lines[startIndex].trim());
      for (var i = startIndex + 1;
          i < lines.length && !buffer.toString().contains(');');
          i++) {
        buffer.write(' ${lines[i].trim()}');
      }
      return buffer.toString();
    }

    test('does not interpolate sensitive PIVX/Sapling metadata into logs', () {
      final violations = <String>[];

      for (final path in filesToScan) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'Missing scanned file $path');

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!statementStart.hasMatch(lines[i])) continue;

          final statement = collectStatement(lines, i);
          if (interpolation.hasMatch(statement) &&
              sensitiveTerms.hasMatch(statement)) {
            violations.add('$path:${i + 1}: $statement');
          }
        }
      }

      expect(violations, isEmpty);
    });

    test('invalid PIVX mnemonic errors stay generic', () {
      final service =
          File('cw_pivx/lib/src/pivx_wallet_service.dart').readAsStringSync();

      expect(service, contains("throw Exception('Invalid PIVX mnemonic')"));
      expect(service, isNot(contains('Invalid mnemonic:')));
      expect(service, isNot(contains(r'${credentials.mnemonic}')));
    });
  });
}
