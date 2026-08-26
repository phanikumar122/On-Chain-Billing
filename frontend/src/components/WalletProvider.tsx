'use client';
// components/WalletProvider.tsx — Aptos wallet adapter provider wrapper

import { AptosWalletAdapterProvider } from '@aptos-labs/wallet-adapter-react';
import { Network } from '@aptos-labs/ts-sdk';

const NETWORK = (process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet') as 'devnet' | 'testnet' | 'mainnet';
const networkMap: Record<string, Network> = {
  devnet: Network.DEVNET,
  testnet: Network.TESTNET,
  mainnet: Network.MAINNET,
};

export default function WalletProvider({ children }: { children: React.ReactNode }) {
  return (
    <AptosWalletAdapterProvider
      autoConnect={false}
      dappConfig={{ network: networkMap[NETWORK] ?? Network.DEVNET }}
      onError={(error) => console.error('Wallet error:', error)}
    >
      {children}
    </AptosWalletAdapterProvider>
  );
}
