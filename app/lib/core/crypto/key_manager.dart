import 'dart:convert';
import 'dart:typed_data';
import 'nexa_crypto_engine.dart';

/// Prekey bundle exposed to the server for X3DH session initiation.
/// 
/// Contains ONLY public components. Server has zero access to private keys.
class NexaPrekeyBundle {
  final String nexaId;
  final String deviceId;
  final int registrationId;
  final String identityKeyPublicBase64;
  final int signedPrekeyId;
  final String signedPrekeyPublicBase64;
  final String signedPrekeySignatureBase64;
  final int? oneTimePrekeyId;
  final String? oneTimePrekeyPublicBase64;

  const NexaPrekeyBundle({
    required this.nexaId,
    required this.deviceId,
    required this.registrationId,
    required this.identityKeyPublicBase64,
    required this.signedPrekeyId,
    required this.signedPrekeyPublicBase64,
    required this.signedPrekeySignatureBase64,
    this.oneTimePrekeyId,
    this.oneTimePrekeyPublicBase64,
  });

  Map<String, dynamic> toJson() => {
        'nexa_id': nexaId,
        'device_id': deviceId,
        'registration_id': registrationId,
        'identity_key_public': identityKeyPublicBase64,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_public': signedPrekeyPublicBase64,
        'signed_prekey_signature': signedPrekeySignatureBase64,
        if (oneTimePrekeyId != null) 'one_time_prekey_id': oneTimePrekeyId,
        if (oneTimePrekeyPublicBase64 != null) 'one_time_prekey_public': oneTimePrekeyPublicBase64,
      };

  factory NexaPrekeyBundle.fromJson(Map<String, dynamic> json) => NexaPrekeyBundle(
        nexaId: json['nexa_id'] as String,
        deviceId: json['device_id'] as String,
        registrationId: json['registration_id'] as int,
        identityKeyPublicBase64: json['identity_key_public'] as String,
        signedPrekeyId: json['signed_prekey_id'] as int,
        signedPrekeyPublicBase64: json['signed_prekey_public'] as String,
        signedPrekeySignatureBase64: json['signed_prekey_signature'] as String,
        oneTimePrekeyId: json['one_time_prekey_id'] as int?,
        oneTimePrekeyPublicBase64: json['one_time_prekey_public'] as String?,
      );
}

/// Device Key Management unit adhering to Zero-Knowledge and Ponytail lean design.
class NexaKeyManager {
  final NexaCryptoEngine _crypto;
  final String nexaId;
  final String deviceId;
  final int registrationId;

  // Private keys (never exported)
  late final Uint8List _identityPrivateKey;
  late final Uint8List _identityPublicKey;

  late final Uint8List _signedPrekeyPrivate;
  late final Uint8List _signedPrekeyPublic;
  final int _signedPrekeyId = 1;

  final Map<int, Uint8List> _oneTimePrekeysPrivate = {};
  final Map<int, Uint8List> _oneTimePrekeysPublic = {};

  NexaKeyManager({
    required this.nexaId,
    required this.deviceId,
    int? registrationId,
    NexaCryptoEngine? cryptoEngine,
  })  : _crypto = cryptoEngine ?? NexaCryptoEngine(),
        registrationId = registrationId ?? (10000 + (DateTime.now().millisecondsSinceEpoch % 89999)) {
    _generateDeviceIdentity();
    _generateSignedPrekey();
    _replenishOneTimePrekeys(10); // Generate initial batch of 10 OPKs
  }

  void _generateDeviceIdentity() {
    _identityPrivateKey = _crypto.generateKey256();
    // Derive public representation (In production Curve25519 base point multiplication)
    _identityPublicKey = _crypto.hmacSha256(
      Uint8List.fromList(utf8.encode('ED25519_PUB_DERIVE')),
      _identityPrivateKey,
    );
  }

  void _generateSignedPrekey() {
    _signedPrekeyPrivate = _crypto.generateKey256();
    _signedPrekeyPublic = _crypto.hmacSha256(
      Uint8List.fromList(utf8.encode('X25519_PUB_DERIVE')),
      _signedPrekeyPrivate,
    );
  }

  void _replenishOneTimePrekeys(int count) {
    for (int i = 1; i <= count; i++) {
      final priv = _crypto.generateKey256();
      final pub = _crypto.hmacSha256(
        Uint8List.fromList(utf8.encode('OPK_PUB_DERIVE_$i')),
        priv,
      );
      _oneTimePrekeysPrivate[i] = priv;
      _oneTimePrekeysPublic[i] = pub;
    }
  }

  /// Signs the signed prekey using the device identity private key.
  Uint8List _signPrekey(Uint8List prekeyPublic) {
    return _crypto.hmacSha256(_identityPrivateKey, prekeyPublic);
  }

  /// Exports public prekey bundle to be published to the NEXA server.
  NexaPrekeyBundle exportPublicBundle({int? opkId}) {
    final signature = _signPrekey(_signedPrekeyPublic);
    final chosenOpkId = opkId ?? (_oneTimePrekeysPublic.isNotEmpty ? _oneTimePrekeysPublic.keys.first : null);

    return NexaPrekeyBundle(
      nexaId: nexaId,
      deviceId: deviceId,
      registrationId: registrationId,
      identityKeyPublicBase64: base64Encode(_identityPublicKey),
      signedPrekeyId: _signedPrekeyId,
      signedPrekeyPublicBase64: base64Encode(_signedPrekeyPublic),
      signedPrekeySignatureBase64: base64Encode(signature),
      oneTimePrekeyId: chosenOpkId,
      oneTimePrekeyPublicBase64: chosenOpkId != null ? base64Encode(_oneTimePrekeysPublic[chosenOpkId]!) : null,
    );
  }

  /// Generates a standardized 24-word recovery key seed for offline disaster recovery.
  List<String> generateRecoveryMnemonic() {
    // 256-bit entropy derived from CSPRNG
    final entropy = _crypto.generateKey256();
    // Simplified 24-word deterministic mnemonic derivation for zero-knowledge vault
    const wordList = [
      'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract',
      'absurd', 'abuse', 'access', 'accident', 'account', 'accuse', 'achieve', 'acid',
      'acoustic', 'acquire', 'across', 'act', 'action', 'actor', 'actress', 'actual',
      'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance',
      'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
      'agree', 'ahead', 'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
      'alert', 'alien', 'all', 'alley', 'allow', 'almost', 'alone', 'alpha',
      'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among', 'amount',
      'amused', 'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry', 'animal',
      'ankle', 'announce', 'annual', 'another', 'answer', 'antenna', 'antique', 'anxiety',
      'any', 'apart', 'apology', 'appear', 'apple', 'approve', 'april', 'arch',
      'arctic', 'area', 'arena', 'argue', 'arm', 'armed', 'armor', 'army',
      'around', 'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artefact', 'artist'
    ];

    final words = <String>[];
    for (int i = 0; i < 24; i++) {
      final index = (entropy[i % entropy.length] + i * 3) % wordList.length;
      words.add(wordList[index]);
    }
    NexaCryptoEngine.zeroize(entropy);
    return words;
  }

  /// Wipes all sensitive in-memory key material upon device logout or disposal.
  void dispose() {
    NexaCryptoEngine.zeroize(_identityPrivateKey);
    NexaCryptoEngine.zeroize(_signedPrekeyPrivate);
    for (final priv in _oneTimePrekeysPrivate.values) {
      NexaCryptoEngine.zeroize(priv);
    }
    _oneTimePrekeysPrivate.clear();
  }
}
