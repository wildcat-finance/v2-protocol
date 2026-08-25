import {
  concat,
  encodeFunctionData,
  getAddress,
  getCreate2Address,
  hashTypedData,
  keccak256,
  pad,
  parseAbi,
  size,
  stringToHex,
  toHex,
  type Address,
  type Hex,
} from 'viem'
import { resolveReferences } from './predicates'
import { buildPlanPayload } from './planEncoding'
import type {
  DeploymentPlan,
  PlanValue,
  Predicate,
  SafeInnerTransaction,
} from './types'

export const CREATE_CALL = getAddress('0x9b35Af71d77eaf8d7e40252370304687390A1A52')
export const MULTI_SEND = getAddress('0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526')

const CREATE_CALL_ABI = parseAbi([
  'function performCreate2(uint256 value, bytes deploymentData, bytes32 salt) returns (address newContract)',
])
const MULTI_SEND_ABI = parseAbi(['function multiSend(bytes transactions)'])

export type CompiledSafeEntry = Omit<
  SafeInnerTransaction,
  'staticGasEstimate' | 'simulatedGas'
>

export interface CompiledSafePlan {
  entries: CompiledSafeEntry[]
  expectedAddresses: Record<string, Address>
}

export interface CompiledSafeTransaction {
  to: Address
  value: '0'
  data: Hex
  operation: 1
}

export interface CompiledSafeTransactionData extends CompiledSafeTransaction {
  safeTxGas: '0'
  baseGas: '0'
  gasPrice: '0'
  gasToken: Address
  refundReceiver: Address
  nonce: string
  safeTxHash: Hex
}

const ZERO_ADDRESS = getAddress('0x0000000000000000000000000000000000000000')

function resolvePredicate(
  predicate: Predicate,
  outputs: ReadonlyMap<string, Address>,
): Predicate {
  return resolveReferences(
    predicate as unknown as PlanValue,
    outputs,
  ) as unknown as Predicate
}

export function compileSafePlan(plan: DeploymentPlan): CompiledSafePlan {
  const safe = getAddress(plan.expectedExecutor)
  const outputs = new Map<string, Address>()
  const expectedAddresses: Record<string, Address> = {}
  const entries: CompiledSafeEntry[] = []

  for (const [planIndex, transaction] of plan.transactions.entries()) {
    if (transaction.reverifyUntil) {
      throw new Error(
        `${transaction.id}: Safe bundling does not support transient predicates; use the EOA ceremony path for temporary ownership steps.`,
      )
    }
    const payload = buildPlanPayload(transaction, outputs)
    if (transaction.kind === 'deploy') {
      const salt = keccak256(stringToHex(`${plan.release}:${transaction.id}`))
      const precomputedAddress = getCreate2Address({
        from: safe,
        salt,
        bytecode: payload.data,
      })
      outputs.set(transaction.output, precomputedAddress)
      expectedAddresses[transaction.id] = precomputedAddress
      const data = encodeFunctionData({
        abi: CREATE_CALL_ABI,
        functionName: 'performCreate2',
        args: [payload.value, payload.data, salt],
      })
      entries.push({
        planIndex,
        planId: transaction.id,
        kind: 'deploy',
        description: transaction.description,
        operation: 1,
        to: CREATE_CALL,
        logicalTarget: precomputedAddress,
        value: '0',
        data,
        decodedArgs: resolveReferences(transaction.constructorArgs.decoded, outputs),
        predicate: resolvePredicate(transaction.predicate, outputs),
        precomputedAddress,
        salt,
        initCodeHash: keccak256(payload.data),
      })
      continue
    }

    if (!payload.to) throw new Error(`${transaction.id}: call payload has no destination.`)
    const logicalTargetValue = transaction.forwardedCall
      ? resolveReferences(transaction.forwardedCall.target, outputs)
      : payload.to
    if (typeof logicalTargetValue !== 'string') {
      throw new Error(`${transaction.id}: call has an invalid logical target.`)
    }
    const logicalTarget = getAddress(logicalTargetValue)
    const callArgs: PlanValue[] = transaction.forwardedCall?.args ?? transaction.args ?? []
    entries.push({
      planIndex,
      planId: transaction.id,
      kind: 'call',
      description: transaction.description,
      operation: 0,
      to: payload.to,
      logicalTarget,
      value: payload.value.toString(),
      data: payload.data,
      decodedArgs: resolveReferences(callArgs, outputs),
      predicate: resolvePredicate(transaction.predicate, outputs),
      precomputedAddress: null,
      salt: null,
      initCodeHash: null,
    })
  }

  return { entries, expectedAddresses }
}

function packInnerTransaction(entry: CompiledSafeEntry): Hex {
  return concat([
    toHex(entry.operation, { size: 1 }),
    entry.to,
    pad(toHex(BigInt(entry.value)), { size: 32 }),
    pad(toHex(size(entry.data)), { size: 32 }),
    entry.data,
  ])
}

export function compileSafeTransaction(
  entries: CompiledSafeEntry[],
): CompiledSafeTransaction {
  if (entries.length === 0) throw new Error('A Safe bundle cannot be empty.')
  const transactions = concat(entries.map(packInnerTransaction))
  return {
    to: MULTI_SEND,
    value: '0',
    data: encodeFunctionData({
      abi: MULTI_SEND_ABI,
      functionName: 'multiSend',
      args: [transactions],
    }),
    operation: 1,
  }
}

export function compileSafeTransactionData(
  chainId: number,
  safe: Address,
  nonce: bigint,
  entries: CompiledSafeEntry[],
): CompiledSafeTransactionData {
  if (nonce < 0n || nonce > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`Safe nonce ${nonce} is outside the supported range.`)
  }
  const transaction = compileSafeTransaction(entries)
  const fields = {
    ...transaction,
    safeTxGas: '0' as const,
    baseGas: '0' as const,
    gasPrice: '0' as const,
    gasToken: ZERO_ADDRESS,
    refundReceiver: ZERO_ADDRESS,
    nonce: nonce.toString(),
  }
  const safeTxHash = hashTypedData({
    domain: { chainId, verifyingContract: getAddress(safe) },
    primaryType: 'SafeTx',
    types: {
      SafeTx: [
        { name: 'to', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'data', type: 'bytes' },
        { name: 'operation', type: 'uint8' },
        { name: 'safeTxGas', type: 'uint256' },
        { name: 'baseGas', type: 'uint256' },
        { name: 'gasPrice', type: 'uint256' },
        { name: 'gasToken', type: 'address' },
        { name: 'refundReceiver', type: 'address' },
        { name: 'nonce', type: 'uint256' },
      ],
    },
    message: {
      to: fields.to,
      value: BigInt(fields.value),
      data: fields.data,
      operation: fields.operation,
      safeTxGas: BigInt(fields.safeTxGas),
      baseGas: BigInt(fields.baseGas),
      gasPrice: BigInt(fields.gasPrice),
      gasToken: fields.gasToken,
      refundReceiver: fields.refundReceiver,
      nonce,
    },
  })
  return { ...fields, safeTxHash }
}
