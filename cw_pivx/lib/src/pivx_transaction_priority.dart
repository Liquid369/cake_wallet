import 'package:cw_bitcoin/bitcoin_transaction_priority.dart';

/// PIVX transaction priority levels.
/// 
/// Fee calculation based on PIVX Core specifications:
/// - minRelayTxFee: 10000 satoshis/kB
/// - dustRelayFee: 30000 satoshis/kB
/// 
/// PIVX uses similar fee structure to Bitcoin but with different defaults.
/// Standard transaction fee = feeRate * txSize
/// Shielded transactions require 100x the minimum relay fee.
class PivxTransactionPriority extends BitcoinTransactionPriority {
  const PivxTransactionPriority({required String title, required int raw})
      : super(title: title, raw: raw);

  static const List<PivxTransactionPriority> all = [fast, medium, slow];
  
  static const PivxTransactionPriority slow =
      PivxTransactionPriority(title: 'Slow', raw: 0);
  static const PivxTransactionPriority medium =
      PivxTransactionPriority(title: 'Medium', raw: 1);
  static const PivxTransactionPriority fast =
      PivxTransactionPriority(title: 'Fast', raw: 2);

  static PivxTransactionPriority deserialize({required int raw}) {
    switch (raw) {
      case 0:
        return slow;
      case 1:
        return medium;
      case 2:
        return fast;
      default:
        throw Exception('Unexpected token: $raw for PivxTransactionPriority deserialize');
    }
  }

  @override
  String get units => 'sat/kB';

  @override
  String toString() {
    var label = '';

    switch (this) {
      case PivxTransactionPriority.slow:
        label = 'Slow';
        break;
      case PivxTransactionPriority.medium:
        label = 'Medium';
        break;
      case PivxTransactionPriority.fast:
        label = 'Fast';
        break;
      default:
        break;
    }

    return label;
  }
  
  /// Get the fee rate in satoshis per kB for this priority level.
  /// 
  /// Based on PIVX Core's minRelayTxFee of 10000 sat/kB:
  /// - Slow: 10000 sat/kB (minimum relay fee)
  /// - Medium: 20000 sat/kB (2x minimum)
  /// - Fast: 50000 sat/kB (5x minimum for priority)
  int get feeRate {
    switch (this) {
      case PivxTransactionPriority.slow:
        return 10000; // minRelayTxFee
      case PivxTransactionPriority.medium:
        return 20000;
      case PivxTransactionPriority.fast:
        return 50000;
      default:
        return 10000;
    }
  }
}
