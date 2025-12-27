# PIVX Wallet Integration for Cake Wallet

This package provides PIVX wallet functionality for Cake Wallet.

## Features

- BIP39/BIP44 HD wallet with PIVX coin type 119
- P2PKH address generation (addresses starting with 'D')
- ElectrumX backend integration
- Transaction creation and signing
- Balance tracking

## PIVX-Specific Details

### Network Parameters (from PIVX Core)

- **Coin Type (SLIP-44):** 119
- **Derivation Path:** m/44'/119'/account'/change/index
- **P2PKH Prefix:** 30 (addresses start with 'D')
- **P2SH Prefix:** 13 (addresses start with '8')
- **Staking Prefix:** 63 (addresses start with 'S')
- **WIF Prefix:** 212
- **P2P Port:** 51472
- **RPC Port:** 51473
- **Block Time:** 60 seconds
- **Coinbase Maturity:** 100 blocks

### Transaction Types

PIVX has three main transaction types:
1. **Regular transactions** - Standard P2PKH transfers
2. **Coinbase transactions** - Block rewards (single null input)
3. **Coinstake transactions** - Proof-of-stake rewards (first output is empty)

### Future Enhancements

- Cold staking support (addresses starting with 'S')
- Sapling shielded transactions (addresses starting with 'ps')
- Masternode support

## References

- [PIVX Core](https://github.com/PIVX-Project/PIVX)
- [SLIP-0044](https://github.com/satoshilabs/slips/blob/master/slip-0044.md)
