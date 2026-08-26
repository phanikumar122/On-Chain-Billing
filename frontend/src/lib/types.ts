// lib/types.ts — Shared TypeScript types for on_chain_billing

export type InvoiceStatus = 'Pending' | 'Paid' | 'Cancelled' | 'Disputed';
export type NetworkType = 'devnet' | 'testnet' | 'mainnet';

export interface Invoice {
  id: number;
  merchant: string;
  payer: string;
  amount: bigint;
  tokenName: string;
  memo: string;
  createdAt: number;
  dueDate: number;
  paidAt?: number;
  status: InvoiceStatus;
  disputeReason?: string;
}

export interface Subscription {
  id: number;
  subscriber: string;
  merchant: string;
  amountPerCycle: bigint;
  intervalSeconds: number;
  maxCycles: number;
  cyclesUsed: number;
  lastChargedAt?: number;
  active: boolean;
  tokenName: string;
}

export const STATUS_MAP: Record<number, InvoiceStatus> = {
  0: 'Pending',
  1: 'Paid',
  2: 'Cancelled',
  3: 'Disputed',
};

export const STATUS_COLOR: Record<InvoiceStatus, string> = {
  Pending:   'var(--status-pending)',
  Paid:      'var(--status-paid)',
  Cancelled: 'var(--status-cancelled)',
  Disputed:  'var(--status-disputed)',
};
