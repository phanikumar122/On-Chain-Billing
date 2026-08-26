'use client';
import { useState, useEffect } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import {
  buildPause, buildUnpause, buildSetFeeBps,
  buildGrantAdmin, buildRevokeAdmin, buildRegisterToken,
  getAdminStatus, getTreasuryBalance, getAccountTransactions,
  formatApt, shortAddr, DEFAULT_COIN,
} from '@/lib/contract';

type ActionKey = 'pause'|'unpause'|'fee'|'grant'|'revoke'|'token' | null;

const ACTIONS = [
  { key: 'pause',   icon: '!', label: 'Pause System',    desc: 'Halt all billing operations (emergency stop)', danger: true },
  { key: 'unpause', icon: '>', label: 'Unpause System',  desc: 'Resume billing after emergency stop', danger: false },
  { key: 'fee',     icon: '$', label: 'Set Platform Fee', desc: 'Configure platform fee in basis points (100 = 1%)', danger: false },
  { key: 'grant',   icon: '+', label: 'Grant Admin',     desc: 'Transfer admin role to another address', danger: true },
  { key: 'revoke',  icon: '-', label: 'Revoke Admin',    desc: 'Revoke admin rights from an address', danger: true },
  { key: 'token',   icon: '*', label: 'Register Token',  desc: 'Whitelist a new CoinType for billing', danger: false },
] as const;

interface SystemStatus { feeBps: number; admin: string; isPaused: boolean; }
interface TxEntry { hash: string; version: string; timestamp: string; type: string; success: boolean; }

