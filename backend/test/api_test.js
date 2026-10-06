/**
 * Integration Test Suite for NEXA Zero-Knowledge Blind Relay Server
 */

const assert = require('assert');
const { app, server } = require('../server');

const TEST_PORT = 8089;

async function runTests() {
  await new Promise((resolve) => server.listen(TEST_PORT, resolve));
  console.log(`[TEST] Test server listening on :${TEST_PORT}`);

  const baseUrl = `http://localhost:${TEST_PORT}`;

  try {
    // 1. Health Check
    const healthRes = await fetch(`${baseUrl}/health`).then(r => r.json());
    assert.strictEqual(healthRes.status, 'ok');
    assert.strictEqual(healthRes.security_mode, 'zero_knowledge_e2ee');
    console.log('✓ Health check passed');

    // 2. Register Devices for Alice and Bob
    const aliceDevice = {
      nexa_id: 'NX-ALICE-1234',
      device_id: 'dev-alice-phone',
      platform: 'android',
      identity_key_public: 'bmV4YV9hbGljZV9pZGVudGl0eV9wdWJsaWNfa2V5XzMyYg==',
      registration_id: 11001
    };

    const regAlice = await fetch(`${baseUrl}/v1/auth/register-device`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(aliceDevice)
    }).then(r => r.json());
    assert.strictEqual(regAlice.nexa_id, 'NX-ALICE-1234');
    console.log('✓ Alice device registered');

    const bobDevice = {
      nexa_id: 'NX-BOB-5678',
      device_id: 'dev-bob-phone',
      platform: 'ios',
      identity_key_public: 'bmV4YV9ib2JfaWRlbnRpdHlfcHVibGljX2tleV8zMmI=',
      registration_id: 11002
    };

    await fetch(`${baseUrl}/v1/auth/register-device`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(bobDevice)
    });
    console.log('✓ Bob device registered');

    // 3. Upload Prekey Bundle for Bob
    const bobBundle = {
      nexa_id: 'NX-BOB-5678',
      device_id: 'dev-bob-phone',
      registration_id: 11002,
      identity_key_public: bobDevice.identity_key_public,
      signed_prekey_id: 1,
      signed_prekey_public: 'c2lnbmVkX3ByZWtleV9ib2JfMzJi',
      signed_prekey_signature: 'c2lnbmF0dXJlX29mX3NpZ25lZF9wcmVrZXlfNjRi',
      one_time_prekeys: [
        { id: 101, public_key: 'b3BrXzEwMV9wdWJsaWNfa2V5' },
        { id: 102, public_key: 'b3BrXzEwMl9wdWJsaWNfa2V5' }
      ]
    };

    const uploadRes = await fetch(`${baseUrl}/v1/keys/bundle`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(bobBundle)
    }).then(r => r.json());
    assert.strictEqual(uploadRes.opk_count, 2);
    console.log('✓ Prekey bundle uploaded');

    // 4. Alice Fetches Bob's Prekey Bundle (Consumes one OPK)
    const fetchedBundle = await fetch(`${baseUrl}/v1/keys/bundle/NX-BOB-5678/dev-bob-phone`).then(r => r.json());
    assert.strictEqual(fetchedBundle.signed_prekey_id, 1);
    assert.strictEqual(fetchedBundle.one_time_prekey.id, 101);
    assert.strictEqual(fetchedBundle.remaining_opks, 1);
    console.log('✓ Prekey bundle fetched and OPK #101 consumed');

    // 5. Alice Sends Zero-Knowledge Encrypted Envelope to Bob
    const envelope = {
      envelope_id: 'env-uuid-001',
      conversation_id: 'conv-alice-bob',
      sender_nexa_id: 'NX-ALICE-1234',
      sender_device_id: 'dev-alice-phone',
      recipient_device_id: 'dev-bob-phone',
      message_type: 1,
      sequence_number: 0,
      timestamp: Date.now(),
      ciphertext_base64: 'QUVTMjU2R0NNX0NJUEhFUlRFWFRfQU5EX1RBR18xMjgtYml0=='
    };

    const sendRes = await fetch(`${baseUrl}/v1/mailbox/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ envelopes: [envelope] })
    }).then(r => r.json());
    assert.strictEqual(sendRes.mailbox_queued, 1);
    console.log('✓ Envelope blindly queued in mailbox');

    // 6. Bob Pulls Mailbox
    const pullRes = await fetch(`${baseUrl}/v1/mailbox/pull/dev-bob-phone`).then(r => r.json());
    assert.strictEqual(pullRes.pending_envelopes.length, 1);
    assert.strictEqual(pullRes.pending_envelopes[0].envelope_id, 'env-uuid-001');
    console.log('✓ Bob pulled pending envelope');

    // 7. Bob ACKs Envelope -> Purged from Server
    const ackRes = await fetch(`${baseUrl}/v1/mailbox/ack`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        device_id: 'dev-bob-phone',
        acknowledged_envelope_ids: ['env-uuid-001']
      })
    }).then(r => r.json());
    assert.strictEqual(ackRes.purged_count, 1);
    assert.strictEqual(ackRes.remaining_count, 0);
    console.log('✓ Mailbox ACK purged envelope from server memory');

    console.log('\n[PASS] All backend zero-knowledge tests passed successfully!');
  } finally {
    server.close();
  }
}

runTests().catch(err => {
  console.error('[FAIL]', err);
  process.exit(1);
});
