import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic Safety Number generator and verifier.
/// 
/// Allows users to verify identity keys out-of-band (via QR code or visual inspection)
/// to detect and eliminate any Man-in-the-Middle (MITM) attacks.
class SafetyNumber {
  final String formattedNumber;
  final String qrPayload;

  const SafetyNumber({
    required this.formattedNumber,
    required this.qrPayload,
  });

  /// Computes the safety number for two users given their identity public keys and NEXA IDs.
  static SafetyNumber compute({
    required String userANexaId,
    required Uint8List userAPublicKey,
    required String userBNexaId,
    required Uint8List userBPublicKey,
  }) {
    // Sort deterministically by NEXA ID so both users calculate identical numbers
    final isAFirst = userANexaId.compareTo(userBNexaId) <= 0;
    final firstId = isAFirst ? userANexaId : userBNexaId;
    final secondId = isAFirst ? userBNexaId : userANexaId;
    final firstKey = isAFirst ? userAPublicKey : userBPublicKey;
    final secondKey = isAFirst ? userBPublicKey : userAPublicKey;

    // Concatenate sorted parameters
    final buffer = BytesBuilder();
    buffer.add(utf8.encode('NEXA_SAFETY_NUM_V1:'));
    buffer.add(utf8.encode(firstId));
    buffer.add(firstKey);
    buffer.add(utf8.encode(secondId));
    buffer.add(secondKey);

    // Iterative hashing (512 rounds of SHA-512 for stretching)
    var currentHash = sha512.convert(buffer.toBytes()).bytes;
    for (int i = 0; i < 512; i++) {
      currentHash = sha512.convert(currentHash).bytes;
    }

    // Extract 60 digits from the hash digest
    final bufferDigits = StringBuffer();
    for (int i = 0; i < 30; i++) {
      final value = (currentHash[i * 2] << 8) | currentHash[i * 2 + 1];
      final fiveDigits = (value % 100000).toString().padLeft(5, '0');
      bufferDigits.write(fiveDigits);
      if (bufferDigits.length >= 60) break;
    }

    final digitsStr = bufferDigits.toString().substring(0, 60);

    // Format into 12 blocks of 5 digits
    final blocks = <String>[];
    for (int i = 0; i < 12; i++) {
      blocks.add(digitsStr.substring(i * 5, (i + 1) * 5));
    }
    final formatted = blocks.join(' ');

    final qrString = 'nexa-safety://$firstId/$secondId?fp=${base64UrlEncode(currentHash.sublist(0, 32))}';

    return SafetyNumber(
      formattedNumber: formatted,
      qrPayload: qrString,
    );
  }

  /// Verifies if another party's scanned QR matches this safety number.
  bool verifyQr(String scannedQr) {
    return scannedQr.trim() == qrPayload.trim();
  }
}
