// lib/aptos.ts — Aptos SDK client singleton
import { Aptos, AptosConfig, Network } from '@aptos-labs/ts-sdk';

const networkMap: Record<string, Network> = {
  devnet:  Network.DEVNET,
  testnet: Network.TESTNET,
  mainnet: Network.MAINNET,
};

const rawNetwork = process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet';
const network = networkMap[rawNetwork] ?? Network.DEVNET;

export const aptosConfig = new AptosConfig({ network });
export const aptos = new Aptos(aptosConfig);

export const BILLING_ADDRESS = process.env.NEXT_PUBLIC_BILLING_ADDRESS ?? '';
if (!BILLING_ADDRESS) {
  if (typeof window === 'undefined') {
    // Only throw at build/server-time to give a clear error
    console.error(
      '[ChainBill] NEXT_PUBLIC_BILLING_ADDRESS is not set. ' +
      'Add it to your .env.local file.'
    );
  }
}

export const MODULE = (mod: string) => `${BILLING_ADDRESS}::${mod}`;
