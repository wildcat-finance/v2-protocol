#!/usr/bin/env node
'use strict';

const http = require('node:http');
const https = require('node:https');
const { URL } = require('node:url');

const PROBE_BYTECODE = '0x600160005d60005c60005260206000f3';
const EXPECTED_RESULT = `0x${'0'.repeat(63)}1`;

function usage() {
  console.error('Usage: node scripts/check-eip1153.js --rpc-url <url> [--quiet]');
}

function parseArgs(argv) {
  const args = { rpcUrl: process.env.RPC_URL || '', quiet: false };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--rpc-url') {
      args.rpcUrl = argv[++i] || '';
    } else if (arg === '--quiet') {
      args.quiet = true;
    } else if (arg === '--help' || arg === '-h') {
      usage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!args.rpcUrl) {
    throw new Error('Missing --rpc-url or RPC_URL.');
  }
  return args;
}

function requestJson(rpcUrl, body) {
  const url = new URL(rpcUrl);
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error(`Unsupported RPC URL protocol: ${url.protocol}`);
  }
  const transport = url.protocol === 'https:' ? https : http;
  const payload = JSON.stringify(body);

  const requestOptions = {
    method: 'POST',
    hostname: url.hostname,
    port: url.port || undefined,
    path: `${url.pathname}${url.search}`,
    headers: {
      'content-type': 'application/json',
      'content-length': Buffer.byteLength(payload),
    },
    timeout: 15_000,
  };
  if (url.username || url.password) {
    requestOptions.auth = `${decodeURIComponent(url.username)}:${decodeURIComponent(url.password)}`;
  }

  return new Promise((resolve, reject) => {
    const req = transport.request(requestOptions, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`HTTP ${res.statusCode}: ${text}`));
          return;
        }
        try {
          resolve(JSON.parse(text));
        } catch (error) {
          reject(new Error(`Invalid JSON-RPC response: ${error.message}`));
        }
      });
    });

    req.on('timeout', () => {
      req.destroy(new Error('JSON-RPC request timed out.'));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

let nextRequestId = 1;

async function rpc(rpcUrl, method, params) {
  const response = await requestJson(rpcUrl, {
    jsonrpc: '2.0',
    id: nextRequestId++,
    method,
    params,
  });
  if (response.error) {
    throw new Error(response.error.message || JSON.stringify(response.error));
  }
  return response.result;
}

function decimalChainId(chainIdHex) {
  if (!chainIdHex || typeof chainIdHex !== 'string') return 'unknown chain';
  try {
    return `chain ${BigInt(chainIdHex).toString(10)}`;
  } catch {
    return 'unknown chain';
  }
}

async function main() {
  const { rpcUrl, quiet } = parseArgs(process.argv);
  let chainId = '';
  try {
    chainId = await rpc(rpcUrl, 'eth_chainId', []);
  } catch {
    chainId = '';
  }

  let callError;
  try {
    const result = await rpc(rpcUrl, 'eth_call', [{ data: PROBE_BYTECODE }, 'latest']);
    if (typeof result === 'string' && result.toLowerCase() === EXPECTED_RESULT) {
      if (!quiet) {
        console.log(`EIP-1153 transient storage probe passed on ${decimalChainId(chainId)}.`);
      }
      return;
    }
    callError = new Error(`Unexpected eth_call result: ${result}`);
  } catch (error) {
    callError = error;
  }

  try {
    await rpc(rpcUrl, 'eth_estimateGas', [{ data: PROBE_BYTECODE }]);
    if (!quiet) {
      console.log(
        `EIP-1153 transient storage probe passed on ${decimalChainId(chainId)} via eth_estimateGas.`
      );
    }
  } catch (estimateError) {
    const details = [
      `EIP-1153 transient storage probe failed on ${decimalChainId(chainId)}.`,
      `eth_call: ${callError.message}`,
      `eth_estimateGas: ${estimateError.message}`,
    ];
    throw new Error(details.join('\n'));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
