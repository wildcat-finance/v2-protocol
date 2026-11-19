#!/usr/bin/env python3
"""Test-only upstream FastLZ oracle. No downloads or Solidity code in this oracle."""

import ctypes
import fcntl
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / 'test/reference/fastlz'
HASHES = {
    'fastlz.c': '36b9b686fe372eaf1406a78914b6b85ed2865bbd3f285b0ba37fdbb294bc66ff',
    'fastlz.h': 'd2b6ca9c0f4b5cdd0855d90695e3b7e0da70203ac93119971020e46bb0b68039',
}


def library():
    for name, expected in HASHES.items():
        assert hashlib.sha256((REFERENCE / name).read_bytes()).hexdigest() == expected, name
    directory = ROOT / 'deploy-out/fastlz-reference' / HASHES['fastlz.c']
    directory.mkdir(parents=True, exist_ok=True)
    output = directory / 'fastlz.so'
    with (directory / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not output.exists():
            subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-fno-strict-aliasing',
                            str(REFERENCE / 'fastlz.c'), '-o', str(output)], check=True)
    result = ctypes.CDLL(str(output))
    result.fastlz_compress_level.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    result.fastlz_compress_level.restype = ctypes.c_int
    result.fastlz_decompress.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    result.fastlz_decompress.restype = ctypes.c_int
    return result


def compress(codec, data):
    # upstream documents a 16-byte minimum. short inputs are one literal run;
    # empty Solidity input uses an empty stream instead of calling C with zero bytes.
    if len(data) < 16:
        return bytes([len(data) - 1]) + data if data else b''
    source = ctypes.create_string_buffer(data + bytes(32))
    output = ctypes.create_string_buffer(len(data) * 2 + 66)
    size = codec.fastlz_compress_level(1, source, len(data), output)
    assert 0 < size <= len(output)
    return output.raw[:size]


def decompress(codec, data):
    if not data:
        return b''
    source = ctypes.create_string_buffer(data + bytes(32))
    output = ctypes.create_string_buffer(49_152)
    size = codec.fastlz_decompress(source, len(data), output, len(output))
    assert 0 < size <= len(output), 'upstream rejected stream'
    return output.raw[:size]


def abi_bytes_pair(first, second):
    def word(value):
        return value.to_bytes(32, 'big')
    def tail(data):
        return word(len(data)) + data + bytes(-len(data) % 32)
    first_tail = tail(first)
    return word(64) + word(64 + len(first_tail)) + first_tail + tail(second)


if __name__ == '__main__':
    original, compressed = (bytes.fromhex(value.removeprefix('0x')) for value in sys.argv[1:])
    assert len(original) <= 49_152 and len(compressed) <= 50_688
    codec = library()
    print('0x' + abi_bytes_pair(compress(codec, original), decompress(codec, compressed)).hex())
