# on_chain_billing

A production-grade, decentralized billing and payment system built as an Aptos Move 2024 package. It enables businesses and individuals to create, manage, and process financial transactions directly on the Aptos blockchain — with no intermediaries, no trusted custodians, and no off-chain oracles required.

---

## Features

| Feature | Description |
|---|---|
| **On-chain Invoices** | Create invoices between merchants and payers; payments are tracked immutably. |
| **Payment Verification / Receipts** | Every successful payment emits a `ReceiptIssued` event with full details. |
| **Dispute Resolution** | Payers can flag disputes; the admin resolves them with a verifiable on-chain decision. |
| **Automated Recurring Billing** | Pull-model subscriptions: no locked funds, no trusted scheduler needed. |
| **Multi-token Support** | All billing entry points are generic over `<CoinType>`; an admin-gated registry controls which tokens are accepted. |
| **Role-based Access Control** | Capability-based `AdminCap` gates all privileged operations. |
| **Pause / Unpause** | Admin can halt all billing operations in an emergency. |
| **Configurable Platform Fee** | Basis-point fee (default 0) skimmed from each payment to the billing treasury address. |
| **Gas Optimization** | `Table<u64, T>` for O(1) lookups; no large struct copies; references preferred over moves. |

---

## Architecture

```
on_chain_billing/
├── Move.toml
├── README.md
├── sources/
│   ├── errors.move          # Abort-code constants (1xx invoice, 2xx sub, 3xx access)
│   ├── events.move          # #[event] structs + emit helpers
│   ├── access_control.move  # Config resource, counters, token registry, pause
│   ├── billing_admin.move   # entry fun façade for admin operations
│   ├── treasury.move        # Generic coin transfer + fee computation
│   ├── invoice.move         # Invoice lifecycle (Pending→Paid/Cancelled/Disputed)
│   └── subscription.move    # Recurring billing (authorize/charge/cancel)
└── tests/
    ├── access_control_tests.move
    ├── invoice_tests.move
    └── subscription_tests.move
```

### Subscription Model — Pull + Pre-authorization

The subscription module implements a **pull model** with **on-chain pre-authorization**:

1. The subscriber signs an `authorize` transaction that records a `Subscription` on-chain — effectively an allowance: *"I agree to pay `amount_per_cycle` of `CoinType` every `interval_seconds`, for at most `max_cycles` cycles."*
2. Any party (merchant, keeper bot, or the subscriber themselves) may call `charge` at any time.
3. **The smart contract enforces all rules**: the subscription must be active, the interval must have elapsed, and the cycle cap must not be exceeded. No trusted off-chain scheduler is required — the blockchain is the enforcer.
4. When `max_cycles` is reached the subscription auto-deactivates.

---

## Prerequisites

- **Aptos CLI** ≥ 2.x:
  ```bash
  curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3
  ```
- **Devnet account**: run `aptos init --profile devnet` and fund via the Aptos faucet.

---

## Build

```bash
aptos move compile --named-addresses billing=<your_address>
```

---

## Test

```bash
aptos move test --named-addresses billing=<your_address>
```

Expected output: `Test result: OK. Total tests: 26; passed: 26; failed: 0`

---

## Publish

```bash
aptos move publish \
  --named-addresses billing=<your_address> \
  --profile devnet
```

---

## CLI Usage Examples

### Admin: Register a token

```bash
aptos move run \
  --function-id '<addr>::billing_admin::register_token' \
  --type-args '0x1::aptos_coin::AptosCoin' \
  --profile devnet
```

### Admin: Set platform fee (e.g. 0.5% = 50 bps)

```bash
aptos move run \
  --function-id '<addr>::billing_admin::set_platform_fee_bps' \
  --args u64:50 \
  --profile devnet
```

### Merchant: Create an invoice

```bash
aptos move run \
  --function-id '<addr>::invoice::create_invoice' \
  --type-args '0x1::aptos_coin::AptosCoin' \
  --args \
    address:<payer_address> \
    u64:1000000 \
    u64:1735689600 \
    'string:Monthly retainer' \
  --profile devnet
```

### Payer: Pay an invoice

```bash
aptos move run \
  --function-id '<addr>::invoice::pay_invoice' \
  --type-args '0x1::aptos_coin::AptosCoin' \
  --args u64:0 \
  --profile devnet
```

### Subscriber: Authorize a subscription

```bash
aptos move run \
  --function-id '<addr>::subscription::authorize' \
  --type-args '0x1::aptos_coin::AptosCoin' \
  --args \
    address:<merchant_address> \
    u64:500000 \
    u64:2592000 \
    u64:12 \
  --profile devnet
```

> Parameters: merchant, amount_per_cycle (μAPT), interval_seconds (2592000 = 30 days), max_cycles

### Anyone: Charge a subscription cycle

```bash
aptos move run \
  --function-id '<addr>::subscription::charge' \
  --type-args '0x1::aptos_coin::AptosCoin' \
  --args u64:0 \
  --profile devnet
```

### Admin: Pause / Unpause

```bash
aptos move run --function-id '<addr>::billing_admin::pause' --profile devnet
aptos move run --function-id '<addr>::billing_admin::unpause' --profile devnet
```

---

## Module Reference

| Module | Key Entry Functions |
|---|---|
| `billing_admin` | `grant_admin`, `revoke_admin`, `pause`, `unpause`, `register_token`, `set_platform_fee_bps` |
| `invoice` | `create_invoice<C>`, `pay_invoice<C>`, `cancel_invoice`, `flag_dispute`, `resolve_dispute` |
| `subscription` | `authorize<C>`, `charge<C>`, `cancel_subscription` |

### View Functions

| Module | View | Returns |
|---|---|---|
| `invoice` | `get_invoice_status(id)` | `u8` (0=Pending,1=Paid,2=Cancelled,3=Disputed) |
| `invoice` | `get_invoice_merchant(id)` | `address` |
| `invoice` | `get_invoice_payer(id)` | `address` |
| `invoice` | `get_invoice_amount(id)` | `u64` |
| `subscription` | `get_subscription_active(id)` | `bool` |
| `subscription` | `get_subscription_cycles_used(id)` | `u64` |
| `subscription` | `is_due(id)` | `bool` |
| `subscription` | `next_charge_time(id)` | `u64` (unix timestamp) |

---

## Error Codes

| Range | Domain |
|---|---|
| `1xx` | Invoice (not found, already paid, cancelled, disputed, invalid amount…) |
| `2xx` | Subscription (not found, too early, max cycles, cancelled, insufficient balance…) |
| `3xx` | Access / System (not authorized, not admin, paused, already initialized…) |

All abort codes are wrapped with `std::error` constructors for canonical Move error categories.

---

## License

MIT
