import type { RunState } from './engine/runState'

export const DEFAULT_RAIL_WIDTH = 368
export const MIN_RAIL_WIDTH = 280
export const MAX_RAIL_WIDTH = 640

const EMPTY_RUN_STATE: RunState = {}

export function runStateForDisplay(runState: RunState, chainVerified: boolean): RunState {
  return chainVerified ? runState : EMPTY_RUN_STATE
}

export function needsAnvilResumeDecision(
  isAnvilPlan: boolean,
  storedActionCount: number,
): boolean {
  return isAnvilPlan && storedActionCount > 0
}

export function clampRailWidth(width: number, viewportWidth: number): number {
  const viewportMaximum = Math.max(MIN_RAIL_WIDTH, viewportWidth - 420)
  const maximum = Math.min(MAX_RAIL_WIDTH, viewportMaximum)
  return Math.min(maximum, Math.max(MIN_RAIL_WIDTH, Math.round(width)))
}

export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

export function isRpcUnavailableError(error: unknown): boolean {
  return /unexpected\s+end\s+of\s+json\s+input|connection\s+refused|econnrefused|failed\s+to\s+fetch|fetch\s+failed|network\s+error|socket\s+hang\s+up|http\s+request\s+failed|request\s+took\s+too\s+long|timed\s+out|rpc\s+(?:is\s+)?unavailable|rpc\s+outage|error\s+sending\s+request|could\s+not\s+connect/i.test(
    errorText(error),
  )
}
