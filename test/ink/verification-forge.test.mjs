import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { verificationArgs, verificationEnvironment } from '../../script/ink/verification.mjs';

test('Forge authenticates ABI checks, source submissions, and watch polling on both Ink chains', async () => {
  const root = mkdtempSync(join(tmpdir(), 'ink-verification-auth-'));
  const key = 'proapi_local_test_only';
  const requests = [];
  let alreadyVerified = false;
  const server = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    const url = new URL(req.url, 'http://127.0.0.1');
    const form = new URLSearchParams(body);
    const param = name => url.searchParams.get(name) ?? form.get(name);
    requests.push({ method: req.method, action: param('action'), key: param('apikey'), chain: param('chainid') });
    res.setHeader('content-type', 'application/json');
    if (param('apikey') !== key) {
      res.writeHead(401).end(JSON.stringify({ error: 'missing API key' }));
      return;
    }
    const responses = {
      getabi: alreadyVerified
        ? { status: '1', message: 'OK', result: '[]' }
        : { status: '0', message: 'NOTOK', result: 'Contract source code not verified' },
      verifysourcecode: { status: '1', message: 'OK', result: 'local-test-guid' },
      checkverifystatus: { status: '1', message: 'OK', result: 'Pass - Verified' },
    };
    res.end(JSON.stringify(responses[param('action')] ?? { status: '0', message: 'NOTOK', result: 'unexpected action' }));
  });
  try {
    mkdirSync(join(root, 'src'));
    writeFileSync(join(root, 'src/VerifierFixture.sol'), 'pragma solidity 0.8.25; contract VerifierFixture {}\n');
    writeFileSync(join(root, 'foundry.toml'), '[profile.ink]\noffline = true\nbytecode_hash = "none"\n');
    writeFileSync(join(root, '.env'), 'ETHERSCAN_API_KEY=unrelated\nVERIFIER_API_KEY=unrelated\n');
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    const inherited = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^(FOUNDRY_|DAPP_)/.test(name)));
    const env = verificationEnvironment(inherited, key);
    for (const chainId of [57073, 763373]) {
      const record = { kind: 'contract', address: '0x0000000000000000000000000000000000000001',
        target: 'src/VerifierFixture.sol:VerifierFixture', compiler: '0.8.25+commit.b61c2a91', constructorArgs: '0x' };
      const args = verificationArgs(chainId, record);
      args[args.indexOf('--verifier-url') + 1] = `http://127.0.0.1:${server.address().port}/v2/api?chainid=${chainId}`;
      args.push('--root', root);
      assert(!args.some(arg => arg.includes(key)), 'API key belongs in the environment, not argv');
      for (alreadyVerified of [false, true]) {
        requests.length = 0;
        const result = await promisify(execFile)('forge', args, { cwd: root, env, encoding: 'utf8', timeout: 30000 })
          .then(output => ({ ...output, code: 0 }), error => error);
        assert(requests.length > 0, result.stderr || result.message);
        assert(requests.every(req => req.key === key), 'Forge dropped the API key');
        assert(requests.every(req => req.chain === String(chainId)), 'Forge dropped the chain ID');
        assert.equal(result.code, 0, result.stderr || result.message);
        assert.deepEqual(requests.map(req => [req.method, req.action]), alreadyVerified
          ? [['GET', 'getabi']]
          : [['GET', 'getabi'], ['POST', 'verifysourcecode'], ['POST', 'checkverifystatus']]);
        assert.match(result.stdout, alreadyVerified ? /already verified/i : /successfully verified/i);
      }
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    rmSync(root, { recursive: true });
  }
});
