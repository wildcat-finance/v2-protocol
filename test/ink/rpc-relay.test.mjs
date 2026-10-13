import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { relayHandler } from '../../script/ink/rpc-relay.mjs';

const token = 'ink-relay-test-token';
const read = { jsonrpc: '2.0', id: 1, method: 'eth_chainId', params: [] };
async function call(handler, payload = read, options = {}) {
  const req = Readable.from([Buffer.from(typeof payload === 'string' ? payload : JSON.stringify(payload))]);
  Object.assign(req, { method: 'POST', url: '/', headers: { host: '127.0.0.1:8549' }, ...options });
  const res = { writeHead(status) { this.status = status; }, end(body) { this.body = body; } };
  await handler(req, res);
  return { status: res.status, body: JSON.parse(res.body), raw: res.body };
}

test('forwards exact RPC bodies and signed transactions with gateway-only bearer auth', async () => {
  for (const chainId of [57073, 763373]) {
    for (const payload of [read, [read], { ...read, method: 'eth_sendRawTransaction', params: ['0x0102'] }]) {
      const output = JSON.stringify({ jsonrpc: '2.0', id: 1, result: '0x' + chainId.toString(16) });
      const handler = relayHandler(chainId, token, async (url, opts) => {
        assert.equal(url, 'https://rpc.wildcat.finance/' + chainId);
        assert.equal(opts.headers.authorization, 'Bearer ' + token);
        assert.equal(opts.body.toString(), JSON.stringify(payload));
        assert.equal(opts.redirect, 'error');
        assert(opts.signal instanceof AbortSignal);
        return new Response(output);
      });
      assert.equal((await call(handler, payload)).raw, output);
    }
  }
});

test('rejects wrong chains, missing or malformed bearer values without exposing them', () => {
  assert.throws(() => relayHandler(1, token), /expected Ink chain/);
  for (const value of [undefined, '', 'Bearer ' + token, token + '\r\nx-bad: 1']) {
    assert.throws(() => relayHandler(763373, value), error => !error.message.includes(token));
  }
});

test('rejects browser access, arbitrary paths, malformed requests and unlocked sends before forwarding', async () => {
  const handler = relayHandler(763373, token, () => { assert.fail('must not forward'); });
  for (const options of [{ method: 'GET' }, { url: '/57073' }, { headers: { host: 'other.example:8549' } },
    { headers: { host: '127.0.0.1:8549', origin: 'https://example.com' } },
    { headers: { host: '127.0.0.1:8549', referer: 'https://example.com' } }]) {
    assert((await call(handler, read, options)).status >= 400);
  }
  for (const payload of ['broken JSON', [], null, {}, [{ ...read, method: 'anvil_impersonateAccount' }],
    { ...read, method: 'eth_sendTransaction' }, { ...read, method: 'eth_sign' }]) {
    assert((await call(handler, payload)).status >= 400);
  }
  assert.equal((await call(handler, 'x'.repeat(16 * 1024 * 1024 + 1))).status, 413);
});

test('preserves JSON-RPC errors and hides HTTP, transport and credential-echo errors', async () => {
  const upstreamError = { jsonrpc: '2.0', id: 1, error: { code: -32001, message: 'missing block' } };
  const handler = relayHandler(763373, token, async () => new Response(JSON.stringify(upstreamError)));
  assert.deepEqual((await call(handler)).body, upstreamError);
  for (const request of [async () => new Response(token, { status: 429 }),
    async () => { throw new Error(token); }, async () => new Response(JSON.stringify({ error: token })),
    async () => new Response('<html>gateway error</html>')]) {
    const result = await call(relayHandler(763373, token, request));
    assert.equal(result.status, 502);
    assert(!result.raw.includes(token));
  }
});
