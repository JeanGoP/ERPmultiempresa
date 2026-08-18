const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function loadLocalEnvironment(filePath) {
  if (!fs.existsSync(filePath)) return {};
  return fs.readFileSync(filePath, 'utf8').split(/\r?\n/).reduce((values, line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) return values;
    const separator = trimmed.indexOf('=');
    if (separator < 1) return values;
    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    values[key] = value;
    return values;
  }, {});
}

const localEnvironment = loadLocalEnvironment(path.join(__dirname, '.env.local'));

const port = Number(process.env.PORT) || 4173;
const publicDir = path.join(__dirname, 'public');
const apiPort = Number(process.env.ERP_API_PORT) || 5180;
const apiHost = '127.0.0.1';
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.json': 'application/json; charset=utf-8'
};

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 50 * 1024 * 1024) throw new Error('PAYLOAD_TOO_LARGE');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function proxyToErpApi(request, response) {
  const headers = { ...request.headers, host: `${apiHost}:${apiPort}` };
  const proxy = http.request({ hostname: apiHost, port: apiPort, method: request.method, path: request.url.replace(/^\/erp-api/, ''), headers }, (apiResponse) => {
    response.writeHead(apiResponse.statusCode || 502, apiResponse.headers);
    apiResponse.pipe(response);
  });
  proxy.on('error', () => {
    if (!response.headersSent) response.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify({ error: 'La API ERP no está disponible. Reinicia el servidor y verifica SQL Server LocalDB.' }));
  });
  request.pipe(proxy);
}

let apiProcess = null;
if (process.env.ERP_API_AUTOSTART !== '0') {
  apiProcess = spawn('dotnet', ['run', '--no-build', '--no-launch-profile', '--project', path.join('backend', 'NexoERP.Api'), '--urls', `http://${apiHost}:${apiPort}`], {
    cwd: __dirname, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...localEnvironment, ...process.env }
  });
  apiProcess.stdout.on('data', (chunk) => process.stdout.write(`[API] ${chunk}`));
  apiProcess.stderr.on('data', (chunk) => process.stderr.write(`[API] ${chunk}`));
  apiProcess.on('error', (error) => console.error('No fue posible iniciar la API ERP:', error.message));
}

http.createServer(async (request, response) => {
  if (request.url.startsWith('/erp-api/')) {
    proxyToErpApi(request, response);
    return;
  }
  if (request.method === 'POST' && request.url === '/api/export-xlsx') {
    try {
      const payload = await readJson(request);
      const { exportExcelBuffer } = await import('./excel-export.mjs');
      const buffer = await exportExcelBuffer(payload);
      response.writeHead(200, {
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': 'attachment; filename="datos-xml.xlsx"',
        'Content-Length': buffer.length,
      });
      response.end(buffer);
    } catch (error) {
      const status = error.message === 'PAYLOAD_TOO_LARGE' ? 413 : 500;
      console.error('Error al exportar Excel:', error);
      response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ error: status === 413 ? 'El documento es demasiado grande.' : 'No fue posible crear el archivo Excel.' }));
    }
    return;
  }
  const requestPath = decodeURIComponent(request.url.split('?')[0]);
  const relativePath = requestPath === '/' ? 'index.html' : requestPath.replace(/^\/+/, '');
  const filePath = path.resolve(publicDir, relativePath);

  if (!filePath.startsWith(publicDir + path.sep)) {
    response.writeHead(403).end('Acceso denegado');
    return;
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(error.code === 'ENOENT' ? 404 : 500).end('Archivo no encontrado');
      return;
    }
    response.writeHead(200, { 'Content-Type': contentTypes[path.extname(filePath)] || 'application/octet-stream' });
    response.end(data);
  });
}).listen(port, '127.0.0.1', () => {
  console.log(`Nexo ERP disponible en http://127.0.0.1:${port}`);
});

function stopApi() { if (apiProcess && !apiProcess.killed) apiProcess.kill(); }
process.once('SIGINT', () => { stopApi(); process.exit(0); });
process.once('SIGTERM', () => { stopApi(); process.exit(0); });
process.once('exit', stopApi);
