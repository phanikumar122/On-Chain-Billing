// lib/contract.ts
// Complete wrappers for every on_chain_billing entry function and view function.
// All write ops return an InputTransactionData payload for the wallet adapter to sign.
// All read ops call the Aptos node view endpoint directly.

import { aptos, BILLING_ADDRESS, MODULE } from './aptos';
import { Invoice, Subscription, STATUS_MAP } from './types';

// ─── Coin type (default APT for devnet testing) ───────────────────────────────
export const DEFAULT_COIN = '0x1::aptos_coin::AptosCoin';

// ─── Address validation ────────────────────────────────────────────────────────
/** Returns true if the string is a valid Aptos hex address (0x + 1-64 hex chars) */
export function isValidAddress(addr: string): boolean {
  return /^0x[0-9a-fA-F]{1,64}$/.test(addr.trim());
}

// ─── BUILD TRANSACTION PAYLOADS ───────────────────────────────────────────────

/** Create an invoice (merchant → payer) */
export function buildCreateInvoice(
  payer: string,
  amount: string,     // in octas
  dueDate: number,    // unix seconds
  memo: string,
  coinType = DEFAULT_COIN,
) {
  return {
    data: {
      function: `${MODULE('invoice')}::create_invoice` as `${string}::${string}::${string}`,
      typeArguments: [coinType],
      functionArguments: [payer, amount, dueDate.toString(), memo],
    },
  };
}

/** Pay an invoice */
export function buildPayInvoice(invoiceId: number, coinType = DEFAULT_COIN) {
  return {
    data: {
      function: `${MODULE('invoice')}::pay_invoice` as `${string}::${string}::${string}`,
      typeArguments: [coinType],
      functionArguments: [invoiceId.toString()],
    },
  };
}

/** Cancel an invoice */
export function buildCancelInvoice(invoiceId: number) {
  return {
    data: {
      function: `${MODULE('invoice')}::cancel_invoice` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [invoiceId.toString()],
    },
  };
}

/** Flag a dispute */
export function buildFlagDispute(invoiceId: number, reason: string) {
  return {
    data: {
      function: `${MODULE('invoice')}::flag_dispute` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [invoiceId.toString(), reason],
    },
  };
}

/** Resolve a dispute (admin only) */
export function buildResolveDispute(invoiceId: number, upheld: boolean) {
  return {
    data: {
      function: `${MODULE('invoice')}::resolve_dispute` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [invoiceId.toString(), upheld],
    },
  };
}

/** Authorize a subscription */
export function buildAuthorizeSubscription(
  merchant: string,
  amountPerCycle: string,
  intervalSeconds: number,
  maxCycles: number,
  coinType = DEFAULT_COIN,
) {
  return {
    data: {
      function: `${MODULE('subscription')}::authorize` as `${string}::${string}::${string}`,
      typeArguments: [coinType],
      functionArguments: [merchant, amountPerCycle, intervalSeconds.toString(), maxCycles.toString()],
    },
  };
}

/** Charge a subscription cycle */
export function buildCharge(subId: number, coinType = DEFAULT_COIN) {
  return {
    data: {
      function: `${MODULE('subscription')}::charge` as `${string}::${string}::${string}`,
      typeArguments: [coinType],
      functionArguments: [subId.toString()],
    },
  };
}

/** Cancel a subscription */
export function buildCancelSubscription(subId: number) {
  return {
    data: {
      function: `${MODULE('subscription')}::cancel_subscription` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [subId.toString()],
    },
  };
}

// ─── ADMIN PAYLOADS ───────────────────────────────────────────────────────────

export function buildPause() {
  return {
    data: {
      function: `${MODULE('billing_admin')}::pause` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [],
    },
  };
}

export function buildUnpause() {
  return {
    data: {
      function: `${MODULE('billing_admin')}::unpause` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [],
    },
  };
}

export function buildSetFeeBps(bps: number) {
  return {
    data: {
      function: `${MODULE('billing_admin')}::set_platform_fee_bps` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [bps.toString()],
    },
  };
}

export function buildGrantAdmin(newAdmin: string) {
  return {
    data: {
      function: `${MODULE('billing_admin')}::grant_admin` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [newAdmin],
    },
  };
}

export function buildRevokeAdmin(target: string) {
  return {
    data: {
      function: `${MODULE('billing_admin')}::revoke_admin` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [target],
    },
  };
}

export function buildRegisterToken(coinType: string) {
  return {
    data: {
      function: `${MODULE('billing_admin')}::register_token` as `${string}::${string}::${string}`,
      typeArguments: [coinType],
      functionArguments: [],
    },
  };
}

// ─── ADMIN VIEW FUNCTIONS ─────────────────────────────────────────────────────

export async function getAdminStatus(): Promise<{ feeBps: number; admin: string; isPaused: boolean }> {
  const [feeRes, adminRes, pausedRes] = await Promise.all([
    aptos.view({ payload: { function: `${MODULE('billing_admin')}::get_fee_bps` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [] } }),
    aptos.view({ payload: { function: `${MODULE('billing_admin')}::get_admin` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [] } }),
    aptos.view({ payload: { function: `${MODULE('billing_admin')}::is_paused` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [] } }),
  ]);
  return {
    feeBps: Number(feeRes[0]),
    admin: adminRes[0] as string,
    isPaused: Boolean(pausedRes[0]),
  };
}

