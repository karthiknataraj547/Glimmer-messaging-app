const https = require('https');

function get(path) {
  return new Promise((resolve, reject) => {
    const req = https.get('https://glimmer-messaging-app-web.vercel.app' + path, res => {
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
  });
}

function post(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request({
      hostname: 'glimmer-messaging-app-web.vercel.app',
      path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
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
  console.log('--- TESTING LIVE VERCEL BACKEND API ---');
  
  const health = await get('/health');
  console.log('0. Health Check:', health.status, health.data);

  const checkAdmin = await get('/v1/auth/check-username/admin');
  console.log('1. Check username "admin":', checkAdmin.status, checkAdmin.data);

  const checkUnique = await get('/v1/auth/check-username/vercel_unique_' + Math.floor(Math.random() * 8999 + 1000));
  console.log('2. Check unique username:', checkUnique.status, checkUnique.data);

  const wrongLogin = await post('/v1/auth/login-user', { username: 'admin', password: 'wrongpassword' });
  console.log('3. Login with wrong password:', wrongLogin.status, wrongLogin.data);

  const correctLogin = await post('/v1/auth/login-user', { username: 'admin', password: '123456' });
  console.log('4. Login with correct password:', correctLogin.status, correctLogin.data);
}

run();
