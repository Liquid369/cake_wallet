import 'dart:typed_data';

import 'package:cw_bitcoin/electrum.dart';
import 'package:cw_bitcoin/bitcoin_amount_format.dart';
import 'package:cw_bitcoin/exceptions.dart';
import 'package:cw_core/pending_transaction.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:convert/convert.dart';
import 'sapling/sapling_factories.dart' show SaplingTransactionResult;

class PivxShieldedTransactionDebugSummary {
  PivxShieldedTransactionDebugSummary({
    required this.byteLength,
    required this.version,
    required this.type,
    required this.transparentInputCount,
    required this.transparentOutputCount,
    required this.hasSaplingData,
    required this.valueBalance,
    required this.shieldedSpendCount,
    required this.shieldedOutputCount,
    required this.hasBindingSignature,
    this.parseError,
  });

  final int byteLength;
  final int? version;
  final int? type;
  final int? transparentInputCount;
  final int? transparentOutputCount;
  final bool hasSaplingData;
  final int? valueBalance;
  final int? shieldedSpendCount;
  final int? shieldedOutputCount;
  final bool hasBindingSignature;
  final String? parseError;

  static const int _saplingSpendDescriptionSize = 384;
  static const int _saplingOutputDescriptionSize = 948;
  static const int _saplingBindingSignatureSize = 64;

  factory PivxShieldedTransactionDebugSummary.fromHex(String txHex) {
    try {
      return PivxShieldedTransactionDebugSummary._parse(hex.decode(txHex));
    } catch (e) {
      return PivxShieldedTransactionDebugSummary(
        byteLength: txHex.length ~/ 2,
        version: null,
        type: null,
        transparentInputCount: null,
        transparentOutputCount: null,
        hasSaplingData: false,
        valueBalance: null,
        shieldedSpendCount: null,
        shieldedOutputCount: null,
        hasBindingSignature: false,
        parseError: 'parse_failed',
      );
    }
  }

  factory PivxShieldedTransactionDebugSummary._parse(List<int> bytes) {
    var offset = 0;

    int readInt16() {
      _require(bytes, offset, 2);
      final value = bytes[offset] | (bytes[offset + 1] << 8);
      offset += 2;
      return value >= 0x8000 ? value - 0x10000 : value;
    }

    int readInt64() {
      _require(bytes, offset, 8);
      final value = Uint8List.fromList(bytes.sublist(offset, offset + 8))
          .buffer
          .asByteData()
          .getInt64(0, Endian.little);
      offset += 8;
      return value;
    }

    int readUint32() {
      _require(bytes, offset, 4);
      final value = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4;
      return value;
    }

    int readVarInt() {
      _require(bytes, offset, 1);
      final first = bytes[offset++];
      if (first < 0xfd) return first;
      if (first == 0xfd) {
        _require(bytes, offset, 2);
        final value = bytes[offset] | (bytes[offset + 1] << 8);
        offset += 2;
        return value;
      }
      if (first == 0xfe) {
        return readUint32();
      }
      _require(bytes, offset, 8);
      var value = 0;
      for (var i = 0; i < 8; i++) {
        value |= bytes[offset + i] << (8 * i);
      }
      offset += 8;
      return value;
    }

    void skip(int length) {
      _require(bytes, offset, length);
      offset += length;
    }

    final version = readInt16();
    final type = readInt16();
    final inputCount = readVarInt();
    for (var i = 0; i < inputCount; i++) {
      skip(36);
      final scriptLength = readVarInt();
      skip(scriptLength);
      skip(4);
    }

    final outputCount = readVarInt();
    for (var i = 0; i < outputCount; i++) {
      skip(8);
      final scriptLength = readVarInt();
      skip(scriptLength);
    }

    skip(4); // nLockTime

    var hasSaplingData = false;
    int? valueBalance;
    int? spendCount;
    int? shieldedOutputCount;
    var hasBindingSignature = false;

    if (offset < bytes.length) {
      hasSaplingData = bytes[offset++] != 0;
      if (hasSaplingData) {
        valueBalance = readInt64();
        spendCount = readVarInt();
        skip(spendCount * _saplingSpendDescriptionSize);
        shieldedOutputCount = readVarInt();
        skip(shieldedOutputCount * _saplingOutputDescriptionSize);
        if (spendCount > 0 || shieldedOutputCount > 0 || valueBalance != 0) {
          skip(_saplingBindingSignatureSize);
          hasBindingSignature = true;
        }
      }
    }

    final parseError = offset == bytes.length ? null : 'trailing_bytes';
    return PivxShieldedTransactionDebugSummary(
      byteLength: bytes.length,
      version: version,
      type: type,
      transparentInputCount: inputCount,
      transparentOutputCount: outputCount,
      hasSaplingData: hasSaplingData,
      valueBalance: valueBalance,
      shieldedSpendCount: spendCount,
      shieldedOutputCount: shieldedOutputCount,
      hasBindingSignature: hasBindingSignature,
      parseError: parseError,
    );
  }

  static void _require(List<int> bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      throw const FormatException('truncated PIVX shielded transaction');
    }
  }

  String toLogString() {
    return 'bytes=$byteLength version=${version ?? 'unknown'} '
        'type=${type ?? 'unknown'} vin=${transparentInputCount ?? 'unknown'} '
        'vout=${transparentOutputCount ?? 'unknown'} '
        'sapling=${hasSaplingData ? 'present' : 'absent'} '
        'value_balance=${valueBalance ?? 'unknown'} '
        'shielded_spends=${shieldedSpendCount ?? 'unknown'} '
        'shielded_outputs=${shieldedOutputCount ?? 'unknown'} '
        'binding_sig=${hasBindingSignature ? 'present' : 'absent'} '
        'parse=${parseError ?? 'ok'}';
  }
}

