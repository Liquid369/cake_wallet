/// Types of unspent outputs for coins with multiple pools.
/// 
/// Used by:
/// - Litecoin: mweb (MWEB shielded), nonMweb (transparent), any
/// - PIVX: sapling (Sapling shielded), transparent, any
enum UnspentCoinType { 
  /// MWEB shielded outputs (Litecoin)
  mweb, 
  /// Non-MWEB outputs (Litecoin transparent)
  nonMweb, 
  /// Sapling shielded notes (PIVX)
  sapling,
  /// Transparent UTXOs (PIVX)
  transparent,
  /// Any type of output
  any 
}