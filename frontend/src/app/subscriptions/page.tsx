'use client';
import { useState, useCallback } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import {
  buildAuthorizeSubscription, buildCharge, buildCancelSubscription,
  getSubscriptionDetails, isSubscriptionDue, nextChargeTime,
  formatApt, DEFAULT_COIN, isValidAddress,
} from '@/lib/contract';
import { Subscription } from '@/lib/types';

type ModalType = 'authorize' | 'charge' | 'cancel' | null;

interface TxLog { hash: string; action: string; ts: number; }

function AptCalc({ octas }: { octas: string }) {
  const n = Number(octas);
  if (!octas || isNaN(n) || n <= 0) return null;
  return <div className="apt-calc">≈ {(n / 1e8).toFixed(n < 1e6 ? 6 : 4)} APT / cycle</div>;
}

const INTERVALS = [
  { label: 'Daily (86,400s)',        value: '86400' },
  { label: 'Weekly (604,800s)',      value: '604800' },
  { label: 'Monthly (2,592,000s)',   value: '2592000' },
  { label: 'Yearly (31,536,000s)',  value: '31536000' },
];

export default function SubscriptionsPage() {
  const { connected, signAndSubmitTransaction } = useWallet();
  const [modal, setModal] = useState<ModalType>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [txLog, setTxLog] = useState<TxLog[]>([]);
  const [lookupId, setLookupId] = useState('');
  const [lookedUp, setLookedUp] = useState<(Partial<Subscription> & { isDue?: boolean; nextCharge?: number }) | null>(null);
  const [lookupError, setLookupError] = useState('');
  const [actionId, setActionId] = useState('');
  const [authForm, setAuthForm] = useState({
    merchant: '', amount: '', interval: '2592000', maxCycles: '12', coinType: DEFAULT_COIN,
  });
  const [chargeCoinType, setChargeCoinType] = useState(DEFAULT_COIN);

  const toast = useCallback((type: 'success' | 'error', text: string) => {
    setMsg({ type, text }); setTimeout(() => setMsg(null), 5000);
  }, []);

  async function submit(payload: unknown, label: string) {
    if (!connected) return toast('error', 'Connect your wallet first');
    setLoading(true);
    try {
      const res = await signAndSubmitTransaction(payload as Parameters<typeof signAndSubmitTransaction>[0]);
      const hash = (res as { hash: string }).hash ?? '';
      toast('success', `✓ ${label} — tx: ${hash.slice(0, 16)}…`);
      setTxLog(prev => [{ hash, action: label, ts: Date.now() }, ...prev.slice(0, 9)]);
      setModal(null);
    } catch (e: unknown) {
      toast('error', (e as { message?: string }).message ?? 'Transaction failed');
    }
    setLoading(false);
  }

  async function lookup() {
    setLookupError(''); setLookedUp(null);
    if (!lookupId) return;
    try {
      const [data, due, next] = await Promise.all([
        getSubscriptionDetails(Number(lookupId)),
        isSubscriptionDue(Number(lookupId)).catch(() => false),
        nextChargeTime(Number(lookupId)).catch(() => 0),
      ]);
      setLookedUp({ ...data, isDue: due as boolean, nextCharge: next as number });
    } catch {
      setLookupError(`Subscription #${lookupId} not found or contract not deployed.`);
    }
  }

  const cyclesUsed = lookedUp?.cyclesUsed ?? 0;
  const maxCycles = lookedUp?.maxCycles ?? 1;
  const cyclePercent = Math.min(100, Math.round((cyclesUsed / maxCycles) * 100));

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Subscriptions</h1>
          <p className="page-subtitle">Authorize and manage recurring on-chain payments</p>
        </div>
        <button className="btn btn-primary"
          onClick={() => { if (!connected) toast('error', 'Connect wallet first'); else setModal('authorize'); }}>
          + Authorize Subscription
        </button>
      </div>

      {msg && (
        <div className={`alert alert-${msg.type}`} style={{ marginBottom: 16 }}>{msg.text}</div>
      )}

      {/* How it works */}
      <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
        <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 14 }}>How Pull-Model Subscriptions Work</h2>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(190px,1fr))', gap: 16 }}>
          {[
            { step: '1', title: 'Authorize', desc: 'Sign an on-chain allowance: amount, interval, max cycles.' },
            { step: '2', title: 'Charge', desc: 'Anyone calls charge(). Contract enforces timing — no trusted scheduler needed.' },
            { step: '3', title: 'Auto-stop', desc: 'Subscription deactivates automatically after max_cycles.' },
          ].map(({ step, title, desc }) => (
            <div key={step} style={{ display: 'flex', gap: 12 }}>
              <span style={{ minWidth: 28, height: 28, borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', border: '1px solid rgba(16, 185, 129, 0.3)', color: 'var(--accent-primary)', fontSize: '0.8125rem', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{step}</span>
              <div>
                <div style={{ fontWeight: 600, fontSize: '0.875rem', marginBottom: 4 }}>{title}</div>
                <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>{desc}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Lookup */}
      <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
        <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 16 }}>Look Up Subscription</h2>
        <div style={{ display: 'flex', gap: 10 }}>
          <input className="form-input" placeholder="Subscription ID" value={lookupId}
            onChange={e => setLookupId(e.target.value)} type="number" style={{ maxWidth: 200 }}
            onKeyDown={e => e.key === 'Enter' && lookup()} />
          <button className="btn btn-secondary" onClick={lookup}>Look Up</button>
        </div>
        {lookupError && <p style={{ color: 'var(--error)', fontSize: '0.8125rem', marginTop: 10 }}>{lookupError}</p>}
        {lookedUp && (
          <div style={{ marginTop: 16 }}>
            <div className="table-wrap" style={{ marginBottom: 12 }}>
              <table className="data-table">
                <tbody>
                  <tr><td style={{ color: 'var(--text-muted)', width: 140 }}>ID</td><td>#{lookedUp.id}</td></tr>
                  <tr>
                    <td style={{ color: 'var(--text-muted)' }}>Status</td>
                    <td><span className={`badge badge-${lookedUp.active ? 'paid' : 'pending'}`}>{lookedUp.active ? 'Active' : 'Inactive'}</span></td>
                  </tr>
                  <tr>
                    <td style={{ color: 'var(--text-muted)' }}>Cycles Progress</td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                        <span>{cyclesUsed} / {maxCycles}</span>
                        <div style={{ width: 120, height: 6, background: '#27272a', borderRadius: 3, overflow: 'hidden' }}>
                          <div style={{ width: `${cyclePercent}%`, height: '100%', background: 'var(--accent-primary)' }} />
                        </div>
                      </div>
                    </td>
                  </tr>
                  <tr><td style={{ color: 'var(--text-muted)' }}>Amount / Cycle</td><td style={{ fontWeight: 600 }}>{lookedUp.amountPerCycle !== undefined ? formatApt(lookedUp.amountPerCycle) : '—'}</td></tr>
                  <tr>
                    <td style={{ color: 'var(--text-muted)' }}>Is Due?</td>
                    <td><span style={{ color: lookedUp.isDue ? 'var(--success)' : 'var(--text-muted)' }}>{lookedUp.isDue ? '✓ Due now' : 'Not yet due'}</span></td>
                  </tr>
                  <tr>
                    <td style={{ color: 'var(--text-muted)' }}>Next Charge</td>
                    <td>{lookedUp.nextCharge ? new Date(lookedUp.nextCharge * 1000).toLocaleString() : 'Immediately'}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            {lookedUp.active && (
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <button className="btn btn-primary btn-sm" disabled={!lookedUp.isDue}
                  onClick={() => { setActionId(String(lookedUp.id)); setModal('charge'); }}>
                  {lookedUp.isDue ? 'Charge Now' : 'Not Due Yet'}
                </button>
                <button className="btn btn-danger btn-sm"
                  onClick={() => { setActionId(String(lookedUp.id)); setModal('cancel'); }}>
                  Cancel Sub
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Tx Log */}
      {txLog.length > 0 && (
        <div className="glass-card" style={{ padding: 24 }}>
          <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 14 }}>Session Activity</h2>
          <div style={{ display: 'grid', gap: 8 }}>
            {txLog.map((tx, i) => (
              <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px', background: 'rgba(255,255,255,0.02)', borderRadius: 6, fontSize: '0.8125rem' }}>
                <span style={{ color: 'var(--success)' }}>✓ {tx.action}</span>
                <a href={`https://explorer.aptoslabs.com/txn/${tx.hash}?network=${process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet'}`}
                  target="_blank" rel="noopener noreferrer"
                  className="mono" style={{ color: 'var(--accent-primary)', fontSize: '0.75rem' }}>
                  {tx.hash.slice(0, 14)}…
                </a>
                <span style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{new Date(tx.ts).toLocaleTimeString()}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Authorize Modal */}
      {modal === 'authorize' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Authorize Subscription</div></div>
            <div className="form-group">
              <label className="form-label">Merchant Address *</label>
              <input className="form-input" placeholder="0x..." value={authForm.merchant}
                style={{ borderColor: authForm.merchant && !isValidAddress(authForm.merchant) ? 'var(--error)' : undefined }}
                onChange={e => setAuthForm(f => ({ ...f, merchant: e.target.value }))} />
              {authForm.merchant && !isValidAddress(authForm.merchant) && (
                <div className="form-hint" style={{ color: 'var(--error)' }}>Invalid address format.</div>
              )}
            </div>
            <div className="form-group">
              <label className="form-label">Amount per Cycle (octas) *</label>
              <input className="form-input" type="number" placeholder="e.g. 10000000 = 0.1 APT"
                value={authForm.amount} onChange={e => setAuthForm(f => ({ ...f, amount: e.target.value }))} />
              <AptCalc octas={authForm.amount} />
            </div>
            <div className="form-group">
              <label className="form-label">Interval Preset</label>
              <select className="form-select" value={authForm.interval}
                onChange={e => setAuthForm(f => ({ ...f, interval: e.target.value }))}>
                {INTERVALS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">Max Cycles *</label>
              <input className="form-input" type="number" min="1" value={authForm.maxCycles}
                onChange={e => setAuthForm(f => ({ ...f, maxCycles: e.target.value }))} />
              <div className="form-hint">Subscription automatically deactivates after this many charges</div>
            </div>
            <div className="form-group">
              <label className="form-label">Coin Type</label>
              <input className="form-input" value={authForm.coinType}
                onChange={e => setAuthForm(f => ({ ...f, coinType: e.target.value }))} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button className="btn btn-primary"
                disabled={loading || !authForm.merchant || !isValidAddress(authForm.merchant) || !authForm.amount}
                onClick={() => submit(
                  buildAuthorizeSubscription(authForm.merchant, authForm.amount, Number(authForm.interval), Number(authForm.maxCycles), authForm.coinType),
                  'Authorize subscription'
                )}>
                {loading ? <span className="spinner" /> : 'Authorize'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Charge Modal */}
      {modal === 'charge' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Charge Subscription #{actionId}</div></div>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', marginBottom: 16 }}>
              Pulls the next cycle payment. Contract enforces all timing and cap rules.
            </p>
            <div className="form-group">
              <label className="form-label">Coin Type</label>
              <input className="form-input" value={chargeCoinType} onChange={e => setChargeCoinType(e.target.value)} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading}
                onClick={() => submit(buildCharge(Number(actionId), chargeCoinType), `Charge sub #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Charge Now'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Cancel Sub Modal */}
      {modal === 'cancel' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Cancel Subscription #{actionId}</div></div>
            <div className="alert alert-warning" style={{ marginBottom: 16 }}>
              Only the subscriber or admin can cancel. Stops all future charges immediately.
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Back</button>
              <button className="btn btn-danger" disabled={loading}
                onClick={() => submit(buildCancelSubscription(Number(actionId)), `Cancel sub #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Cancel Subscription'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
