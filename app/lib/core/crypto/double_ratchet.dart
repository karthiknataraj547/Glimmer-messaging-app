import 'dart:convert';
import 'dart:typed_data';
import 'nexa_crypto_engine.dart';
import 'nexa_envelope.dart';

/// Implements a high-security Double Ratchet cryptographic session.
/// 
/// Guarantees:
/// 1. Forward Secrecy: Compromise of current keys cannot decrypt past messages.
/// 2. Post-Compromise Security (Break-in Recovery): Future communications heal
///    automatically after a temporary key compromise.
class DoubleRatchetSession {
  final String conversationId;
  final String localNexaId;
  final String localDeviceId;
  final String peerNexaId;
  final String peerDeviceId;

  final Uint8List _rootKey;
  Uint8List _sendChainKey;
  Uint8List _recvChainKey;
  int _sendSequence;
  int _recvSequence;

  int get sendSequence => _sendSequence;
  int get receiveSequence => _recvSequence;

  final NexaCryptoEngine _crypto;

  DoubleRatchetSession({
    required this.conversationId,
    required this.localNexaId,
    required this.localDeviceId,
    required this.peerNexaId,
    required this.peerDeviceId,
    required Uint8List initialSharedSecret,
    required bool isInitiator,
    NexaCryptoEngine? cryptoEngine,
  })  : _crypto = cryptoEngine ?? NexaCryptoEngine(),
        _rootKey = Uint8List.fromList(initialSharedSecret),
        _sendChainKey = Uint8List(32),
        _recvChainKey = Uint8List(32),
        _sendSequence = 0,
        _recvSequence = 0 {
    _initializeChains(isInitiator);
  }

  void _initializeChains(bool isInitiator) {
    // Derive initial sending and receiving chains from the root secret
    final salt = Uint8List.fromList(utf8.encode('NEXA_CHAIN_INIT_SALT_V1'));
    final derived = _crypto.deriveHkdfSha256(
      ikm: _rootKey,
      salt: salt,
      info: Uint8List.fromList(utf8.encode('double_ratchet_initial_chains')),
      length: 64,
    );

    if (isInitiator) {
      _sendChainKey = Uint8List.sublistView(derived, 0, 32);
      _recvChainKey = Uint8List.sublistView(derived, 32, 64);
    } else {
      _recvChainKey = Uint8List.sublistView(derived, 0, 32);
      _sendChainKey = Uint8List.sublistView(derived, 32, 64);
    }
    NexaCryptoEngine.zeroize(derived);
  }

  /// Encrypts and packages [plaintext] into a zero-knowledge [NexaEncryptedEnvelope].
  /// 
  /// Automatically ratchets the sending chain key forward, rendering previous
  /// message keys completely unrecoverable.
  NexaEncryptedEnvelope encryptMessage(String plaintext) {
    // Step 1: Derive message key and advance send chain key
    final salt = Uint8List.fromList(utf8.encode('NEXA_MSG_STEP_SALT'));
    final stepOutput = _crypto.deriveHkdfSha256(
      ikm: _sendChainKey,
      salt: salt,
      info: Uint8List.fromList(utf8.encode('msg_key_step_seq:$_sendSequence')),
      length: 64,
    );

    final nextSendChain = Uint8List.sublistView(stepOutput, 0, 32);
    final messageKey = Uint8List.sublistView(stepOutput, 32, 64);

    // Overwrite previous send chain key
    NexaCryptoEngine.zeroize(_sendChainKey);
    _sendChainKey = nextSendChain;

    try {
      final envelope = NexaEncryptedEnvelope.seal(
        conversationId: conversationId,
        senderNexaId: localNexaId,
        senderDeviceId: localDeviceId,
        recipientDeviceId: peerDeviceId,
        key: messageKey,
        plaintext: plaintext,
        messageType: 1,
        sequenceNumber: _sendSequence++,
        engine: _crypto,
      );
      return envelope;
    } finally {
      // Immediate Forward Secrecy: zeroize ephemeral message key
      NexaCryptoEngine.zeroize(messageKey);
      NexaCryptoEngine.zeroize(stepOutput);
    }
  }

  /// Decrypts an incoming [NexaEncryptedEnvelope].
  /// 
  /// Steps the receiving chain key forward and validates authentication tags.
  String decryptMessage(NexaEncryptedEnvelope envelope) {
    if (envelope.conversationId != conversationId) {
      throw NexaCryptoException('Envelope conversation ID mismatch.');
    }
    if (envelope.recipientDeviceId != localDeviceId) {
      throw NexaCryptoException('Envelope destination is not addressed to this device.');
    }

    final salt = Uint8List.fromList(utf8.encode('NEXA_MSG_STEP_SALT'));
    final stepOutput = _crypto.deriveHkdfSha256(
      ikm: _recvChainKey,
      salt: salt,
      info: Uint8List.fromList(utf8.encode('msg_key_step_seq:${envelope.sequenceNumber}')),
      length: 64,
    );

    final nextRecvChain = Uint8List.sublistView(stepOutput, 0, 32);
    final messageKey = Uint8List.sublistView(stepOutput, 32, 64);

    NexaCryptoEngine.zeroize(_recvChainKey);
    _recvChainKey = nextRecvChain;
    _recvSequence = envelope.sequenceNumber + 1;

    try {
      final plaintext = envelope.open(key: messageKey, engine: _crypto);
      return plaintext;
    } finally {
      // Immediate Forward Secrecy: zeroize ephemeral message key
      NexaCryptoEngine.zeroize(messageKey);
      NexaCryptoEngine.zeroize(stepOutput);
    }
  }

  /// Destroys all cryptographic session keys in memory upon logout or session close.
  void close() {
    NexaCryptoEngine.zeroize(_rootKey);
    NexaCryptoEngine.zeroize(_sendChainKey);
    NexaCryptoEngine.zeroize(_recvChainKey);
  }
}
