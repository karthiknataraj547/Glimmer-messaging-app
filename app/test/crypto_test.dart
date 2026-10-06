import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('PointyCastle AES-256-GCM authenticated encryption and decryption', () {
    // 1. Setup CSPRNG
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seed = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seed[i] = seedSource.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    // 2. Generate 256-bit AES key & 96-bit IV
    final keyBytes = secureRandom.nextBytes(32);
    final ivBytes = secureRandom.nextBytes(12);
    const plaintext = 'NEXA Zero-Knowledge Confidential Message';
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final aad = Uint8List.fromList(utf8.encode('sender:NX-7K4M;recipient:NX-9B1D'));

    // 3. Encrypt with GCM
    final gcmCipher = GCMBlockCipher(AESEngine());
    final aeadParams = AEADParameters(
      KeyParameter(keyBytes),
      128, // 128-bit MAC tag
      ivBytes,
      aad,
    );
    gcmCipher.init(true, aeadParams); // true = encrypt

    final ciphertext = gcmCipher.process(plaintextBytes);
    expect(ciphertext.isNotEmpty, true);
    expect(ciphertext, isNot(equals(plaintextBytes)));

    // 4. Decrypt with GCM
    final decryptCipher = GCMBlockCipher(AESEngine());
    decryptCipher.init(false, aeadParams); // false = decrypt
    final decryptedBytes = decryptCipher.process(ciphertext);
    final decryptedText = utf8.decode(decryptedBytes);

    expect(decryptedText, equals(plaintext));

    // 5. Tampering test: ensure tampered ciphertext fails authentication
    final tamperedCiphertext = Uint8List.fromList(ciphertext);
    tamperedCiphertext[0] ^= 0x01; // flip one bit

    final tamperedCipher = GCMBlockCipher(AESEngine());
    tamperedCipher.init(false, aeadParams);
    expect(() => tamperedCipher.process(tamperedCiphertext), throwsA(isA<InvalidCipherTextException>()));
  });
}
