import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcloud/services/pairing_repository.dart';

void main() {
  group('PairingRepository unit tests', () {
    test('generateRandomCode produces 12 character uppercase alphanumeric code', () {
      final code1 = PairingRepository.generateRandomCode();
      final code2 = PairingRepository.generateRandomCode();

      expect(code1.length, equals(12));
      expect(code2.length, equals(12));
      expect(code1, isNot(equals(code2)));
      expect(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$').hasMatch(code1), isTrue);
    });

    test('PairingCodeInfo expiry calculations work correctly', () {
      final futureExpiry = DateTime.now().toUtc().add(const Duration(minutes: 5));
      final info = PairingCodeInfo(
        plaintextCode: 'TESTCODE1234',
        serverDeviceId: 'server-id-123',
        expiresAt: futureExpiry,
        canUpload: true,
      );

      expect(info.isExpired, isFalse);
      expect(info.remainingTime.inSeconds, greaterThan(0));

      final pastExpiry = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
      final expiredInfo = PairingCodeInfo(
        plaintextCode: 'TESTCODE1234',
        serverDeviceId: 'server-id-123',
        expiresAt: pastExpiry,
        canUpload: false,
      );

      expect(expiredInfo.isExpired, isTrue);
      expect(expiredInfo.remainingTime, equals(Duration.zero));
    });
  });
}
