const http = require('http');

function req(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'localhost',
      port: 8080,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };
    const r = http.request(opts, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    r.on('error', reject);
    if (body) r.write(JSON.stringify(body));
    r.end();
  });
}

async function testAll() {
  console.log('--- Testing New Endpoints on Port 8080 ---');

  // 1. Telemetry Location
  const locRes = await req('POST', '/v1/users/telemetry/location', {
    username: 'test_karthik',
    handle: '@test_karthik',
    nexa_id: 'NX-TEST-001',
    full_name: 'Karthik N',
    latitude: 12.9716,
    longitude: 77.5946,
    accuracy: 4.5,
    altitude: 920.0,
    address: 'Bangalore Tech Park'
  });
  console.log('1. Location Telemetry:', locRes.status, locRes.data.success ? 'PASS' : 'FAIL');

  // Admin login
  const loginRes = await req('POST', '/v1/admin/login', {
    adminKey: '123456'
  });
  const token = loginRes.data.token;
  const authHeaders = { 'Authorization': `Bearer ${token}` };
  console.log('2. Admin Login:', loginRes.status, token ? 'PASS' : 'FAIL');

  // 3. Admin Locations
  const adminLocs = await req('GET', '/v1/admin/locations', null, authHeaders);
  console.log('3. Admin Locations:', adminLocs.status, adminLocs.data.count > 0 ? 'PASS' : 'FAIL');

  // 4. Admin Retention Policy
  const retPol = await req('GET', '/v1/admin/retention-policy', null, authHeaders);
  console.log('4. Retention Policy GET:', retPol.status, 'Hours:', retPol.data.retention_hours);

  // 5. Update Retention Policy
  const setPol = await req('POST', '/v1/admin/retention-policy', { hours: 168 }, authHeaders);
  console.log('5. Retention Policy POST:', setPol.status, setPol.data.retention_hours === 168 ? 'PASS' : 'FAIL');

  // 6. Purge Delivered
  const purgeRes = await req('POST', '/v1/admin/purge-delivered', {}, authHeaders);
  console.log('6. Purge Delivered:', purgeRes.status, purgeRes.data.success ? 'PASS' : 'FAIL');

  // 7. Audited Chat Monitor - Invalid PIN should be rejected (403)
  const auditFail = await req('POST', '/v1/admin/audit/chats', {
    user1: 'alice',
    user2: 'bob',
    reason: 'Investigating reported impersonation incident',
    pin: 'wrong_pin'
  }, authHeaders);
  console.log('7. Audited Chat (Wrong PIN):', auditFail.status === 403 ? 'PASS (Forbidden as expected)' : 'FAIL');

  // 8. Audited Chat Monitor - Valid PIN (123456)
  const auditPass = await req('POST', '/v1/admin/audit/chats', {
    user1: 'alice',
    user2: 'bob',
    reason: 'Investigating reported impersonation incident',
    pin: '123456'
  }, authHeaders);
  console.log('8. Audited Chat (Valid PIN):', auditPass.status, auditPass.data.success ? 'PASS' : 'FAIL');

  // 9. Tamper-Evident SHA-256 Ledger Integrity
  const integrity = await req('GET', '/v1/admin/audit/integrity', null, authHeaders);
  console.log('9. Ledger Integrity:', integrity.status, integrity.data.is_tampered === false ? 'PASS (Untampered)' : 'FAIL');

  console.log('--- All Endpoint Tests Finished ---');
}

testAll().catch(console.error);
