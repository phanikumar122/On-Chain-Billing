import type { Metadata } from 'next';
import './globals.css';
import Navbar from '@/components/Navbar';
import Footer from '@/components/Footer';
import WalletProvider from '@/components/WalletProvider';
import ErrorBoundary from '@/components/ErrorBoundary';

export const metadata: Metadata = {
  title: 'ChainBill — On-Chain Billing & Payments',
  description: 'Decentralized invoicing, recurring subscriptions, and multi-token billing powered by Aptos Move.',
  keywords: ['Aptos', 'blockchain', 'billing', 'invoice', 'subscription', 'DeFi'],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <WalletProvider>
          <div className="app-shell">
            <Navbar />
            <main className="main-content">
              <ErrorBoundary>
                {children}
              </ErrorBoundary>
            </main>
            <Footer />
          </div>
        </WalletProvider>
      </body>
    </html>
  );
}
