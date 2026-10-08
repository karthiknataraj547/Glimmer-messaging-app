const http = require('http');

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({
      hostname: 'localhost',
      port: 8080,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {})
      }
    }, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(b) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: b });
        }
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

async function run() {
  console.log('1. Lookup users with "admin":');
  console.log(await req('GET', '/v1/users/lookup?q=admin'));

  console.log('\n2. Send message from admin to test_peer:');
  const sendRes = await req('POST', '/v1/messages/send', {
    sender_handle: 'admin',
    sender_nexa_id: 'NX-0000-ADMN',
    recipient_handle: 'test_peer',
    recipient_nexa_id: 'NX-1111-2222',
    text: 'Hello from Sovereign Admin!'
  });
  console.log(sendRes);

  console.log('\n3. Get thread between admin and test_peer:');
  console.log(await req('GET', '/v1/messages/thread/admin/test_peer'));

  console.log('\n4. Check App Update:');
  console.log(await req('GET', '/v1/app/check-update'));
}

run();
