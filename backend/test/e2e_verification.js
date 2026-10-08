const http = require('http');

function apiCall(port, method, path, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
        ...headers
      }
    }, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, json: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function testAll() {
  console.log('=== NEXA E2E VERIFICATION SUITE ===\n');

  // 1. Directory Search / NEXA ID Servicing Lookup
  console.log('1. Testing Directory Lookup (NEXA ID & handle search)...');
  const lookup1 = await apiCall(8080, 'GET', '/v1/users/lookup?q=admin');
  console.log('   Lookup "admin" status:', lookup1.status, 'users count:', lookup1.json?.users?.length);
  if (!lookup1.json?.users?.length) throw new Error('Directory lookup failed');

  // 2. Bidirectional Messaging: User A -> User B
  console.log('\n2. Testing Message Send (User A -> User B)...');
  const sendRes = await apiCall(8080, 'POST', '/v1/messages/send', {}, {
    sender_handle: 'alice',
    sender_nexa_id: 'NX-ALICE-1001',
    recipient_handle: 'bob',
    recipient_nexa_id: 'NX-BOB-2002',
    text: 'Hey Bob, checking in via NEXA encrypted relay!',
    type: 'text'
  });
  console.log('   Message send status:', sendRes.status, 'success:', sendRes.json?.success);
  if (!sendRes.json?.success) throw new Error('Message sending failed');

  // 3. User B retrieving Thread
  console.log('\n3. Testing Thread Retrieval (Alice <-> Bob)...');
  const threadRes = await apiCall(8080, 'GET', '/v1/messages/thread/alice/bob');
  console.log('   Thread messages count:', threadRes.json?.count);
  const found = threadRes.json?.messages?.some(m => m.text.includes('Hey Bob'));
  console.log('   Message present in bidirectional thread:', found);
  if (!found) throw new Error('Message not found in conversation thread');

  // 4. User B checking Inbox
  console.log('\n4. Testing Recipient Inbox Pull (Bob)...');
  const inboxRes = await apiCall(8080, 'GET', '/v1/messages/inbox/bob');
  console.log('   Bob inbox count:', inboxRes.json?.count);
  const inInbox = inboxRes.json?.messages?.some(m => m.text.includes('Hey Bob'));
  console.log('   Message received in Bob inbox:', inInbox);
  if (!inInbox) throw new Error('Message not found in recipient inbox');

  // 5. In-App Update Engine: Check current version
  console.log('\n5. Testing In-App Update Engine Check...');
  const checkVer1 = await apiCall(8080, 'GET', '/v1/app/check-update');
  console.log('   Server version:', checkVer1.json?.latest_version, 'build:', checkVer1.json?.build_number);

  // 6. Admin Pushing a New Release (v1.0.3+4)
  console.log('\n6. Testing Admin Update Push (v1.0.3+4)...');
  const pushRes = await apiCall(8081, 'POST', '/v1/admin/app/push-update', {
    'x-admin-master-key': 'nexa_admin_master_secret_2026'
  }, {
    latest_version: '1.0.3',
    build_number: 4,
    release_date: '2026-10-08',
    release_notes: 'Real device contacts sync, peer ID servicing option, real-time message delivery enhancements, and security upgrades.',
    download_url: 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk',
    web_url: 'https://glimmer-messaging-app-web.vercel.app/',
    mandatory: false
  });
  console.log('   Update push status:', pushRes.status, 'message:', pushRes.json?.message);
  if (!pushRes.json?.success) throw new Error('Update push failed');

  // 7. Verify Client receives new update
  console.log('\n7. Verifying Client Update Detection...');
  const checkVer2 = await apiCall(8080, 'GET', '/v1/app/check-update');
  console.log('   New server version:', checkVer2.json?.latest_version, 'build:', checkVer2.json?.build_number);
  if (checkVer2.json?.latest_version !== '1.0.3' || checkVer2.json?.build_number !== 4) {
    throw new Error('Update verification failed');
  }

  console.log('\n=== ALL E2E VERIFICATIONS PASSED SUCCESSFULLY ===');
}

testAll().catch(e => {
  console.error('\nE2E VERIFICATION FAILED:', e);
  process.exit(1);
});