export async function getTreasuryBalance(coinType = DEFAULT_COIN): Promise<bigint> {
  try {
    const res = await aptos.view({
      payload: {
        function: `${MODULE('billing_admin')}::get_treasury_balance` as `${string}::${string}::${string}`,
        typeArguments: [coinType],
        functionArguments: [],
      },
    });
    return BigInt(res[0] as string);
  } catch {
    return 0n;
  }
}

// ─── VIEW FUNCTIONS ───────────────────────────────────────────────────────────

export async function getInvoiceStatus(id: number): Promise<number> {
  try {
    const res = await aptos.view({
      payload: {
        function: `${MODULE('invoice')}::get_invoice_status` as `${string}::${string}::${string}`,
        typeArguments: [],
        functionArguments: [id.toString()],
      },
    });
    return Number(res[0]);
  } catch {
    throw new Error(`Invoice ${id} not found`);
  }
}

export async function getInvoiceDetails(id: number): Promise<Partial<Invoice>> {
  const [status, merchant, payer, amount] = await Promise.all([
    aptos.view({ payload: { function: `${MODULE('invoice')}::get_invoice_status` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
    aptos.view({ payload: { function: `${MODULE('invoice')}::get_invoice_merchant` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
    aptos.view({ payload: { function: `${MODULE('invoice')}::get_invoice_payer` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
    aptos.view({ payload: { function: `${MODULE('invoice')}::get_invoice_amount` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
  ]);
  return {
    id,
    status: STATUS_MAP[Number(status[0])],
    merchant: merchant[0] as string,
    payer: payer[0] as string,
    amount: BigInt(amount[0] as string),
  };
}

export async function getSubscriptionDetails(id: number): Promise<Partial<Subscription>> {
  const [active, cycles, amount] = await Promise.all([
    aptos.view({ payload: { function: `${MODULE('subscription')}::get_subscription_active` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
    aptos.view({ payload: { function: `${MODULE('subscription')}::get_subscription_cycles_used` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
    aptos.view({ payload: { function: `${MODULE('subscription')}::get_subscription_amount` as `${string}::${string}::${string}`, typeArguments: [], functionArguments: [id.toString()] } }),
  ]);
  return {
    id,
    active: Boolean(active[0]),
    cyclesUsed: Number(cycles[0]),
    amountPerCycle: BigInt(amount[0] as string),
  };
}

export async function isSubscriptionDue(id: number): Promise<boolean> {
  const res = await aptos.view({
    payload: {
      function: `${MODULE('subscription')}::is_due` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [id.toString()],
    },
  });
  return Boolean(res[0]);
}

export async function nextChargeTime(id: number): Promise<number> {
  const res = await aptos.view({
    payload: {
      function: `${MODULE('subscription')}::next_charge_time` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [id.toString()],
    },
  });
  return Number(res[0]);
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────

/** Format octas → APT string */
export function formatApt(octas: bigint | number): string {
  const n = typeof octas === 'bigint' ? octas : BigInt(octas);
  const whole = n / 100_000_000n;
  const frac  = n % 100_000_000n;
  if (frac === 0n) return `${whole} APT`;
  return `${whole}.${frac.toString().padStart(8, '0').replace(/0+$/, '')} APT`;
}

/** Shorten address for display */
export function shortAddr(addr: string): string {
  if (!addr || addr.length < 12) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/** Format unix seconds to locale date string */
export function formatDate(ts: number): string {
  return new Date(ts * 1000).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  });
}

/** Fetch recent transactions from Aptos Indexer for a given account */
export async function getAccountTransactions(address: string, limit = 10): Promise<Array<{
  hash: string;
  version: string;
  timestamp: string;
  type: string;
  success: boolean;
}>> {
  const network = process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet';
  const indexerUrl = network === 'mainnet'
    ? 'https://api.mainnet.aptoslabs.com/v1/graphql'
    : network === 'testnet'
    ? 'https://api.testnet.aptoslabs.com/v1/graphql'
    : 'https://api.devnet.aptoslabs.com/v1/graphql';

  const query = `
    query GetAccountTransactions($address: String!, $limit: Int!) {
      user_transactions(
        where: { sender: { _eq: $address } }
        order_by: { timestamp: desc }
        limit: $limit
      ) {
        hash
        version
        timestamp
        entry_function_id_str
        success
      }
    }
  `;

  try {
    const res = await fetch(indexerUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, variables: { address, limit } }),
    });
    const json = await res.json();
    return (json.data?.user_transactions ?? []).map((tx: {
      hash: string;
      version: string;
      timestamp: string;
      entry_function_id_str: string;
      success: boolean;
    }) => ({
      hash: tx.hash,
      version: tx.version,
      timestamp: tx.timestamp,
      type: tx.entry_function_id_str?.split('::').pop() ?? 'transaction',
      success: tx.success,
    }));
  } catch {
    return [];
  }
}
