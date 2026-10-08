const https = require('https');

function get(path, token = null) {
  return new Promise((resolve, reject) => {
    const headers = {};
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = https.request({
      hostname: 'glimmer-messaging-app-web.vercel.app',
      path,
      method: 'GET',
      headers
    }, res => {
      let buf = '';
      res.on('data', c => buf += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(buf) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: buf });
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

function post(path, body, token = null) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data)
    };
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = https.request({
      hostname: 'glimmer-messaging-app-web.vercel.app',
      path,
      method: 'POST',
      headers
    }, res => {
      let buf = '';
      res.on('data', c => buf += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(buf) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: buf });
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function run() {
  console.log('--- TESTING LIVE VERCEL BACKEND & ADMIN API ---');
  
  const health = await get('/health');
  console.log('0. Health Check:', health.status, health.data?.status || health.raw?.slice(0, 80));

  const checkAdmin = await get('/v1/auth/check-username/admin');
  console.log('1. Check username "admin":', checkAdmin.status, checkAdmin.data?.available);

  const checkUnique = await get('/v1/auth/check-username/vercel_unique_' + Math.floor(Math.random() * 8999 + 1000));
  console.log('2. Check unique username:', checkUnique.status, checkUnique.data?.available);

  const wrongLogin = await post('/v1/auth/login-user', { username: 'admin', password: 'wrongpassword' });
  console.log('3. Login with wrong password:', wrongLogin.status, wrongLogin.data?.error);

  const correctLogin = await post('/v1/auth/login-user', { username: 'admin', password: '123456' });
  console.log('4. Login with correct password:', correctLogin.status, correctLogin.data?.success);

  const adminLogin = await post('/v1/admin/login', { username: 'admin', password: '123456' });
  console.log('5. Admin Login with PIN:', adminLogin.status, adminLogin.data?.success, 'Token:', !!adminLogin.data?.token);

  if (adminLogin.data?.token) {
    const adminUsers = await get('/v1/admin/users', adminLogin.data.token);
    console.log('6. Admin Users List:', adminUsers.status, 'Total users:', adminUsers.data?.count);
  }
}

run();
