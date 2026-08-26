'use client';
import Link from 'next/link';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { shortAddr } from '@/lib/contract';

const FEATURES = [
  { num: '01', title: 'On-Chain Invoices', desc: 'Create verifiable invoices with full lifecycle tracking: Pending → Paid → Resolved.' },
  { num: '02', title: 'Recurring Subscriptions', desc: 'Pull-model billing. Pre-authorize recurring payments enforced by smart contracts.' },
  { num: '03', title: 'Role-Based Access', desc: 'Strict admin controls for system pauses, token registration, and fee adjustments.' },
  { num: '04', title: 'Dispute Resolution', desc: 'Built-in on-chain arbitration for absolute transparency and auditability.' },
  { num: '05', title: 'Multi-Token Support', desc: 'Register any Aptos coin. Generic types ensure composable, safe billing.' },
  { num: '06', title: 'Gas Optimized', desc: 'O(1) lookups and batch-friendly design for minimal gas overhead.' },
];

const STATS = [
  { label: 'Network', value: process.env.NEXT_PUBLIC_APTOS_NETWORK?.toUpperCase() ?? 'DEVNET', sub: 'Environment' },
  { label: 'Modules', value: '7', sub: 'Deployed' },
  { label: 'Tests', value: '26', sub: 'Passing' },
];

export default function HomePage() {
  const { connected, account } = useWallet();

  return (
    <>
      <section className="hero">
        <div className="hero-badge">
          Built on Aptos Move
        </div>
        <h1>Decentralized<br />Billing Infrastructure</h1>
        <p>
          Create invoices, manage subscriptions, and process multi-token payments
          via trustless smart contracts — transparent, composable, and production-ready.
        </p>
        <div className="hero-actions">
          <Link href="/invoices" className="btn btn-primary">
            Manage Invoices
          </Link>
          <Link href="/subscriptions" className="btn btn-secondary">
            Subscriptions
          </Link>
        </div>

        {connected && account && (
          <div style={{ marginTop: '2rem' }}>
            <div className="alert alert-success" style={{ display: 'inline-flex', justifyContent: 'center' }}>
              <span style={{ fontWeight: 600 }}>Wallet Connected:</span>
              <span className="mono">{shortAddr(account.address.toString())}</span>
            </div>
          </div>
        )}
      </section>

      {/* Stats */}
      <div className="stats-grid" style={{ marginBottom: '3.5rem', maxWidth: '900px', margin: '0 auto 3.5rem' }}>
        {STATS.map(s => (
          <div key={s.label} className="stat-card" style={{ textAlign: 'center' }}>
            <div className="stat-label">{s.label}</div>
            <div className="stat-value">{s.value}</div>
            <div className="stat-sub">{s.sub}</div>
          </div>
        ))}
      </div>

      <hr className="section-divider" />

      {/* Features */}
      <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
        <h2 style={{ fontSize: '1.5rem', fontWeight: 700, letterSpacing: '-0.02em', marginBottom: '0.5rem' }}>
          Platform Architecture
        </h2>
        <p style={{ color: 'var(--text-secondary)', maxWidth: 480, margin: '0 auto', fontSize: '0.9375rem' }}>
          Seven independently-tested Move modules forming a composable billing primitive.
        </p>
      </div>

      <div className="bento-grid">
        {FEATURES.map(f => (
          <div key={f.num} className="bento-card">
            <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--accent-primary)', letterSpacing: '0.05em', marginBottom: '8px' }}>
              {f.num}
            </div>
            <div className="bento-title">{f.title}</div>
            <div className="bento-desc">{f.desc}</div>
          </div>
        ))}
      </div>
    </>
  );
}
