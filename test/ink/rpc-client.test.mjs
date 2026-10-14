import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { rpcClient } from '../../script/ink/inventory.mjs';

test('RPC reads close their connection without changing the request or deadline', async t => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    requests.push({ url, ...options });
    return new Response(JSON.stringify({ jsonrpc: '2.0', id: requests.length, result: '0x4' }));
  });
  const rpc = rpcClient('http://127.0.0.1:8549');
  assert.equal(await rpc('eth_getTransactionCount', ['0x1234', 'latest']), '0x4');
  assert.equal(await rpc('eth_getBlockByNumber', ['0x10', false]), '0x4');
  for (const [index, request] of requests.entries()) {
    assert.equal(request.url, 'http://127.0.0.1:8549');
    assert.equal(request.method, 'POST');
    assert.equal(request.headers.connection, 'close');
    assert.equal(request.headers['content-type'], 'application/json');
    assert(request.signal instanceof AbortSignal && !request.signal.aborted);
    assert.equal(JSON.parse(request.body).id, index + 1);
  }
  assert.deepEqual(JSON.parse(requests[1].body), { jsonrpc: '2.0', id: 2, method: 'eth_getBlockByNumber', params: ['0x10', false] });
});

test('RPC errors distinguish transport, timeout, HTTP and JSON-RPC without exposing credentials', async t => {
  const secret = 'private-rpc-secret';
  const cases = [
    [() => new Response(secret, { status: 429 }), 'HTTP 429'],
    [() => new Response(secret), 'invalid JSON response'],
    [() => new Response(JSON.stringify({ error: { code: -32005, message: secret } })), 'JSON-RPC -32005'],
    [() => new Response(JSON.stringify({ error: { code: secret, message: secret } })), 'invalid JSON-RPC response'],
    [() => { throw new DOMException(secret, 'TimeoutError'); }, 'timeout after 30s'],
    [() => { throw new TypeError(secret, { cause: { code: 'ECONNRESET', message: secret } }); }, 'ECONNRESET'],
    [() => { throw new TypeError(secret, { cause: { code: secret } }); }, 'network failure'],
  ];
  for (const [request, reason] of cases) {
    const mocked = t.mock.method(globalThis, 'fetch', request);
    await assert.rejects(rpcClient('https://rpc.example.test/' + secret)('eth_getBlockByNumber'), error => {
      assert.equal(error.message, 'RPC request failed: eth_getBlockByNumber (' + reason + ')');
      assert(!String(error).includes(secret));
      return true;
    });
    assert.equal(mocked.mock.callCount(), 1);
    mocked.mock.restore();
  }
});

test('a block read survives synchronous work after the server expires its old socket', { timeout: 10000 }, async t => {
  // a separate process can close sockets while the client's event loop is blocked by Forge.
  const server = spawn(process.execPath, ['--input-type=module', '-e', `
    import { createServer } from 'node:http';
    let connection = 0;
    const server = createServer(async (req, res) => {
      const socket = req.socket;
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const request = JSON.parse(Buffer.concat(chunks));
      res.writeHead(200, {'content-type': 'application/json', connection: 'keep-alive', 'keep-alive': 'timeout=30'});
      res.end(JSON.stringify({jsonrpc: '2.0', id: request.id, result: socket.number}));
      setTimeout(() => socket.destroy(), 50);
    });
    server.on('connection', socket => { socket.number = ++connection; });
    server.listen(0, '127.0.0.1', () => process.send(server.address().port));
  `], { stdio: ['ignore', 'ignore', 'pipe', 'ipc'] });
  t.after(async () => {
    if (server.exitCode === null && server.signalCode === null) {
      const exited = once(server, 'exit');
      server.kill('SIGTERM');
      await exited;
    }
  });
  const [port] = await once(server, 'message');
  const rpc = rpcClient('http://127.0.0.1:' + port);
  assert.equal(await rpc('eth_getBlockByNumber', ['0x10', false]), 1);
  const paused = spawnSync(process.execPath, ['-e', 'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 200)']);
  assert.equal(paused.status, 0);
  assert.equal(await rpc('eth_getBlockByNumber', ['0x10', false]), 2);
});
