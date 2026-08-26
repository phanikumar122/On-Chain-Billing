'use client';
import { useWallet } from '@aptos-labs/wallet-adapter-react';
import { useState, useRef, useEffect } from 'react';
import { shortAddr } from '@/lib/contract';

const WALLET_INSTALL_URL = 'https://petra.app/';

export default function WalletButton() {
  const { connect, disconnect, account, connected, wallets } = useWallet();
  const [dropOpen, setDropOpen] = useState(false);
  const [noWalletMsg, setNoWalletMsg] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handle(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setDropOpen(false);
        setNoWalletMsg(false);
      }
    }
    document.addEventListener('mousedown', handle);
    return () => document.removeEventListener('mousedown', handle);
  }, []);

  function handleConnect() {
    const wallet = wallets?.find(w => w.name === 'Petra') ?? wallets?.[0];
    if (wallet) {
      connect(wallet.name);
    } else {
      setNoWalletMsg(true);
    }
  }

  if (connected && account) {
    return (
      <div ref={ref} style={{ position: 'relative' }}>
        <button
          className="wallet-btn wallet-connected"
          onClick={() => setDropOpen(o => !o)}
        >
          <span className="wallet-dot" />
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: '0.8125rem' }}>
            {shortAddr(account.address.toString())}
          </span>
          <span style={{ marginLeft: 2, opacity: 0.6, fontSize: '0.7rem' }}>▾</span>
        </button>
        {dropOpen && (
          <div className="wallet-dropdown">
            <div className="wallet-dropdown-addr">
              <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginBottom: 4 }}>Connected</div>
              <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: '0.8rem', wordBreak: 'break-all' }}>
                {account.address.toString()}
              </div>
            </div>
            <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '8px 0' }} />
            <button
              className="wallet-dropdown-btn"
              onClick={() => { disconnect(); setDropOpen(false); }}
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    );
  }

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button className="wallet-btn" onClick={handleConnect}>
        Connect Wallet
      </button>
      {noWalletMsg && (
        <div className="wallet-dropdown" style={{ minWidth: 260 }}>
          <div style={{ fontSize: '0.875rem', fontWeight: 600, marginBottom: 8 }}>No Wallet Detected</div>
          <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.5, marginBottom: 12 }}>
            No Aptos wallet extension was found. Install Petra to get started.
          </p>
          <a
            href={WALLET_INSTALL_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-primary btn-sm"
            style={{ width: '100%', display: 'flex', justifyContent: 'center' }}
            onClick={() => setNoWalletMsg(false)}
          >
            Install Petra Wallet
          </a>
        </div>
      )}
    </div>
  );
}
