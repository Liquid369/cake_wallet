import 'package:cw_bitcoin/electrum.dart';
import 'package:cw_bitcoin/bitcoin_amount_format.dart';
import 'package:cw_core/pending_transaction.dart';
import 'sapling/sapling_factories.dart' show SaplingTransactionResult;

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

  /// Add a listener for transaction commit events.
  void addListener(void Function(dynamic) listener) {
    _listeners.add(listener);
  }

  @override
  Future<void> commit() async {
    try {
      // Broadcast the raw transaction via Electrum
      final txid = await electrumClient.broadcastTransaction(
        transactionRaw: hex,
        network: null, // PIVX network doesn't need to be specified here
      );
      
      if (txid != id) {
        // This shouldn't happen, but log it if it does
        print('[PendingPivxShieldedTransaction] Warning: broadcast txid $txid differs from computed $id');
      }
      
      // Call the onCommit callback if provided
      if (onCommit != null) {
        await onCommit!(this);
      }
      
      // Notify listeners
      for (final listener in _listeners) {
        listener(this);
      }
    } catch (e) {
      throw Exception('Failed to broadcast shielded transaction: $e');
    }
  }

  @override
  Future<Map<String, String>> commitUR() async {
    // UR encoding not supported for shielded transactions yet
    return {};
  }
}
