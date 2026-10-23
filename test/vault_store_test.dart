import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcloud/services/vault_store.dart';

void main() {
  group('VaultStore.safeName', () {
    final store = VaultStore();

    test('strips path components before accepting a filename', () {
      expect(store.safeName('../private.txt'), 'private.txt');
      expect(store.safeName(r'..\\private.txt'), 'private.txt');
    });

    test('replaces control characters and traversal sequences', () {
      expect(store.safeName('bad\u0000name..txt'), 'bad_name_txt');
    });

    test('rejects an empty filename', () {
      expect(() => store.safeName('  '), throwsFormatException);
    });

    test('bounds excessively long names', () {
      final result = store.safeName('${'a' * 220}.txt');
      expect(result.length, 180);
    });
  });
}
