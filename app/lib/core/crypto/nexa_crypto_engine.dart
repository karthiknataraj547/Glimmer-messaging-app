import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Exception thrown when cryptographic verification or decryption fails.
class NexaCryptoException implements Exception {
  final String message;
  final dynamic cause;
  const NexaCryptoException(this.message, [this.cause]);

  @override
  String toString() => 'NexaCryptoException: $message${cause != null ? " (Cause: $cause)" : ""}';
}

/// Production-grade cryptographic engine for NEXA.
/// 
/// Employs PointyCastle for:
/// - AES-256-GCM AEAD encryption/decryption (128-bit auth tag, 96-bit nonce)
/// - Constant-time comparison to prevent timing side-channel attacks
/// - HKDF-SHA256 for key derivation & ratchet stepping
/// - PBKDF2-HMAC-SHA256 (100,000 iterations) for passphrase/recovery key stretching
/// - Explicit memory zeroization to mitigate memory dumping attacks
/// - CSPRNG seeded with OS hardware entropy
class NexaCryptoEngine {
  static final NexaCryptoEngine _instance = NexaCryptoEngine._internal();
  factory NexaCryptoEngine() => _instance;

  late final SecureRandom _secureRandom;

  NexaCryptoEngine._internal() {
    _initCSPRNG();
  }

  void _initCSPRNG() {
    final fortuna = FortunaRandom();
    final systemRandom = Random.secure();
    final seed = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seed[i] = systemRandom.nextInt(256);
    }
    fortuna.seed(KeyParameter(seed));
    _secureRandom = fortuna;
  }

  /// Generates [count] cryptographically secure random bytes.
  Uint8List generateRandomBytes(int count) {
    return _secureRandom.nextBytes(count);
  }

  /// Generates a standard 256-bit (32-byte) symmetric encryption key.
  Uint8List generateKey256() {
    return generateRandomBytes(32);
  }

  /// Generates a standard 96-bit (12-byte) GCM nonce.
  Uint8List generateNonce96() {
    return generateRandomBytes(12);
  }

  /// Encrypts [plaintext] using AES-256-GCM with Associated Authenticated Data ([aad]).
  /// 
  /// Returns a combined payload: [12-byte IV] + [Ciphertext + 16-byte GCM Tag].
  Uint8List encryptAesGcm({
    required Uint8List key,
    required Uint8List plaintext,
    Uint8List? nonce,
    Uint8List? aad,
  }) {
    if (key.length != 32) {
      throw const NexaCryptoException('AES-256 requires a 32-byte key.');
    }

    final iv = nonce ?? generateNonce96();
    if (iv.length != 12) {
      throw const NexaCryptoException('GCM requires a 12-byte (96-bit) nonce.');
    }

    final associatedData = aad ?? Uint8List(0);

    try {
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(key),
        128, // 128-bit MAC tag
        iv,
        associatedData,
      );
      cipher.init(true, params);

      final encryptedOutput = cipher.process(plaintext);

      // Construct packed envelope: [12 bytes IV] + [encryptedOutput with tag]
      final result = Uint8List(iv.length + encryptedOutput.length);
      result.setRange(0, iv.length, iv);
      result.setRange(iv.length, result.length, encryptedOutput);
      return result;
    } catch (e) {
      throw NexaCryptoException('Encryption failed: ${e.toString()}', e);
    }
  }

  /// Decrypts a packed AES-256-GCM payload ([12-byte IV] + [Ciphertext + Tag]) with [aad].
  Uint8List decryptAesGcm({
    required Uint8List key,
    required Uint8List packedPayload,
    Uint8List? aad,
  }) {
    if (key.length != 32) {
      throw const NexaCryptoException('AES-256 requires a 32-byte key.');
    }
    if (packedPayload.length < 12 + 16) {
      throw const NexaCryptoException('Ciphertext payload is too short to contain valid IV and GCM tag.');
    }

    final iv = Uint8List.sublistView(packedPayload, 0, 12);
    final ciphertextWithTag = Uint8List.sublistView(packedPayload, 12);
    final associatedData = aad ?? Uint8List(0);

    try {
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(key),
        128,
        iv,
        associatedData,
      );
      cipher.init(false, params);

      return cipher.process(ciphertextWithTag);
    } on InvalidCipherTextException catch (e) {
      throw NexaCryptoException('Authentication failed: ciphertext has been tampered with or key is invalid.', e);
    } catch (e) {
      throw NexaCryptoException('Decryption failed: ${e.toString()}', e);
    }
  }

  /// Constant-time memory comparison to protect against timing side-channel attacks.
  static bool fixedTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Computes HMAC-SHA256 of [data] using [key] via PointyCastle.
  Uint8List hmacSha256(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(key));
    return hmac.process(data);
  }

  /// Derives keys using standard RFC 5869 HKDF (Extract and Expand) with SHA-256.
  Uint8List deriveHkdfSha256({
    required Uint8List ikm, // Input Keying Material
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    // 1. HKDF-Extract(salt, IKM) -> PRK
    final actualSalt = salt.isEmpty ? Uint8List(32) : salt;
    final prk = hmacSha256(actualSalt, ikm);

    // 2. HKDF-Expand(PRK, info, length) -> OKM
    final hashLen = 32;
    final n = (length / hashLen).ceil();
    if (n > 255) {
      throw const NexaCryptoException('HKDF-Expand cannot exceed 255 * hashLen bytes.');
    }

    final okm = BytesBuilder();
    var t = Uint8List(0);

    for (int i = 1; i <= n; i++) {
      final input = BytesBuilder();
      input.add(t);
      input.add(info);
      input.addByte(i);
      t = hmacSha256(prk, input.toBytes());
      okm.add(t);
    }

    final fullBytes = okm.toBytes();
    final result = Uint8List.sublistView(fullBytes, 0, length);
    zeroize(prk);
    zeroize(t);
    return result;
  }

  /// Derives a 256-bit master key from a user passphrase or recovery phrase
  /// using PBKDF2 with HMAC-SHA256 and [iterations] (default 100,000 rounds).
  Uint8List deriveMasterKeyFromPassphrase({
    required String passphrase,
    required Uint8List salt,
    int iterations = 100000,
  }) {
    final passBytes = Uint8List.fromList(utf8.encode(passphrase));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, iterations, 32));

    final derived = pbkdf2.process(passBytes);
    zeroize(passBytes);
    return derived;
  }

  /// Overwrites [buffer] with zeros to eradicate sensitive keys from memory.
  static void zeroize(Uint8List buffer) {
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
  }
}
