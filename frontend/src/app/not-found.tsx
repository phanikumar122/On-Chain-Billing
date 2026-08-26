import Link from 'next/link';

export default function NotFound() {
  return (
    <div style={{ textAlign: 'center', padding: '5rem 1rem' }}>
      <div style={{ fontSize: '5rem', marginBottom: '1.5rem', opacity: 0.4 }}>⬡</div>
      <h1 style={{ fontSize: 'clamp(1.75rem,4vw,3rem)', fontWeight: 800, letterSpacing: '-0.04em', marginBottom: '1rem' }}>
        404 — Page Not Found
      </h1>
      <p style={{ color: 'var(--text-secondary)', marginBottom: '2rem', maxWidth: 400, margin: '0 auto 2rem' }}>
        This route doesn&apos;t exist on-chain or off-chain. Head back to the dashboard.
      </p>
      <Link href="/" className="btn btn-primary">← Back to Dashboard</Link>
    </div>
  );
}
