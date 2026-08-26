'use client';
import Link from 'next/link';
import { shortAddr } from '@/lib/contract';
import { BILLING_ADDRESS } from '@/lib/aptos';

const NETWORK = process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet';

export default function Footer() {
  return (
    <footer style={{
      marginTop: 'auto',
      borderTop: '1px solid var(--border)',
      background: 'var(--bg-main)',
      padding: '2rem 1.5rem',
      fontSize: '0.8125rem',
      color: 'var(--text-muted)'
    }}>
      <div style={{
        maxWidth: 1200,
        margin: '0 auto',
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: 16
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>ChainBill</span>
          <span>•</span>
          <span>Aptos Move On-Chain Billing</span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <span>Contract: <code className="mono" style={{ color: 'var(--text-secondary)' }}>{shortAddr(BILLING_ADDRESS)}</code></span>
          <span>•</span>
          <a
            href={`https://explorer.aptoslabs.com/account/${BILLING_ADDRESS}?network=${NETWORK}`}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: 'var(--accent-primary)', textDecoration: 'none' }}
          >
            Aptos Explorer →
          </a>
        </div>
      </div>
    </footer>
  );
}
