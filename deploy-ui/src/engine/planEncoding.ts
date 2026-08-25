import {
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  isAddress,
  parseAbiItem,
  parseAbiParameters,
  type AbiFunction,
  type AbiParameter,
  type Address,
  type Hex,
} from 'viem'
import { isReference, resolveReferences } from './predicates'
import type { PlanTransaction, PlanValue } from './types'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address

function normalizeForAbi(value: PlanValue, parameter: AbiParameter): unknown {
  if (parameter.type.endsWith(']')) {
    if (!Array.isArray(value)) throw new Error(`Expected array for ${parameter.type}.`)
    const itemType = parameter.type.replace(/\[[0-9]*\]$/, '')
    return value.map((entry) =>
      normalizeForAbi(entry, { ...parameter, type: itemType } as AbiParameter),
    )
  }
  if (parameter.type === 'tuple') {
    if (value === null || typeof value !== 'object') throw new Error('Expected tuple value.')
    const values = Array.isArray(value) ? value : Object.values(value)
    const components = (
      parameter as AbiParameter & { components?: readonly AbiParameter[] }
    ).components ?? []
    return components.map((component, index) =>
      normalizeForAbi(values[index] as PlanValue, component),
    )
  }
  if (/^u?int[0-9]*$/.test(parameter.type)) return BigInt(value as string | number)
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

function replaceReferencesWithZero(value: PlanValue): PlanValue {
  if (isReference(value)) return ZERO_ADDRESS
  if (Array.isArray(value)) return value.map(replaceReferencesWithZero)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, replaceReferencesWithZero(entry)]),
    )
  }
  return value
}

function encodeConstructorValues(types: string[], values: PlanValue[]): Hex {
  if (types.length !== values.length) {
    throw new Error(`Constructor expects ${types.length} argument(s), got ${values.length}.`)
  }
  if (types.length === 0) return '0x'
  const parameters = parseAbiParameters(types.join(','))
  const normalized = values.map((value, index) => normalizeForAbi(value, parameters[index]))
  return encodeAbiParameters(parameters, normalized)
}

function encodeCall(signature: string, args: PlanValue[]): Hex {
  const abi = functionAbi(signature)
  if (abi.inputs.length !== args.length) {
    throw new Error(`${signature} expects ${abi.inputs.length} argument(s), got ${args.length}.`)
  }
  const normalizedArgs = args.map((arg, index) => normalizeForAbi(arg, abi.inputs[index]))
  return encodeFunctionData({ abi: [abi], args: normalizedArgs })
}

function forwardedCallData(
  transaction: Extract<PlanTransaction, { kind: 'call' }> & {
    forwardedCall: NonNullable<Extract<PlanTransaction, { kind: 'call' }>['forwardedCall']>
  },
  outputs: ReadonlyMap<string, Address> | null,
): Hex {
  const forwarded = transaction.forwardedCall
  const targetValue = outputs
    ? resolveReferences(forwarded.target, outputs)
    : replaceReferencesWithZero(forwarded.target)
  if (typeof targetValue !== 'string' || !isAddress(targetValue)) {
    throw new Error(`${transaction.id}: resolved invalid forwarded target ${String(targetValue)}`)
  }
  const innerArgs = outputs
    ? resolveReferences(forwarded.args, outputs)
    : forwarded.args.map(replaceReferencesWithZero)
  const innerData = encodeCall(forwarded.functionSignature, innerArgs)
  return encodeCall(transaction.functionSignature, [getAddress(targetValue), innerData])
}

export interface PlanPayload {
  to?: Address
  data: Hex
  value: bigint
}

export function buildPlanPayload(
  transaction: PlanTransaction,
  outputs: ReadonlyMap<string, Address>,
): PlanPayload {
  const value = BigInt(transaction.envelope.value)
  if (transaction.kind === 'deploy') {
    const unresolved = encodeConstructorValues(
      transaction.constructorArgs.types,
      transaction.constructorArgs.decoded.map(replaceReferencesWithZero),
    )
    if (unresolved.toLowerCase() !== transaction.constructorArgs.encoded.toLowerCase()) {
      throw new Error(
        `${transaction.id}: constructor ABI types and arguments do not reproduce the reviewed encoding.`,
      )
    }
    const resolved = resolveReferences(transaction.constructorArgs.decoded, outputs)
    const encoded = encodeConstructorValues(transaction.constructorArgs.types, resolved)
    return { data: `${transaction.initCode}${encoded.slice(2)}` as Hex, value }
  }

  const unresolvedData = transaction.forwardedCall
    ? forwardedCallData(transaction, null)
    : encodeCall(transaction.functionSignature, transaction.args.map(replaceReferencesWithZero))
  if (unresolvedData.toLowerCase() !== transaction.calldata.toLowerCase()) {
    throw new Error(
      `${transaction.id}: function signature and arguments do not reproduce the reviewed calldata.`,
    )
  }
  const toValue = resolveReferences(transaction.to, outputs)
  if (typeof toValue !== 'string' || !isAddress(toValue)) {
    throw new Error(`${transaction.id}: resolved invalid destination ${String(toValue)}`)
  }
  return {
    to: getAddress(toValue),
    data: transaction.forwardedCall
      ? forwardedCallData(transaction, outputs)
      : encodeCall(transaction.functionSignature, resolveReferences(transaction.args, outputs)),
    value,
  }
}
