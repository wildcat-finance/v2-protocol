import {
  decodeFunctionResult,
  encodeFunctionData,
  getAddress,
  isAddress,
  parseAbiItem,
  type AbiFunction,
  type Address,
  type Hex,
} from 'viem'
import type {
  PlanValue,
  Predicate,
  PredicateResult,
  ReadTransport,
  Reference,
} from './types'

export function isReference(value: unknown): value is Reference {
  return (
    !!value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).length === 1 &&
    typeof (value as Reference).$ref === 'string'
  )
}

export function resolveReferences<T extends PlanValue>(
  value: T,
  outputs: ReadonlyMap<string, Address>,
): T {
  if (isReference(value)) {
    const resolved = outputs.get(value.$ref)
    if (!resolved) throw new Error(`Unresolved output reference: ${value.$ref}`)
    return resolved as T
  }
  if (Array.isArray(value)) {
    return value.map((entry) => resolveReferences(entry, outputs)) as T
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        resolveReferences(entry, outputs),
      ]),
    ) as T
  }
  return value
}

export function canonicalValue(value: unknown): unknown {
  if (typeof value === 'bigint' || typeof value === 'number') return value.toString()
  if (typeof value === 'string') {
    if (isAddress(value) || /^0x[a-fA-F0-9]*$/.test(value)) return value.toLowerCase()
    return value
  }
  if (Array.isArray(value)) return value.map(canonicalValue)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !/^\d+$/.test(key))
        .map(([key, entry]) => [key, canonicalValue(entry)]),
    )
  }
  return value
}

function functionAbi(signature: string): AbiFunction {
  const declaration = signature.trim().startsWith('function ')
    ? signature.trim()
    : `function ${signature.trim()}`
  const item = parseAbiItem(declaration)
  if (item.type !== 'function') throw new Error(`Invalid function signature: ${signature}`)
  return item
}

function normalizeForAbi(value: PlanValue, parameter: { type: string; components?: readonly any[] }): unknown {
  if (parameter.type.endsWith(']')) {
    if (!Array.isArray(value)) throw new Error(`Expected array for ${parameter.type}.`)
    const itemType = parameter.type.replace(/\[[0-9]*\]$/, '')
    return value.map((entry) => normalizeForAbi(entry, { ...parameter, type: itemType }))
  }
  if (parameter.type === 'tuple') {
    if (value === null || typeof value !== 'object') throw new Error('Expected tuple value.')
    const values = Array.isArray(value) ? value : Object.values(value)
    return (parameter.components ?? []).map((component, index) =>
      normalizeForAbi(values[index] as PlanValue, component),
    )
  }
  if (/^u?int[0-9]*$/.test(parameter.type)) return BigInt(value as string | number)
  return value
}

export async function evaluatePredicate(
  transport: ReadTransport,
  predicate: Predicate,
  outputs: ReadonlyMap<string, Address>,
): Promise<PredicateResult> {
  const targetValue = resolveReferences(predicate.target, outputs)
  if (typeof targetValue !== 'string' || !isAddress(targetValue)) {
    throw new Error(`Predicate resolved to invalid target: ${String(targetValue)}`)
  }
  const target = getAddress(targetValue)

  if (predicate.type === 'codePresent') {
    const code = await transport.getCode(target)
    const ok = typeof code === 'string' && !/^0x0*$/.test(code)
    return {
      ok,
      detail: ok ? `code present at ${target}` : `no code at ${target}`,
    }
  }

  const abi = functionAbi(predicate.call.sig)
  const args = resolveReferences(predicate.call.args, outputs).map((value, index) =>
    normalizeForAbi(
      value,
      abi.inputs[index] as { type: string; components?: readonly any[] },
    ),
  )
  const data = encodeFunctionData({ abi: [abi], args })
  const encodedResult = await transport.ethCall(target, data)
  const decoded = decodeFunctionResult({ abi: [abi], data: encodedResult })
  const actual = canonicalValue(decoded)
  const expected = canonicalValue(resolveReferences(predicate.expect, outputs))
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  return {
    ok,
    detail: ok
      ? `${predicate.call.sig} returned ${JSON.stringify(actual)}`
      : `${predicate.call.sig} expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  }
}

export function encodePredicateCall(predicate: Extract<Predicate, { type: 'callEq' }>): Hex {
  const abi = functionAbi(predicate.call.sig)
  return encodeFunctionData({ abi: [abi], args: predicate.call.args as readonly unknown[] })
}
