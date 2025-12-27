import 'package:flutter_test/flutter_test.dart';
import 'package:cw_pivx/src/pivx_network.dart';

void main() {
  group('PivxNetwork', () {
    test('mainnet has correct prefixes', () {
      expect(PivxNetwork.mainnet.p2pkhNetVer, [30]);
      expect(PivxNetwork.mainnet.p2shNetVer, [13]);
      expect(PivxNetwork.mainnet.wifNetVer, [212]);
      expect(PivxNetwork.coinType, 119);
    });

    test('testnet has correct prefixes', () {
      expect(PivxNetwork.testnet.p2pkhNetVer, [139]);
      expect(PivxNetwork.testnet.p2shNetVer, [19]);
      expect(PivxNetwork.testnet.wifNetVer, [239]);
      expect(PivxNetwork.coinType, 119);
    });

    test('mainnet has correct network parameters', () {
      expect(PivxNetwork.defaultPort, 51472);
      expect(PivxNetwork.rpcPort, 51473);
      expect(PivxNetwork.coinbaseMaturity, 100);
      expect(PivxNetwork.targetBlockTime, 60);
      expect(PivxNetwork.minRelayTxFee, 10000);
    });

    test('isValidAddress validates correctly', () {
      // Valid P2PKH address (starts with D)
      expect(PivxNetwork.isValidAddress('D'), false); // Too short
      
      // Valid staking address (starts with S)
      // Note: Full validation requires proper base58 check
      
      // Invalid addresses
      expect(PivxNetwork.isValidAddress(''), false);
      expect(PivxNetwork.isValidAddress('1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2'), false);
    });
  });
}
