import 'package:cake_wallet/utils/payment_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentRequest', () {
    group('Ethereum URIs', () {
      test("extract address and amount from EIP681 Uri with contract", () {
        final uri = Uri.parse(
            "ethereum:0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174@1/transfer?address=0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41&uint256=2000000000000000000");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        expect(paymentRequest.amount, "2");
      });

      test("extract address and amount from EIP681 Uri", () {
        final uri = Uri.parse(
            "ethereum:0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41@1?value=2000000000000000000");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        expect(paymentRequest.amount, "2");
      });

      test("extract address and amount from Cake Style Uri", () {
        final uri = Uri.parse(
            "ethereum:0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41@1?amount=2.00");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        expect(paymentRequest.amount, "2.00");
      });

      test("extract address from EIP681 Uri with contract", () {
        final uri = Uri.parse(
            "ethereum:0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174@1/transfer?address=0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        expect(paymentRequest.amount, "");
      });

      test(
          "extract address and amount from EIP681 Uri with contract and no chainId",
          () {
        final uri = Uri.parse(
            "ethereum:0x1234567890abcdef1234567890abcdef12345678/transfer?address=0xabcdef1234567890abcdef1234567890abcdef12&uint256=1000000000000000000");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xabcdef1234567890abcdef1234567890abcdef12");
        expect(paymentRequest.amount, "1");
      });

      test("extract address from minimal EIP681 Uri", () {
        final uri =
            Uri.parse("ethereum:0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.address,
            "0xCfc1650da7C961FD82998e7e30ca5f699D0aBf41");
        expect(paymentRequest.amount, "");
      });
    });

    group('PIVX URIs', () {
      test('extract address and amount while leaving message as a local note',
          () {
        final uri =
            Uri.parse('pivx:ps1receiveaddress?amount=1.23&message=invoice');
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.scheme, 'pivx');
        expect(paymentRequest.address, 'ps1receiveaddress');
        expect(paymentRequest.amount, '1.23');
        expect(paymentRequest.note, 'invoice');
        expect(paymentRequest.hasUnsupportedParameters, false);
      });

      test('marks memo fields unsupported instead of treating them as notes',
          () {
        final uri = Uri.parse(
            'pivx:ps1receiveaddress?amount=1.23&memo=secret&req-memo=secret');
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.note, '');
        expect(paymentRequest.hasUnsupportedParameters, true);
        expect(paymentRequest.unsupportedParameters,
            containsAll(<String>['memo', 'req-memo']));
      });

      test('marks unknown required PIVX URI fields unsupported', () {
        final uri = Uri.parse('pivx:ps1receiveaddress?req-pool=sapling');
        final paymentRequest = PaymentRequest.fromUri(uri);

        expect(paymentRequest.hasUnsupportedParameters, true);
        expect(paymentRequest.unsupportedParameters, contains('req-pool'));
      });
    });
  });
}
