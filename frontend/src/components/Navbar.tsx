'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';
import WalletButton from './WalletButton';

const NETWORK = process.env.NEXT_PUBLIC_APTOS_NETWORK ?? 'devnet';

const NAV_LINKS = [
  { href: '/',              label: 'Dashboard' },
  { href: '/invoices',      label: 'Invoices' },
  { href: '/subscriptions', label: 'Subscriptions' },
  { href: '/admin',         label: 'Admin' },
];

export default function Navbar() {
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <nav className="navbar">
      <div className="navbar-container">
        <Link href="/" className="navbar-brand" onClick={() => setMenuOpen(false)}>
          <div className="logo-icon">CB</div>
          ChainBill
        </Link>

        <div className="navbar-nav">
          {NAV_LINKS.map(({ href, label }) => {
            const isActive = href === '/' ? pathname === '/' : pathname.startsWith(href);
            return (
              <Link key={href} href={href} className={`nav-link${isActive ? ' active' : ''}`}>
                {label}
              </Link>
            );
          })}
        </div>

        <div className="navbar-right">
          <span className="network-badge">{NETWORK}</span>
          <WalletButton />
        </div>
      </div>
    </nav>
  );
}
