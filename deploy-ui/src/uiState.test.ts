import { describe, expect, it } from 'vitest'
import type { Hex } from 'viem'
import { LocalStorageProgressStore } from './engine/runState'
import {
  clampRailWidth,
  DEFAULT_RAIL_WIDTH,
  isRpcUnavailableError,
  MAX_RAIL_WIDTH,
  MIN_RAIL_WIDTH,
  needsAnvilResumeDecision,
  runStateForDisplay,
} from './uiState'

class TestStorage implements Storage {
  private readonly values = new Map<string, string>()

  get length(): number {
    return this.values.size
  }

  clear(): void {
    this.values.clear()
  }

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  key(index: number): string | null {
    return Array.from(this.values.keys())[index] ?? null
  }

  removeItem(key: string): void {
    this.values.delete(key)
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value)
  }
}

describe('deploy UI recovery helpers', () => {
  it('recognizes transport failures without classifying wallet rejection as an outage', () => {
    expect(
      isRpcUnavailableError(
        new Error(
          'Unexpected end of JSON input: tcp connect error: Connection refused (os error 61)',
        ),
      ),
    ).toBe(true)
    expect(isRpcUnavailableError(new Error('temporary RPC outage'))).toBe(true)
    expect(isRpcUnavailableError(new Error('HTTP request failed. The request took too long.'))).toBe(
      true,
    )
    expect(isRpcUnavailableError(new Error('User rejected the request.'))).toBe(false)
    expect(isRpcUnavailableError(new Error('Execution reverted: OwnableUnauthorizedAccount'))).toBe(
      false,
    )
  })

  it('keeps the desktop rail within usable panel and viewport bounds', () => {
    expect(clampRailWidth(DEFAULT_RAIL_WIDTH, 1440)).toBe(DEFAULT_RAIL_WIDTH)
    expect(clampRailWidth(100, 1440)).toBe(MIN_RAIL_WIDTH)
    expect(clampRailWidth(900, 1440)).toBe(MAX_RAIL_WIDTH)
    expect(clampRailWidth(600, 900)).toBe(480)
  })

  it('clears only the selected ceremony package progress', () => {
    const storage = new TestStorage()
    const digest = `0x${'11'.repeat(32)}` as Hex
    const store = new LocalStorageProgressStore(digest, storage)
    storage.setItem('unrelated', 'keep')
    store.save({})

    store.clear()

    expect(storage.getItem(store.key)).toBeNull()
    expect(storage.getItem('unrelated')).toBe('keep')
  })

  it('withholds cached completion until chain verification and gates Anvil resume', () => {
    const cached = {
      'deploy-token': {
        txHash: `0x${'22'.repeat(32)}` as Hex,
        status: 'verified' as const,
      },
    }
    expect(runStateForDisplay(cached, false)).toEqual({})
    expect(runStateForDisplay(cached, true)).toBe(cached)
    expect(needsAnvilResumeDecision(true, 1)).toBe(true)
    expect(needsAnvilResumeDecision(true, 0)).toBe(false)
    expect(needsAnvilResumeDecision(false, 1)).toBe(false)
  })
})