/// Pending transaction wrapper for PIVX Sapling shielded transactions.
///
/// This wraps a [SaplingTransactionResult] to implement the [PendingTransaction]
/// interface, allowing shielded transactions to be treated uniformly with
/// transparent transactions in the wallet UI.
class PendingPivxShieldedTransaction with PendingTransaction {
  PendingPivxShieldedTransaction({
    required this.result,
    required this.electrumClient,
    required this.amount,
    required this.fee,
    this.onCommit,
  }) : _listeners = [];

  /// The result from the Sapling transaction builder containing the signed tx.
  final SaplingTransactionResult result;

  /// The Electrum client for broadcasting.
  final ElectrumClient electrumClient;

  /// The amount being sent in satoshis/zatoshis.
  final int amount;

  /// The transaction fee in satoshis/zatoshis.
  final int fee;

  /// Callback called after successful broadcast.
  final Future<void> Function(dynamic)? onCommit;

  /// Listeners for transaction commit events.
  final List<void Function(dynamic)> _listeners;

  @override
  String get id => result.txId;

  @override
  String get hex => result.txHex;

  @override
  String get amountFormatted => bitcoinAmountToString(amount: amount);

  @override
  String get feeFormatted => "$feeFormattedValue PIVX";

  String get feeFormattedValue => bitcoinAmountToString(amount: fee);

  @override
  int? get outputCount => 1; // Shielded transactions have encrypted outputs

  static String sanitizeBroadcastError(String error) {
    var message = error.trim();
    final lowerMessage = message.toLowerCase();

    const saplingRejections = {
      'bad-txns-sapling-spend-description-invalid':
          'PIVX node rejected the shielded transaction: Sapling spend proof/signature validation failed.',
      'bad-txns-sapling-output-description-invalid':
          'PIVX node rejected the shielded transaction: Sapling output proof validation failed.',
      'bad-txns-sapling-binding-signature-invalid':
          'PIVX node rejected the shielded transaction: Sapling binding signature validation failed.',
      'bad-txns-shielded-requirements-not-met':
          'PIVX node rejected the shielded transaction: Sapling anchor or nullifier requirements were not met.',
      'bad-txns-sapling-requirements-not-met':
          'PIVX node rejected the shielded transaction: Sapling anchor or nullifier requirements were not met.',
      'bad-txns-nullifier-double-spent':
          'PIVX node rejected the shielded transaction: selected shielded note was already spent.',
      'bad-spend-description-nullifiers-duplicate':
          'PIVX node rejected the shielded transaction: duplicate shielded nullifier.',
      'bad-txns-valuebalance-nonzero':
          'PIVX node rejected the shielded transaction: invalid Sapling value balance.',
      'bad-txns-valuebalance-toolarge':
          'PIVX node rejected the shielded transaction: Sapling value balance is too large.',
      'bad-txns-invalid-sapling-act':
          'PIVX node rejected the shielded transaction: Sapling is not active on this chain height.',
      'bad-txns-invalid-sapling':
          'PIVX node rejected the shielded transaction: invalid Sapling transaction form.',
    };

    for (final entry in saplingRejections.entries) {
      if (lowerMessage.contains(entry.key)) {
        return '${entry.value} (${entry.key})';
      }
    }

    message = message
        .replaceAll(RegExp(r'\[[0-9a-fA-F\s]{128,}\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (message.isEmpty) {
      return 'Failed to broadcast shielded transaction';
    }

    const maxLength = 240;
    if (message.length > maxLength) {
      message = '${message.substring(0, maxLength)}...';
    }

    return message;
  }

  /// Add a listener for transaction commit events.
  void addListener(void Function(dynamic) listener) {
    _listeners.add(listener);
  }

  @override
  Future<void> commit() async {
    try {
      int? callId;
      final txSummary = PivxShieldedTransactionDebugSummary.fromHex(hex);
      printV(
          '[PendingPivxShieldedTransaction] Broadcast attempt: ${txSummary.toLogString()}');

      // Broadcast the raw transaction via Electrum
      final txid = await electrumClient.broadcastTransaction(
        transactionRaw: hex,
        network: null, // PIVX network doesn't need to be specified here
        idCallback: (id) => callId = id,
      );

      if (txid.isEmpty) {
        final error =
            callId == null ? '' : electrumClient.getErrorMessage(callId!);
        final message = sanitizeBroadcastError(error);
        printV(
            '[PendingPivxShieldedTransaction] Broadcast failed: $message; ${txSummary.toLogString()}');
        throw BitcoinTransactionCommitFailed(errorMessage: message);
      }

      if (txid.toLowerCase() != id.toLowerCase()) {
        printV('[PendingPivxShieldedTransaction] Broadcast txid mismatch');
        throw BitcoinTransactionCommitFailed(
          errorMessage: 'Broadcast transaction id mismatch',
        );
      }

      // Call the onCommit callback if provided
      if (onCommit != null) {
        await onCommit!(this);
      }

      // Notify listeners
      for (final listener in _listeners) {
        listener(this);
      }
    } on BitcoinTransactionCommitFailed {
      rethrow;
    } catch (e) {
      throw BitcoinTransactionCommitFailed(
        errorMessage: 'Failed to broadcast shielded transaction',
      );
    }
  }

  @override
  Future<Map<String, String>> commitUR() async {
    // UR encoding not supported for shielded transactions yet
    return {};
  }
}
