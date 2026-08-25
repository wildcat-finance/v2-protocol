import type { Address, Hex } from 'viem'

export type Reference = { $ref: string }
export type PlanValue =
  | Reference
  | string
  | number
  | boolean
  | null
  | PlanValue[]
  | { [key: string]: PlanValue }

export type Predicate =
  | { type: 'codePresent'; target: Address | Reference }
  | {
      type: 'callEq'
      target: Address | Reference
      call: { sig: string; args: PlanValue[] }
      expect: PlanValue
    }
  | {
      type: 'callResultEq'
      target: Address | Reference
      call: { sig: string; args: PlanValue[] }
      resultIndex: number
      expect: PlanValue
    }

export type GasLimitPolicy =
  | 'estimate*1.3'
  | { type: 'explicit'; gasLimit: string }

export interface TransactionEnvelope {
  chainId: number
  expectedExecutor: Address
  to: Address | Reference | null
  value: string
  data: 'initCode+constructorArgs' | 'functionSignature+args' | 'forwardedCall'
  gasLimitPolicy: GasLimitPolicy
  nonceCheck: 'display-and-confirm'
}

interface PlanTransactionBase {
  id: string
  description: string
  reverifyUntil?: string
  envelope: TransactionEnvelope
  predicate: Predicate
}

export interface DeployTransaction extends PlanTransactionBase {
  kind: 'deploy'
  artifactName: string
  initCode: Hex
  constructorArgs: { types: string[]; decoded: PlanValue[]; encoded: Hex }
  output: string
}

export interface ForwardedCall {
  target: Address | Reference
  functionSignature: string
  args: PlanValue[]
}

export interface DirectCallTransaction extends PlanTransactionBase {
  kind: 'call'
  to: Address | Reference
  functionSignature: string
  args: PlanValue[]
  forwardedCall?: never
  calldata: Hex
}

export interface ForwardedCallTransaction extends PlanTransactionBase {
  kind: 'call'
  to: Address | Reference
  functionSignature: 'executeProtocolAction(address,bytes)'
  args?: never
  forwardedCall: ForwardedCall
  calldata: Hex
}

export type CallTransaction = DirectCallTransaction | ForwardedCallTransaction

export type PlanTransaction = DeployTransaction | CallTransaction

export interface DeploymentPlan {
  schemaVersion: '1.1.0'
  foundryProfile: 'deploy'
  network: string
  chainId: number
  release: string
  expectedExecutor: Address
  onFailure: 'halt'
  resume: 're-verify all prior predicates before continuing'
  transactions: PlanTransaction[]
}

export interface SafeInnerTransaction {
  planIndex: number
  planId: string
  kind: 'deploy' | 'call'
  description: string
  operation: 0 | 1
  to: Address
  logicalTarget: Address
  value: string
  data: Hex
  decodedArgs: PlanValue[]
  predicate: Predicate
  precomputedAddress: Address | null
  salt: Hex | null
  initCodeHash: Hex | null
  staticGasEstimate: string
  simulatedGas: string | null
}

export interface BundleManifest {
  schemaVersion: '1.1.0'
  plan: {
    release: string
    network: string
    chainId: number
    fileHash: Hex
  }
  safe: { address: Address; version: '1.4.1' }
  bundle: {
    number: number
    safeNonce: string
    maxGas: string
    staticGasEstimate: string
    simulatedGas: string | null
  }
  safeTransaction: {
    to: Address
    value: string
    data: Hex
    operation: 1
    safeTxGas: '0'
    baseGas: '0'
    gasPrice: '0'
    gasToken: Address
    refundReceiver: Address
    nonce: string
    safeTxHash: Hex
  }
  innerTransactions: SafeInnerTransaction[]
}

export type ExpectedAddresses = Record<string, Address>

export interface PredicateResult {
  ok: boolean
  detail: string
}

export interface ReceiptLike {
  transactionHash: Hex
  blockNumber: bigint
  status: 'success' | 'reverted'
  contractAddress?: Address | null
}

export interface ExecutionTransport {
  getChainId(): Promise<number>
  getAccount(): Promise<Address>
  getCode(address: Address): Promise<Hex | undefined>
  getTransactionCount(address: Address): Promise<number>
  estimateGas(request: {
    account: Address
    to?: Address
    data: Hex
    value: bigint
  }): Promise<bigint>
  sendTransaction(request: {
    account: Address
    to?: Address
    data: Hex
    value: bigint
    gas: bigint
    nonce: number
  }): Promise<Hex>
  waitForReceipt(hash: Hex): Promise<ReceiptLike>
  getReceipt(hash: Hex): Promise<ReceiptLike | null>
  ethCall(to: Address, data: Hex): Promise<Hex>
}

export interface ReadTransport {
  getChainId(): Promise<number>
  getCode(address: Address): Promise<Hex | undefined>
  ethCall(to: Address, data: Hex): Promise<Hex>
}
