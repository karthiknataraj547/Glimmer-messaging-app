const http = require('http');

function apiCall(port, method, path, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    let payload = null;
    let finalHeaders = { ...headers };

    if (body !== null) {
      if (Buffer.isBuffer(body)) {
        payload = body;
        finalHeaders['Content-Length'] = body.length;
        if (!finalHeaders['Content-Type'] && !finalHeaders['content-type']) {
          finalHeaders['Content-Type'] = 'application/octet-stream';
        }
      } else {
        payload = JSON.stringify(body);
        finalHeaders['Content-Type'] = finalHeaders['Content-Type'] || 'application/json';
        finalHeaders['Content-Length'] = Buffer.byteLength(payload);
      }
    }

    const req = http.request({
      hostname: '127.0.0.1',
      port,
      path,
      method,
      headers: finalHeaders
    }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        const buffer = Buffer.concat(chunks);
        const str = buffer.toString('utf8');
        try {
          resolve({ status: res.statusCode, headers: res.headers, json: JSON.parse(str), buffer });
        } catch (_) {
          resolve({ status: res.statusCode, headers: res.headers, raw: str, buffer });
        }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function runRegressionSuite() {
  console.log('================================================================');
  console.log('  SECURE MESSAGING PRODUCTION REGRESSION & OBSERVABILITY SUITE  ');
  console.log('================================================================\n');

  let passed = 0;
  let total = 0;

  async function test(name, fn) {
    total++;
    process.stdout.write(`[TEST ${total}] ${name}... `);
    try {
      await fn();
      passed++;
      console.log('PASSED ✓');
    } catch (e) {
      console.log('FAILED ✗');
      console.error('   Error:', e.message);
      throw e;
    }
  }

  // TEST 1: Canonical Direct Conversation Creation & Deduplication
  let convId1 = null;
  await test('Direct conversation creation returns canonical deterministic ID', async () => {
    const res1 = await apiCall(8080, 'POST', '/v1/conversations/direct', {}, {
      user1: 'alice',
      user2: 'bob'
    });
    if (res1.status !== 200 || !res1.json?.conversation?.id) {
      throw new Error(`Failed to create direct conversation: ${JSON.stringify(res1.json)}`);
    }
    convId1 = res1.json.conversation.id;

    // Call again with inverted user order: bob, alice
    const res2 = await apiCall(8080, 'POST', '/v1/conversations/direct', {}, {
      user1: 'bob',
      user2: 'alice'
    });
    if (res2.json?.conversation?.id !== convId1) {
      throw new Error(`Inverted user query returned non-canonical ID: ${res2.json?.conversation?.id} vs ${convId1}`);
    }
  });

  // TEST 2: Canonical Conversations List for User
  await test('User conversations list returns canonical entries without duplicates', async () => {
    const res = await apiCall(8080, 'GET', '/v1/conversations?userId=alice');
    if (res.status !== 200 || !Array.isArray(res.json?.conversations)) {
      throw new Error(`Invalid conversations response: ${JSON.stringify(res.json)}`);
    }
    const matching = res.json.conversations.filter(c => c.id === convId1);
    if (matching.length !== 1) {
      throw new Error(`Expected exactly 1 conversation entry for canonical pair, found: ${matching.length}`);
    }
  });

  // TEST 3: Idempotent Message Ingestion
  const clientMsgId = `cl_test_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
  await test('Message sending persists with clientMessageId deduplication', async () => {
    const res1 = await apiCall(8080, 'POST', '/v1/messages/send', {}, {
      sender_handle: 'alice',
      sender_nexa_id: 'NX-ALICE-1001',
      recipient_handle: 'bob',
      recipient_nexa_id: 'NX-BOB-2002',
      conversation_id: convId1,
      client_message_id: clientMsgId,
      text: 'Encrypted payload test 1'
    });
    if (![200, 201].includes(res1.status) || !res1.json?.success) {
      throw new Error(`Failed to send initial message: ${JSON.stringify(res1.json)}`);
    }

    // Attempt to send duplicate message with same client_message_id
    const res2 = await apiCall(8080, 'POST', '/v1/messages/send', {}, {
      sender_handle: 'alice',
      sender_nexa_id: 'NX-ALICE-1001',
      recipient_handle: 'bob',
      recipient_nexa_id: 'NX-BOB-2002',
      conversation_id: convId1,
      client_message_id: clientMsgId,
      text: 'Encrypted payload test 1 (DUPLICATE)'
    });
    if (![200, 201].includes(res2.status) || !res2.json?.duplicate) {
      throw new Error(`Expected duplicate rejection, received: ${JSON.stringify(res2.json)}`);
    }
  });

  // TEST 4: Conversation History Cursor Pagination
  await test('Paginated messages history loads with membership verification', async () => {
    const res = await apiCall(8080, 'GET', `/v1/conversations/${convId1}/messages?userId=alice&limit=10`);
    if (res.status !== 200 || !Array.isArray(res.json?.messages)) {
      throw new Error(`Failed to fetch paginated messages: ${JSON.stringify(res.json)}`);
    }
    const foundMsg = res.json.messages.find(m => m.client_message_id === clientMsgId || m.text.includes('Encrypted payload test 1'));
    if (!foundMsg) {
      throw new Error('Persisted message not found in conversation messages query');
    }
  });

  // TEST 5: Attachment Upload and Raw Streaming Download
  let uploadedAttachmentId = null;
  await test('Attachment binary upload and streaming download', async () => {
    const sampleBytes = Buffer.from('NEXA_E2EE_ATTACHMENT_VERIFICATION_STREAM_2026', 'utf8');
    const uploadRes = await apiCall(8080, 'POST', '/v1/attachments/upload', {
      'x-file-name': 'sec_payload.dat',
      'x-media-type': 'application/octet-stream'
    }, sampleBytes);

    if (![200, 201].includes(uploadRes.status) || !uploadRes.json?.attachmentId) {
      throw new Error(`Upload failed: ${JSON.stringify(uploadRes.json)}`);
    }
    uploadedAttachmentId = uploadRes.json.attachmentId;

    // Fetch binary stream
    const downloadRes = await apiCall(8080, 'GET', `/v1/attachments/${uploadedAttachmentId}?raw=1`);
    if (downloadRes.status !== 200 || !downloadRes.buffer.equals(sampleBytes)) {
      throw new Error(`Downloaded attachment bytes mismatch: ${downloadRes.raw}`);
    }
  });

  // TEST 6: Real Location Coordinates Transmission & Persistence
  await test('Location coordinates payload transmission and verification', async () => {
    const locClientMsgId = `cl_loc_${Date.now()}`;
    const locRes = await apiCall(8080, 'POST', '/v1/messages/send', {}, {
      sender_handle: 'alice',
      sender_nexa_id: 'NX-ALICE-1001',
      recipient_handle: 'bob',
      recipient_nexa_id: 'NX-BOB-2002',
      conversation_id: convId1,
      client_message_id: locClientMsgId,
      type: 'location',
      text: '📍 Real Location Pin • 37.7749° N, 122.4194° W',
      location_data: {
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 3.5,
        address: 'San Francisco, California'
      }
    });

    if (![200, 201].includes(locRes.status) || !locRes.json?.success) {
      throw new Error(`Location send failed: ${JSON.stringify(locRes.json)}`);
    }

    const histRes = await apiCall(8080, 'GET', `/v1/conversations/${convId1}/messages?userId=bob&limit=5`);
    const locMsg = histRes.json?.messages?.find(m => m.client_message_id === locClientMsgId);
    if (!locMsg || !locMsg.location_data) {
      throw new Error('Location message missing location_data in database record');
    }
    const locObj = typeof locMsg.location_data === 'string' ? JSON.parse(locMsg.location_data) : locMsg.location_data;
    if (Math.abs(locObj.latitude - 37.7749) > 0.0001) {
      throw new Error(`Latitude mismatch: ${locObj.latitude}`);
    }
  });

  // TEST 7: Push Token Registration Pipeline
  await test('Push notification token registration & unregistration', async () => {
    const regRes = await apiCall(8080, 'POST', '/v1/devices/push-token', {}, {
      userId: 'NX-ALICE-1001',
      token: 'fcm_mock_token_reg_test_998127391',
      platform: 'android'
    });
    if (regRes.status !== 200 || !regRes.json?.success) {
      throw new Error(`Push token registration failed: ${JSON.stringify(regRes.json)}`);
    }

    const unregRes = await apiCall(8080, 'DELETE', '/v1/devices/push-token', {}, {
      userId: 'NX-ALICE-1001',
      token: 'fcm_mock_token_reg_test_998127391'
    });
    if (unregRes.status !== 200 || !unregRes.json?.success) {
      throw new Error(`Push token unregistration failed: ${JSON.stringify(unregRes.json)}`);
    }
  });

  // TEST 8: WebRTC Real Signaling & ICE Candidate Relay
  await test('WebRTC session offer, answer, and ICE candidate exchange', async () => {
    const callId = `call_${Date.now()}`;
    const offerRes = await apiCall(8080, 'POST', '/v1/calls/offer', {}, {
      callId,
      callerId: 'NX-ALICE-1001',
      calleeId: 'NX-BOB-2002',
      sdpOffer: 'v=0\r\no=alice 12345 1 IN IP4 127.0.0.1\r\ns=NEXA WebRTC Call'
    });
    if (offerRes.status !== 200 || !offerRes.json?.success) {
      throw new Error(`Call offer failed: ${JSON.stringify(offerRes.json)}`);
    }

    const candRes1 = await apiCall(8080, 'POST', '/v1/calls/candidate', {}, {
      callId,
      fromUserId: 'NX-ALICE-1001',
      candidate: { candidate: 'candidate:1 1 UDP 2122252543 192.168.1.100 54321 typ host', sdpMid: '0', sdpMLineIndex: 0 }
    });
    if (candRes1.status !== 200 || !candRes1.json?.success) {
      throw new Error(`Candidate submission failed: ${JSON.stringify(candRes1.json)}`);
    }

    const fetchCand = await apiCall(8080, 'GET', `/v1/calls/candidates/${callId}`);
    if (fetchCand.status !== 200 || !fetchCand.json?.candidates || fetchCand.json.candidates.length !== 1) {
      throw new Error(`Candidate fetch count mismatch: ${fetchCand.json?.candidates?.length}`);
    }

    const ansRes = await apiCall(8080, 'POST', '/v1/calls/answer', {}, {
      callId,
      sdpAnswer: 'v=0\r\no=bob 67890 1 IN IP4 127.0.0.1\r\ns=NEXA WebRTC Answer'
    });
    if (ansRes.status !== 200 || !ansRes.json?.success) {
      throw new Error(`Call answer failed: ${JSON.stringify(ansRes.json)}`);
    }
  });

  console.log('\n================================================================');
  console.log(`  ALL ${passed} OF ${total} TESTS PASSED SUCCESSFULLY (100% SUCCESS RATE)`);
  console.log('================================================================\n');
}

runRegressionSuite().catch(err => {
  console.error('\nSUITE TERMINATED WITH ERRORS:', err);
  process.exit(1);
});
