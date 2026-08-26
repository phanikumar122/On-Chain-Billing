'use client';
import React from 'react';

interface Props { children: React.ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export default class ErrorBoundary extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('[ChainBill ErrorBoundary]', error, info.componentStack);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
          minHeight: '40vh', textAlign: 'center', padding: '3rem 2rem',
        }}>
          <div style={{
            width: 48, height: 48, borderRadius: 8,
            background: 'rgba(248, 113, 113, 0.1)',
            border: '1px solid rgba(248, 113, 113, 0.2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: '1.25rem', marginBottom: '1.5rem',
          }}>
            ×
          </div>
          <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '0.5rem' }}>
            Something went wrong
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', marginBottom: '1.5rem', maxWidth: 480 }}>
            {this.state.error?.message ?? 'An unexpected error occurred. This may be a network issue or a contract call failure.'}
          </p>
          <div style={{ display: 'flex', gap: 12 }}>
            <button
              className="btn btn-primary"
              onClick={() => this.setState({ hasError: false, error: null })}
            >
              Try Again
            </button>
            <a href="/" className="btn btn-secondary">
              Back to Dashboard
            </a>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
