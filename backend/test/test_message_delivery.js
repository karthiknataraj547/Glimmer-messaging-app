const http = require('http');

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port: 8080,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {})
      }
    }, res => {
      let raw = '';
      res.on('data', chunk => raw += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(raw) });
        } catch (_) {
          resolve({ status: res.statusCode, raw });
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function run() {
  console.log('--- 1. Testing with Registered User: karthik_official & harshith_123 ---');
  const user1Res = await request('GET', '/v1/directory/resolve/karthik_official');
  const user2Res = await request('GET', '/v1/directory/resolve/harshith_123');

  const u1 = user1Res.body;
  const u2 = user2Res.body;

  console.log('User 1:', u1.username, 'ID:', u1.user_id, 'Phone:', u1.phone);
  console.log('User 2:', u2.username, 'ID:', u2.user_id, 'Phone:', u2.phone);

  console.log('\n--- 2. Scenario A: Send to User 2 by @username ---');
  const msgA = await request('POST', '/v1/messages/send', {
    sender_handle: u1.username,
    sender_nexa_id: u1.user_id,
    recipient_handle: u2.username,
    recipient_nexa_id: u2.user_id,
    text: 'Msg A: Hello Harshith by username!'
  });
  console.log('Send A status:', msgA.status, msgA.body?.success);

  console.log('\n--- 3. Scenario B: Send to User 2 by NEXA ID only (recipient_handle is the NEXA ID) ---');
  const msgB = await request('POST', '/v1/messages/send', {
    sender_handle: u1.username,
    sender_nexa_id: u1.user_id,
    recipient_handle: u2.user_id, // Typed into ID input: NX-....
    recipient_nexa_id: u2.user_id,
    text: 'Msg B: Hello Harshith by NEXA ID!'
  });
  console.log('Send B status:', msgB.status, msgB.body?.success);

  console.log('\n--- 4. Scenario C: Send Voice Message (audio_path, no text) ---');
  const msgC = await request('POST', '/v1/messages/send', {
    sender_handle: u1.username,
    sender_nexa_id: u1.user_id,
    recipient_handle: u2.username,
    recipient_nexa_id: u2.user_id,
    audio_path: '/cache/voice_note_1.m4a',
    audio_duration: 15,
    type: 'voice'
  });
  console.log('Send C status:', msgC.status, msgC.body?.success);

  console.log('\n--- 5. Verify User 2 Inbox (/v1/messages/inbox/harshith_123) ---');
  const u2Inbox = await request('GET', `/v1/messages/inbox/${u2.username}?nexa_id=${u2.user_id}`);
  console.log('User 2 inbox count:', u2Inbox.body?.count);
  const foundA = u2Inbox.body?.messages?.some(m => m.text?.includes('Msg A'));
  const foundB = u2Inbox.body?.messages?.some(m => m.text?.includes('Msg B'));
  const foundC = u2Inbox.body?.messages?.some(m => m.type === 'voice');
  console.log('User 2 received Msg A (sent by username):', foundA);
  console.log('User 2 received Msg B (sent by NEXA ID):', foundB);
  console.log('User 2 received Msg C (voice note):', foundC);

  console.log('\n--- 6. Verify User 2 Thread by username (/v1/messages/thread/harshith_123/karthik_official) ---');
  const threadByUsername = await request('GET', `/v1/messages/thread/${u2.username}/${u1.username}`);
  console.log('Thread count by username:', threadByUsername.body?.count);

  console.log('\n--- 7. Verify Thread by NEXA IDs (/v1/messages/thread/ID1/ID2) ---');
  const threadById = await request('GET', `/v1/messages/thread/${u1.user_id}/${u2.user_id}`);
  console.log('Thread count by NEXA IDs:', threadById.body?.count);

  console.log('\n--- 8. Verify Cross-Thread: Query with user2 username & user1 NEXA ID ---');
  const crossThread = await request('GET', `/v1/messages/thread/${u2.username}/${u1.user_id}`);
  console.log('Cross-thread count:', crossThread.body?.count);

  if (foundA && foundB && foundC && threadByUsername.body?.count >= 3 && threadById.body?.count >= 3 && crossThread.body?.count >= 3) {
    console.log('\n>>> ALL MESSAGE DELIVERY SCENARIOS PASSED WITH 100% SUCCESS! <<<');
  } else {
    console.error('\n>>> TEST FAILED <<<');
    process.exit(1);
  }
}

run().catch(console.error);
