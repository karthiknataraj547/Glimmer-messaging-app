import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/crypto/nexa_crypto_engine.dart';
import 'package:nexa_app/core/crypto/nexa_envelope.dart';
import 'package:nexa_app/core/crypto/safety_number.dart';
import 'package:nexa_app/core/crypto/double_ratchet.dart';

void main() {
  group('NEXA High-End Cryptographic Security Suite', () {
    late NexaCryptoEngine crypto;

    setUp(() {
      crypto = NexaCryptoEngine();
    });

    test('AES-256-GCM AEAD encryption and decryption with metadata binding', () {
      final key = crypto.generateKey256();
      final plaintext = Uint8List.fromList(utf8.encode('Secret zero-knowledge data'));
      final aad = Uint8List.fromList(utf8.encode('sender:NX-1234|receiver:NX-5678'));

      final ciphertext = crypto.encryptAesGcm(key: key, plaintext: plaintext, aad: aad);
      expect(ciphertext.length, greaterThan(plaintext.length));

      final decrypted = crypto.decryptAesGcm(key: key, packedPayload: ciphertext, aad: aad);
      expect(utf8.decode(decrypted), equals('Secret zero-knowledge data'));

      // Test AAD tampering causes rejection
      final tamperedAad = Uint8List.fromList(utf8.encode('sender:NX-1234|receiver:NX-HACK'));
      expect(
        () => crypto.decryptAesGcm(key: key, packedPayload: ciphertext, aad: tamperedAad),
        throwsA(isA<NexaCryptoException>()),
      );
    });

    test('Safety Number computation is deterministic and detects MITM', () {
      final aliceKey = crypto.generateRandomBytes(32);
      final bobKey = crypto.generateRandomBytes(32);
      final malloryKey = crypto.generateRandomBytes(32);

      final safetyNumAlice = SafetyNumber.compute(
        userANexaId: 'NX-7K4M-29QP',
        userAPublicKey: aliceKey,
        userBNexaId: 'NX-9B1D-84ZT',
        userBPublicKey: bobKey,
      );

      final safetyNumBob = SafetyNumber.compute(
        userANexaId: 'NX-9B1D-84ZT',
        userAPublicKey: bobKey,
        userBNexaId: 'NX-7K4M-29QP',
        userBPublicKey: aliceKey,
      );

      // Both sides must arrive at the exact same 60-digit number regardless of argument order
      expect(safetyNumAlice.formattedNumber, equals(safetyNumBob.formattedNumber));
      expect(safetyNumAlice.formattedNumber.split(' ').length, equals(12));

      // Mallory MITM substitution produces a completely distinct safety number
      final safetyNumMitm = SafetyNumber.compute(
        userANexaId: 'NX-7K4M-29QP',
        userAPublicKey: aliceKey,
        userBNexaId: 'NX-9B1D-84ZT',
        userBPublicKey: malloryKey,
      );
      expect(safetyNumAlice.formattedNumber, isNot(equals(safetyNumMitm.formattedNumber)));
    });

    test('Double Ratchet Session simulates complete bidirectional E2E conversation', () {
      final sharedSecret = crypto.generateKey256();

      // Alice (Initiator)
      final alice = DoubleRatchetSession(
        conversationId: 'conv-101',
        localNexaId: 'NX-ALICE',
        localDeviceId: 'device-alice-phone',
        peerNexaId: 'NX-BOB',
        peerDeviceId: 'device-bob-phone',
        initialSharedSecret: sharedSecret,
        isInitiator: true,
      );

      // Bob (Recipient)
      final bob = DoubleRatchetSession(
        conversationId: 'conv-101',
        localNexaId: 'NX-BOB',
        localDeviceId: 'device-bob-phone',
        peerNexaId: 'NX-ALICE',
        peerDeviceId: 'device-alice-phone',
        initialSharedSecret: sharedSecret,
        isInitiator: false,
      );

      // 1. Alice sends message to Bob
      const msg1 = 'Hey Bob, let us test zero-knowledge encryption!';
      final envelope1 = alice.encryptMessage(msg1);

      expect(envelope1.senderNexaId, equals('NX-ALICE'));
      expect(envelope1.recipientDeviceId, equals('device-bob-phone'));

      final receivedByBob1 = bob.decryptMessage(envelope1);
      expect(receivedByBob1, equals(msg1));

      // 2. Bob replies to Alice
      const msg2 = 'Decrypted successfully! Replying under ratcheted key.';
      final envelope2 = bob.encryptMessage(msg2);
      final receivedByAlice2 = alice.decryptMessage(envelope2);
      expect(receivedByAlice2, equals(msg2));

      // 3. Multi-turn messaging
      const msg3 = 'Third message in ratcheted sequence.';
      final envelope3 = alice.encryptMessage(msg3);
      final receivedByBob3 = bob.decryptMessage(envelope3);
      expect(receivedByBob3, equals(msg3));

      // 4. Tampered envelope rejection
      final tamperedPayload = Uint8List.fromList(envelope3.payloadWithIvAndTag);
      tamperedPayload[15] ^= 0x55; // flip bit in ciphertext
      final tamperedEnvelope = NexaEncryptedEnvelope(
        envelopeId: 'fake-id',
        conversationId: envelope3.conversationId,
        senderNexaId: envelope3.senderNexaId,
        senderDeviceId: envelope3.senderDeviceId,
        recipientDeviceId: envelope3.recipientDeviceId,
        messageType: envelope3.messageType,
        sequenceNumber: 99,
        timestamp: envelope3.timestamp,
        payloadWithIvAndTag: tamperedPayload,
      );

      expect(() => bob.decryptMessage(tamperedEnvelope), throwsA(isA<NexaCryptoException>()));

      alice.close();
      bob.close();
    });
  });
}
