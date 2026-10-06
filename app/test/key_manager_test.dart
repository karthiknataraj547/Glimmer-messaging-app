import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/crypto/key_manager.dart';

void main() {
  test('NexaKeyManager generates valid public prekey bundles and 24-word recovery seeds', () {
    final keyManager = NexaKeyManager(
      nexaId: 'NX-7K4M-29QP',
      deviceId: 'dev-pixel-8-pro',
    );

    final bundle = keyManager.exportPublicBundle();
    expect(bundle.nexaId, equals('NX-7K4M-29QP'));
    expect(bundle.deviceId, equals('dev-pixel-8-pro'));
    expect(bundle.identityKeyPublicBase64.isNotEmpty, true);
    expect(bundle.signedPrekeyPublicBase64.isNotEmpty, true);
    expect(bundle.signedPrekeySignatureBase64.isNotEmpty, true);
    expect(bundle.oneTimePrekeyPublicBase64, isNotNull);

    // Verify recovery mnemonic
    final mnemonic = keyManager.generateRecoveryMnemonic();
    expect(mnemonic.length, equals(24));
    for (final word in mnemonic) {
      expect(word.isNotEmpty, true);
    }

    // Verify serialization roundtrip
    final json = bundle.toJson();
    final reconstructed = NexaPrekeyBundle.fromJson(json);
    expect(reconstructed.nexaId, equals(bundle.nexaId));
    expect(reconstructed.deviceId, equals(bundle.deviceId));
    expect(reconstructed.identityKeyPublicBase64, equals(bundle.identityKeyPublicBase64));

    keyManager.dispose();
  });
}
