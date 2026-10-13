#!/usr/bin/env node
// Forge's script providers don't all inherit RPC headers. add auth at one local hop.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const PORT = 8549;
const MAX_BODY = 16 * 1024 * 1024;

export function relayHandler(chainId, token, request = fetch) {
  assert([57073, 763373].includes(chainId), 'expected Ink chain 57073 or 763373');
  assert(typeof token === 'string' && /^[A-Za-z0-9._~+/-]+=*$/.test(token), 'set a valid INK_RPC_TOKEN in .env');
  const upstream = 'https://rpc.wildcat.finance/' + chainId;
  return async (req, res) => {
    const fail = (status, message) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32000, message } }));
    };
    // no browser access, arbitrary upstreams, or unlocked-account sends.
    if (req.headers.host !== '127.0.0.1:' + PORT || req.headers.origin || req.headers.referer) return fail(403, 'local CLI requests only');
    if (req.method !== 'POST' || req.url !== '/') return fail(405, 'POST / required');
    try {
      let size = 0;
      const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY) return fail(413, 'RPC body too large');
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      let payload;
      try { payload = JSON.parse(body); } catch { return fail(400, 'invalid JSON'); }
      const calls = Array.isArray(payload) ? payload : [payload];
      if (!calls.length || calls.some(c => !c || c.jsonrpc !== '2.0' || typeof c.method !== 'string')) return fail(400, 'invalid JSON-RPC request');
      if (calls.some(c => /^(anvil_|evm_|personal_|wallet_)/.test(c.method) || c.method === 'eth_sendTransaction' || c.method === 'eth_sign')) return fail(403, 'only signed transactions may be submitted');
      const response = await request(upstream, {
        method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token },
        body, redirect: 'error', signal: AbortSignal.timeout(60000),
      });
      if (!response.ok) return fail(502, 'gateway HTTP ' + response.status);
      const output = await response.text();
      // don't let an upstream error echo the bearer into Forge logs or receipts.
      if (output.includes(token)) return fail(502, 'gateway returned credentials');
      JSON.parse(output);
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(output);
    } catch {
      fail(502, 'gateway request failed');
    }
  };
}

export function startRelay(chainId, token) {
  const server = createServer(relayHandler(chainId, token));
  server.requestTimeout = 65000;
  server.on('error', () => { console.error('RPC relay failed; check that port 8549 is free'); process.exitCode = 1; });
  server.listen(PORT, '127.0.0.1', () => console.log('LIVE Ink RPC relay: http://127.0.0.1:8549 -> chain ' + chainId + ' (not Anvil)'));
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    assert.equal(process.argv.length, 3, 'usage: node script/ink/rpc-relay.mjs CHAIN_ID');
    startRelay(Number(process.argv[2]), process.env.INK_RPC_TOKEN);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