export default function AdminPage() {
  const { connected, signAndSubmitTransaction, account } = useWallet();
  const [action, setAction] = useState<ActionKey>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [feeBps, setFeeBps] = useState('');
  const [grantAddr, setGrantAddr] = useState('');
  const [revokeAddr, setRevokeAddr] = useState('');
  const [tokenType, setTokenType] = useState(DEFAULT_COIN);

  // System status from chain
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [treasury, setTreasury] = useState<bigint | null>(null);
  const [txHistory, setTxHistory] = useState<TxEntry[]>([]);
  const [statusLoading, setStatusLoading] = useState(false);

  const toast = (type: 'success' | 'error', text: string) => {
    setMsg({ type, text }); setTimeout(() => setMsg(null), 5000);
  };

  useEffect(() => {
    async function loadStatus() {
      setStatusLoading(true);
      try {
        const [s, t] = await Promise.all([getAdminStatus(), getTreasuryBalance()]);
        setStatus(s);
        setTreasury(t);
      } catch { /* contract may not be deployed */ }
      setStatusLoading(false);
    }
    loadStatus();
  }, []);

  useEffect(() => {
    async function loadTxHistory() {
      if (!account) return;
      const txs = await getAccountTransactions(account.address.toString(), 8);
      setTxHistory(txs);
    }
    loadTxHistory();
  }, [account]);

  async function submit(payload: unknown) {
    if (!connected) return toast('error', 'Connect your wallet first');
    setLoading(true);
    try {
      const res = await signAndSubmitTransaction(payload as Parameters<typeof signAndSubmitTransaction>[0]);
      toast('success', `Transaction submitted: ${(res as { hash: string }).hash?.slice(0, 24)}…`);
      setAction(null);
      // Re-fetch status after action
      const [s, t] = await Promise.all([getAdminStatus(), getTreasuryBalance()]).catch(() => [null, null]);
      if (s) setStatus(s as SystemStatus);
      if (t !== null) setTreasury(t as bigint);
    } catch (e: unknown) {
      toast('error', (e as { message?: string }).message ?? 'Transaction failed');
    }
    setLoading(false);
  }

  const network = process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet';
  const explorerBase = `https://explorer.aptoslabs.com/txn`;

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Admin Panel</h1>
          <p className="page-subtitle">Administrative controls for the on-chain billing system</p>
        </div>
      </div>

      {msg && (
        <div className={`alert alert-${msg.type}`} style={{ marginBottom: 16 }}>
          {msg.type === 'success' ? '✓' : '✗'} {msg.text}
        </div>
      )}

      {!connected && (
        <div className="alert alert-warning" style={{ marginBottom: 24 }}>
          Connect your wallet and ensure it is the admin address to execute admin functions.
        </div>
      )}

      {/* System Status Panel */}
      <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
          <h2 style={{ fontSize: '1rem', fontWeight: 600 }}>System Status</h2>
          {statusLoading && <span className="spinner" />}
        </div>
        {status ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 16 }}>
            <div className="glass-card" style={{ padding: '16px 20px' }}>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>System State</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ width: 8, height: 8, borderRadius: '50%', background: status.isPaused ? 'var(--error)' : 'var(--success)', flexShrink: 0 }} />
                <span style={{ fontWeight: 600, fontSize: '1rem' }}>{status.isPaused ? 'Paused' : 'Operational'}</span>
              </div>
            </div>
            <div className="glass-card" style={{ padding: '16px 20px' }}>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>Platform Fee</div>
              <div style={{ fontWeight: 600, fontSize: '1rem' }}>
                {status.feeBps} bps <span style={{ color: 'var(--text-muted)', fontWeight: 400, fontSize: '0.875rem' }}>({status.feeBps / 100}%)</span>
              </div>
            </div>
            <div className="glass-card" style={{ padding: '16px 20px' }}>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>Current Admin</div>
              <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: '0.875rem', fontWeight: 600 }}>
                {shortAddr(status.admin)}
              </div>
            </div>
            <div className="glass-card" style={{ padding: '16px 20px' }}>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>Treasury Balance</div>
              <div style={{ fontWeight: 600, fontSize: '1rem' }}>
                {treasury !== null ? formatApt(treasury) : '—'}
              </div>
            </div>
          </div>
        ) : !statusLoading ? (
          <p style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>
            Could not load system status. Ensure the contract is deployed and NEXT_PUBLIC_BILLING_ADDRESS is set.
          </p>
        ) : null}
      </div>

      {/* Action Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(280px,1fr))', gap: 16, marginBottom: 24 }}>
        {ACTIONS.map(({ key, label, desc, danger }) => (
          <div
            key={key}
            className="glass-card"
            style={{ padding: 24, cursor: 'pointer', position: 'relative', overflow: 'hidden' }}
            onClick={() => setAction(key as ActionKey)}
          >
            {danger && (
              <div style={{ position: 'absolute', top: 12, right: 12, fontSize: '0.7rem', fontWeight: 600, color: 'var(--error)', background: 'rgba(248,113,113,0.1)', padding: '2px 8px', borderRadius: 4, border: '1px solid rgba(248,113,113,0.2)' }}>
                RESTRICTED
              </div>
            )}
            <div style={{ fontWeight: 600, marginBottom: 6, fontSize: '1rem' }}>{label}</div>
            <div style={{ fontSize: '0.8125rem', color: 'var(--text-secondary)', lineHeight: 1.5, marginBottom: 16 }}>{desc}</div>
            <span className={`btn btn-sm ${danger ? 'btn-danger' : 'btn-secondary'}`} style={{ pointerEvents: 'none' }}>
              Configure →
            </span>
          </div>
        ))}
      </div>

      {/* Transaction History from Indexer */}
      {account && txHistory.length > 0 && (
        <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
          <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 16 }}>Recent Wallet Transactions</h2>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Function</th>
                  <th>Status</th>
                  <th>Timestamp</th>
                  <th>Hash</th>
                </tr>
              </thead>
              <tbody>
                {txHistory.map(tx => (
                  <tr key={tx.hash}>
                    <td style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: '0.8rem' }}>{tx.type}</td>
                    <td>
                      <span style={{
                        display: 'inline-flex', alignItems: 'center', gap: 5,
                        fontSize: '0.75rem', fontWeight: 600,
                        color: tx.success ? 'var(--success)' : 'var(--error)',
                      }}>
                        <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'currentColor', display: 'inline-block' }} />
                        {tx.success ? 'Success' : 'Failed'}
                      </span>
                    </td>
                    <td style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
                      {new Date(tx.timestamp).toLocaleString()}
                    </td>
                    <td>
                      <a
                        href={`${explorerBase}/${tx.hash}?network=${network}`}
                        target="_blank" rel="noopener noreferrer"
                        style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: '0.75rem', color: 'var(--text-secondary)', textDecoration: 'none' }}
                      >
                        {tx.hash.slice(0, 12)}…
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Modals ── */}

      {/* Pause */}
      {action === 'pause' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Pause System</div></div>
            <div className="alert alert-error" style={{ marginBottom: 16 }}>
              This will prevent ALL billing operations (create/pay invoices, authorize/charge subscriptions) until unpaused.
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-danger" disabled={loading} onClick={() => submit(buildPause())}>
                {loading ? <span className="spinner" /> : 'Pause System'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Unpause */}
      {action === 'unpause' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Unpause System</div></div>
            <p style={{ color: 'var(--text-secondary)', marginBottom: 20, fontSize: '0.875rem' }}>Resume all billing operations.</p>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading} onClick={() => submit(buildUnpause())}>
                {loading ? <span className="spinner" /> : 'Unpause System'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Set Fee */}
      {action === 'fee' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Set Platform Fee</div></div>
            <div className="form-group">
              <label className="form-label">Fee in Basis Points</label>
              <input className="form-input" type="number" min="0" max="10000" placeholder="e.g. 50 = 0.5%" value={feeBps} onChange={e => setFeeBps(e.target.value)} />
              <div className="form-hint">100 bps = 1% · Max: 10,000 bps (100%) · 0 = no fee</div>
            </div>
            {feeBps && (
              <div className="alert alert-warning">
                Platform will collect {Number(feeBps) / 100}% on every invoice payment and subscription charge.
              </div>
            )}
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading || !feeBps} onClick={() => submit(buildSetFeeBps(Number(feeBps)))}>
                {loading ? <span className="spinner" /> : 'Set Fee'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Grant Admin */}
      {action === 'grant' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Grant Admin</div></div>
            <div className="alert alert-error" style={{ marginBottom: 16 }}>Warning: This transfers full admin control. Verify the address carefully.</div>
            <div className="form-group">
              <label className="form-label">New Admin Address *</label>
              <input className="form-input" placeholder="0x..." value={grantAddr} onChange={e => setGrantAddr(e.target.value)} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-danger" disabled={loading || !grantAddr} onClick={() => submit(buildGrantAdmin(grantAddr))}>
                {loading ? <span className="spinner" /> : 'Grant Admin'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Revoke Admin */}
      {action === 'revoke' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Revoke Admin</div></div>
            <div className="form-group">
              <label className="form-label">Target Address *</label>
              <input className="form-input" placeholder="0x..." value={revokeAddr} onChange={e => setRevokeAddr(e.target.value)} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-danger" disabled={loading || !revokeAddr} onClick={() => submit(buildRevokeAdmin(revokeAddr))}>
                {loading ? <span className="spinner" /> : 'Revoke Admin'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Register Token */}
      {action === 'token' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setAction(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setAction(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Register Token</div></div>
            <div className="form-group">
              <label className="form-label">Coin Type *</label>
              <input className="form-input" value={tokenType} onChange={e => setTokenType(e.target.value)} />
              <div className="form-hint">Full Move type path, e.g. 0x1::aptos_coin::AptosCoin</div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAction(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading || !tokenType} onClick={() => submit(buildRegisterToken(tokenType))}>
                {loading ? <span className="spinner" /> : 'Register Token'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
