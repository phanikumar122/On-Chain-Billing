'use client';
import { useState, useCallback } from 'react';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import {
  buildCreateInvoice, buildPayInvoice, buildCancelInvoice,
  buildFlagDispute, buildResolveDispute,
  getInvoiceDetails, formatApt, shortAddr, formatDate,
  DEFAULT_COIN, isValidAddress,
} from '@/lib/contract';
import { Invoice, STATUS_MAP } from '@/lib/types';

type ModalType = 'create' | 'pay' | 'cancel' | 'dispute' | 'resolve' | null;

interface TxLog {
  hash: string;
  action: string;
  ts: number;
}

function StatusBadge({ status }: { status: string }) {
  return <span className={`badge badge-${status.toLowerCase()}`}>{status}</span>;
}

/** Inline APT ↔ octas calculator chip */
function AptCalc({ octas }: { octas: string }) {
  const n = Number(octas);
  if (!octas || isNaN(n) || n <= 0) return null;
  return (
    <div className="apt-calc">
      ≈ {(n / 1e8).toFixed(n < 1e6 ? 6 : 4)} APT
    </div>
  );
}

export default function InvoicesPage() {
  const { connected, signAndSubmitTransaction, account } = useWallet();
  const [modal, setModal] = useState<ModalType>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [txLog, setTxLog] = useState<TxLog[]>([]);

  // Lookup state
  const [lookupId, setLookupId] = useState('');
  const [lookedUp, setLookedUp] = useState<Partial<Invoice> | null>(null);
  const [lookupError, setLookupError] = useState('');

  // Form state — Create
  const [createForm, setCreateForm] = useState({
    payer: '', amount: '', dueDate: '', memo: '', coinType: DEFAULT_COIN,
  });
  // Action state
  const [actionId, setActionId] = useState('');
  const [disputeReason, setDisputeReason] = useState('');
  const [upheld, setUpheld] = useState(true);
  const [payCoinType, setPayCoinType] = useState(DEFAULT_COIN);

  const toast = useCallback((type: 'success' | 'error', text: string) => {
    setMsg({ type, text });
    setTimeout(() => setMsg(null), 5000);
  }, []);

  async function submit(payload: unknown, actionLabel: string) {
    if (!connected) return toast('error', 'Connect your wallet first');
    setLoading(true);
    try {
      const res = await signAndSubmitTransaction(
        payload as Parameters<typeof signAndSubmitTransaction>[0]
      );
      const hash = (res as { hash: string }).hash ?? '';
      toast('success', `✓ ${actionLabel} — tx: ${hash.slice(0, 16)}…`);
      setTxLog(prev => [{ hash, action: actionLabel, ts: Date.now() }, ...prev.slice(0, 9)]);
      setModal(null);
    } catch (e: unknown) {
      toast('error', (e as { message?: string }).message ?? 'Transaction failed');
    }
    setLoading(false);
  }

  async function lookupInvoice() {
    setLookupError(''); setLookedUp(null);
    if (!lookupId) return;
    try {
      const data = await getInvoiceDetails(Number(lookupId));
      setLookedUp(data);
    } catch {
      setLookupError(`Invoice #${lookupId} not found or contract not deployed.`);
    }
  }

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Invoices</h1>
          <p className="page-subtitle">Create, pay, and manage on-chain invoices</p>
        </div>
        <button
          className="btn btn-primary"
          onClick={() => { if (!connected) toast('error', 'Connect wallet first'); else setModal('create'); }}
        >
          + New Invoice
        </button>
      </div>

      {msg && (
        <div className={`alert alert-${msg.type}`} style={{ marginBottom: 16 }}>
          {msg.text}
        </div>
      )}

      {/* Lookup */}
      <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
        <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 16 }}>Look Up Invoice</h2>
        <div style={{ display: 'flex', gap: 10 }}>
          <input
            className="form-input" placeholder="Invoice ID (e.g. 0)"
            value={lookupId} onChange={e => setLookupId(e.target.value)}
            type="number" style={{ maxWidth: 200 }}
            onKeyDown={e => e.key === 'Enter' && lookupInvoice()}
          />
          <button className="btn btn-secondary" onClick={lookupInvoice}>Look Up</button>
        </div>
        {lookupError && <p style={{ color: 'var(--error)', fontSize: '0.8125rem', marginTop: 10 }}>{lookupError}</p>}
        {lookedUp && (
          <div style={{ marginTop: 16 }}>
            <div className="table-wrap" style={{ marginBottom: 12 }}>
              <table className="data-table">
                <tbody>
                  <tr><td style={{ color: 'var(--text-muted)', width: 130 }}>ID</td><td>#{lookedUp.id}</td></tr>
                  <tr><td style={{ color: 'var(--text-muted)' }}>Status</td><td><StatusBadge status={lookedUp.status ?? 'Unknown'} /></td></tr>
                  <tr><td style={{ color: 'var(--text-muted)' }}>Merchant</td><td className="mono">{shortAddr(lookedUp.merchant ?? '')}</td></tr>
                  <tr><td style={{ color: 'var(--text-muted)' }}>Payer</td><td className="mono">{shortAddr(lookedUp.payer ?? '')}</td></tr>
                  <tr><td style={{ color: 'var(--text-muted)' }}>Amount</td><td style={{ fontWeight: 600 }}>{lookedUp.amount !== undefined ? formatApt(lookedUp.amount) : '—'}</td></tr>
                </tbody>
              </table>
            </div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {lookedUp.status === 'Pending' && (
                <>
                  <button className="btn btn-primary btn-sm" onClick={() => { setActionId(String(lookedUp.id)); setModal('pay'); }}>Pay</button>
                  <button className="btn btn-ghost btn-sm" onClick={() => { setActionId(String(lookedUp.id)); setModal('cancel'); }}>Cancel</button>
                  <button className="btn btn-danger btn-sm" onClick={() => { setActionId(String(lookedUp.id)); setModal('dispute'); }}>Dispute</button>
                </>
              )}
              {lookedUp.status === 'Disputed' && (
                <button className="btn btn-secondary btn-sm" onClick={() => { setActionId(String(lookedUp.id)); setModal('resolve'); }}>Resolve (Admin)</button>
              )}
            </div>
          </div>
        )}
      </div>

      {/* State machine reference */}
      <div className="glass-card" style={{ padding: 24, marginBottom: 24 }}>
        <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 12 }}>Invoice State Machine</h2>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'center', fontSize: '0.875rem' }}>
          {['Pending', 'Paid', 'Cancelled', 'Disputed'].map((s, i, arr) => (
            <span key={s} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <StatusBadge status={s} />
              {i < arr.length - 1 && <span style={{ color: 'var(--text-muted)' }}>→</span>}
            </span>
          ))}
        </div>
        <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem', marginTop: 10 }}>
          Disputed → Paid (merchant wins) or Disputed → Cancelled (payer wins). Only admin resolves disputes.
        </p>
      </div>

      {/* Tx Activity Log */}
      {txLog.length > 0 && (
        <div className="glass-card" style={{ padding: 24 }}>
          <h2 style={{ fontSize: '1rem', fontWeight: 600, marginBottom: 14 }}>Session Activity</h2>
          <div style={{ display: 'grid', gap: 8 }}>
            {txLog.map((tx, i) => (
              <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px', background: 'rgba(255,255,255,0.03)', borderRadius: 8, fontSize: '0.8125rem' }}>
                <span style={{ color: 'var(--success)' }}>✓ {tx.action}</span>
                <a
                  href={`https://explorer.aptoslabs.com/txn/${tx.hash}?network=${process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet'}`}
                  target="_blank" rel="noopener noreferrer"
                  className="mono" style={{ color: 'var(--accent)', fontSize: '0.75rem' }}
                >
                  {tx.hash.slice(0, 14)}…
                </a>
                <span style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>
                  {new Date(tx.ts).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── MODALS ── */}

      {/* Create Invoice */}
      {modal === 'create' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Create Invoice</div></div>
            <div className="form-group">
              <label className="form-label">Payer Address *</label>
              <input className="form-input" placeholder="0x..."
                value={createForm.payer} style={{ borderColor: createForm.payer && !isValidAddress(createForm.payer) ? 'var(--error)' : undefined }}
                onChange={e => setCreateForm(f => ({ ...f, payer: e.target.value }))} />
              {createForm.payer && !isValidAddress(createForm.payer) && (
                <div className="form-hint" style={{ color: 'var(--error)' }}>Invalid Aptos address. Must start with 0x followed by hex characters.</div>
              )}
            </div>
            <div className="form-group">
              <label className="form-label">Amount (octas) *</label>
              <input className="form-input" type="number" placeholder="100000000 = 1 APT"
                value={createForm.amount} onChange={e => setCreateForm(f => ({ ...f, amount: e.target.value }))} />
              <AptCalc octas={createForm.amount} />
            </div>
            <div className="form-group">
              <label className="form-label">Due Date *</label>
              <input className="form-input" type="date" value={createForm.dueDate}
                onChange={e => setCreateForm(f => ({ ...f, dueDate: e.target.value }))} />
            </div>
            <div className="form-group">
              <label className="form-label">Memo</label>
              <input className="form-input" placeholder="Invoice description..."
                value={createForm.memo} onChange={e => setCreateForm(f => ({ ...f, memo: e.target.value }))} />
            </div>
            <div className="form-group">
              <label className="form-label">Coin Type</label>
              <input className="form-input" value={createForm.coinType}
                onChange={e => setCreateForm(f => ({ ...f, coinType: e.target.value }))} />
              <div className="form-hint">Must be registered by admin. Default: AptosCoin</div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button
                className="btn btn-primary"
                disabled={loading || !createForm.payer || !isValidAddress(createForm.payer) || !createForm.amount || !createForm.dueDate}
                onClick={() => submit(
                  buildCreateInvoice(
                    createForm.payer, createForm.amount,
                    Math.floor(new Date(createForm.dueDate).getTime() / 1000),
                    createForm.memo || 'Invoice', createForm.coinType,
                  ),
                  `Create invoice for ${shortAddr(createForm.payer)}`
                )}
              >
                {loading ? <span className="spinner" /> : 'Create Invoice'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Pay */}
      {modal === 'pay' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Pay Invoice #{actionId}</div></div>
            {lookedUp?.amount !== undefined && (
              <div className="alert alert-warning" style={{ marginBottom: 16 }}>
                Amount due: <strong>{formatApt(lookedUp.amount)}</strong>
              </div>
            )}
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', marginBottom: 16 }}>
              Transfers the invoice amount (minus platform fee) from your wallet to the merchant.
            </p>
            <div className="form-group">
              <label className="form-label">Coin Type</label>
              <input className="form-input" value={payCoinType} onChange={e => setPayCoinType(e.target.value)} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading}
                onClick={() => submit(buildPayInvoice(Number(actionId), payCoinType), `Pay invoice #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Confirm Payment'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Cancel */}
      {modal === 'cancel' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Cancel Invoice #{actionId}</div></div>
            <div className="alert alert-warning" style={{ marginBottom: 16 }}>
              Only the merchant or admin can cancel. Invoice must be in Pending state.
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Back</button>
              <button className="btn btn-danger" disabled={loading}
                onClick={() => submit(buildCancelInvoice(Number(actionId)), `Cancel invoice #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Cancel Invoice'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Dispute */}
      {modal === 'dispute' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Flag Dispute — Invoice #{actionId}</div></div>
            <div className="form-group">
              <label className="form-label">Dispute Reason *</label>
              <textarea className="form-textarea" placeholder="Describe the dispute..."
                value={disputeReason} onChange={e => setDisputeReason(e.target.value)} />
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button className="btn btn-danger" disabled={loading || !disputeReason}
                onClick={() => submit(buildFlagDispute(Number(actionId), disputeReason), `Dispute invoice #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Submit Dispute'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Resolve */}
      {modal === 'resolve' && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div className="modal">
            <button className="modal-close" onClick={() => setModal(null)}>✕</button>
            <div className="modal-header"><div className="modal-title">Resolve Dispute — Invoice #{actionId}</div></div>
            <div className="alert alert-warning" style={{ marginBottom: 16 }}>Admin only. Irreversible on-chain action.</div>
            <div className="form-group">
              <label className="form-label">Decision</label>
              <select className="form-select" value={upheld ? 'true' : 'false'}
                onChange={e => setUpheld(e.target.value === 'true')}>
                <option value="true">Upheld — Payer wins (Invoice → Cancelled)</option>
                <option value="false">Denied — Merchant wins (Invoice → Paid)</option>
              </select>
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setModal(null)}>Cancel</button>
              <button className="btn btn-primary" disabled={loading}
                onClick={() => submit(buildResolveDispute(Number(actionId), upheld), `Resolve dispute #${actionId}`)}>
                {loading ? <span className="spinner" /> : 'Resolve'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
