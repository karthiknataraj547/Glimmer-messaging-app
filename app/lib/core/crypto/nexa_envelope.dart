import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'nexa_crypto_engine.dart';

/// Represents a sealed, zero-knowledge encrypted transmission envelope.
/// 
/// The server can inspect routing metadata (envelopeId, recipientDeviceId, timestamp)
/// but possesses ZERO ability to decrypt the ciphertext or alter the AAD without
/// invalidating the GCM-128 authentication tag.
class NexaEncryptedEnvelope {
  final String envelopeId;
  final String conversationId;
  final String senderNexaId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final int messageType; // 1 = Double Ratchet Message, 2 = X3DH Init, 3 = Ephemeral Sync
  final int sequenceNumber;
  final int timestamp;
  final Uint8List payloadWithIvAndTag;

  const NexaEncryptedEnvelope({
    required this.envelopeId,
    required this.conversationId,
    required this.senderNexaId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.messageType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.payloadWithIvAndTag,
  });

  /// Computes the Associated Authenticated Data (AAD) for this envelope.
  /// 
  /// Binds the routing metadata directly to the AEAD MAC tag, ensuring
  /// that any replay or rerouting to a different conversation/device causes
  /// immediate authentication failure.
  Uint8List computeAad() {
    final rawAad = 'conv:$conversationId|s:$senderNexaId|$senderDeviceId|r:$recipientDeviceId|seq:$sequenceNumber|ts:$timestamp';
    return Uint8List.fromList(utf8.encode(rawAad));
  }

  /// Factory to seal plaintext into an envelope using [key].
  factory NexaEncryptedEnvelope.seal({
    required String conversationId,
    required String senderNexaId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required Uint8List key,
    required String plaintext,
    int messageType = 1,
    int sequenceNumber = 0,
    NexaCryptoEngine? engine,
  }) {
    final crypto = engine ?? NexaCryptoEngine();
    final envelopeId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final tempEnvelope = NexaEncryptedEnvelope(
      envelopeId: envelopeId,
      conversationId: conversationId,
      senderNexaId: senderNexaId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      messageType: messageType,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      payloadWithIvAndTag: Uint8List(0),
    );

    final aad = tempEnvelope.computeAad();
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    final encryptedPayload = crypto.encryptAesGcm(
      key: key,
      plaintext: plaintextBytes,
      aad: aad,
    );

    return NexaEncryptedEnvelope(
      envelopeId: envelopeId,
      conversationId: conversationId,
      senderNexaId: senderNexaId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      messageType: messageType,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      payloadWithIvAndTag: encryptedPayload,
    );
  }

  /// Opens and decrypts the envelope with [key].
  /// 
  /// Throws [NexaCryptoException] if ciphertext or routing headers are altered.
  String open({
    required Uint8List key,
    NexaCryptoEngine? engine,
  }) {
    final crypto = engine ?? NexaCryptoEngine();
    final aad = computeAad();

    final decryptedBytes = crypto.decryptAesGcm(
      key: key,
      packedPayload: payloadWithIvAndTag,
      aad: aad,
    );

    final plaintext = utf8.decode(decryptedBytes);
    NexaCryptoEngine.zeroize(decryptedBytes);
    return plaintext;
  }

  /// Serializes to wire-format JSON.
  Map<String, dynamic> toJson() {
    return {
      'envelope_id': envelopeId,
      'conversation_id': conversationId,
      'sender_nexa_id': senderNexaId,
      'sender_device_id': senderDeviceId,
      'recipient_device_id': recipientDeviceId,
      'message_type': messageType,
      'sequence_number': sequenceNumber,
      'timestamp': timestamp,
      'ciphertext_base64': base64Encode(payloadWithIvAndTag),
    };
  }

  /// Deserializes from wire-format JSON.
  factory NexaEncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return NexaEncryptedEnvelope(
      envelopeId: json['envelope_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderNexaId: json['sender_nexa_id'] as String,
      senderDeviceId: json['sender_device_id'] as String,
      recipientDeviceId: json['recipient_device_id'] as String,
      messageType: json['message_type'] as int,
      sequenceNumber: json['sequence_number'] as int,
      timestamp: json['timestamp'] as int,
      payloadWithIvAndTag: base64Decode(json['ciphertext_base64'] as String),
    );
  }
}
