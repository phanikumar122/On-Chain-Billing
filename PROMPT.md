# TASK
Build a production-grade on-chain billing and payment system as an Aptos Move
package called `on_chain_billing`. Target Aptos devnet, Move 2 (Move 2024 edition),
using the aptos-framework. Write clean, gas-conscious, well-documented Move.
Explain each module briefly as you build it, and ensure `aptos move test` passes
with all tests green before you finish.

# PROJECT CONTEXT
A decentralized billing and payment system for transparent, automated, trustless
financial transactions on-chain. It lets businesses and individuals create, manage,
and process billing directly on the blockchain: automated recurring payments,
multi-token support, subscription cycles, on-chain invoices, payment verification
with receipts, dispute resolution, and role-based access control.

# PACKAGE LAYOUT
on_chain_billing/
  Move.toml
  README.md
  sources/
    errors.move
    events.move
    access_control.move
    invoice.move
    subscription.move
    treasury.move
    billing_admin.move
  tests/
    invoice_tests.move
    subscription_tests.move
    access_control_tests.move

# MOVE.TOML
- Package name on_chain_billing, version 1.0.0.
- Named address `billing = "_"` (resolved at publish/test time).
- Dependency: AptosFramework via git
  (https://github.com/aptos-labs/aptos-core.git, subdir aptos-move/framework/
  aptos-framework, rev mainnet).
- Set Move 2 / 2024 edition in package config.

# MODULE: errors.move
Central abort-code constants (u64), grouped and commented:
- E_NOT_AUTHORIZED, E_NOT_ADMIN, E_PAUSED
- E_INVOICE_NOT_FOUND, E_INVOICE_ALREADY_PAID, E_INVOICE_CANCELLED,
  E_INVOICE_DISPUTED, E_INVALID_AMOUNT, E_INVOICE_OVERDUE_ONLY,
  E_NOT_INVOICE_PAYER, E_NOT_INVOICE_MERCHANT
- E_SUB_NOT_FOUND, E_CHARGE_TOO_EARLY, E_AMOUNT_EXCEEDS_CAP,
  E_MAX_CYCLES_REACHED, E_SUB_CANCELLED, E_INSUFFICIENT_BALANCE
- E_ALREADY_INITIALIZED, E_NOT_INITIALIZED, E_INVALID_STATE_TRANSITION
Use distinct numeric ranges per domain (e.g. 1xx invoice, 2xx subscription,
3xx access). Prefer error::permission_denied / invalid_argument / not_found
wrappers from std::error where appropriate.

# MODULE: events.move
Define #[event] structs (all with relevant ids, addresses, amounts, timestamps):
InvoiceCreated, InvoicePaid, InvoiceCancelled, InvoiceDisputed, DisputeResolved,
Subscribed, Charged, SubscriptionCancelled, AdminGranted, AdminRevoked,
SystemPaused, SystemUnpaused, ReceiptIssued. Provide small emit helper functions.

# MODULE: access_control.move + billing_admin.move
- Capability-based roles. AdminCap resource gates privileged actions.
- init_module (or an explicit initialize(admin)) sets up a Config resource under
  the `billing` address holding: admin address, paused flag, global invoice/sub
  counters, and supported-token registry.
- grant_admin / revoke_admin (only current admin), assert_admin, assert_not_paused.
- pause() / unpause() emit SystemPaused/SystemUnpaused.
- Role-gated: dispute resolution, pausing, token registry management.

# MODULE: treasury.move
- Generic multi-token support: all coin movement generic over <CoinType>.
- Use aptos_framework::coin for transfers; helper deposit/withdraw/transfer fns.
- Optional escrow store per invoice/subscription if needed for verification.
- Register supported tokens; reject unsupported CoinType at billing time.
- Fee/commission hook (configurable basis-point platform fee, default 0) so a
  merchant fee can be skimmed on payment — emit it in the receipt.

# MODULE: invoice.move  (Invoice Generation + Payment Verification)
- Enum-like Status: Pending / Paid / Cancelled / Disputed (u8 constants + helpers).
- Invoice resource/struct fields: id (u64), merchant (address), payer (address),
  amount (u64), token type info (store type name / TypeInfo), memo/description
  (String), created_at, due_date, paid_at (Option), status, dispute_reason
  (Option<String>). Store invoices in a table under `billing` (or under merchant),
  keyed by global id.
- Functions:
  * create_invoice<CoinType>(merchant, payer, amount, due_date, memo): asserts
    not paused, amount > 0, token supported; assigns id from counter; emits
    InvoiceCreated. Returns id.
  * pay_invoice<CoinType>(payer, id): asserts exists, status Pending, caller is
    payer, not overdue-locked; transfers amount (minus platform fee) to merchant
    via treasury; sets Paid + paid_at; emits InvoicePaid + ReceiptIssued
    (payment verification / receipt).
  * cancel_invoice(caller, id): merchant or admin, only if Pending; emits
    InvoiceCancelled.
  * flag_dispute(payer, id, reason) and resolve_dispute(admin, id, uphold):
    dispute resolution flow with valid state transitions; emits
    InvoiceDisputed / DisputeResolved.
  * #[view] get_invoice(id), list helpers, and status query views.

# MODULE: subscription.move  (Automated / Recurring Billing)
- Pull + pre-authorization model (trust-minimized, no locked funds, no trusted
  scheduler needed):
  * authorize<CoinType>(subscriber, merchant, amount_per_cycle, interval_seconds,
    max_cycles): stores a Subscription resource acting as an on-chain allowance;
    fields: id, subscriber, merchant, amount_per_cycle, interval_seconds,
    max_cycles, cycles_used, last_charged_at, active (bool), token type. Emits
    Subscribed.
  * charge<CoinType>(caller, sub_id): CALLABLE BY ANYONE (merchant or keeper bot).
    The CONTRACT enforces: subscription active, >= interval_seconds since
    last_charged_at (use timestamp::now_seconds()), amount_per_cycle <= cap,
    cycles_used < max_cycles. Transfers amount_per_cycle from subscriber to
    merchant (minus platform fee), increments cycles_used, sets last_charged_at,
    auto-deactivates when max_cycles reached. Emits Charged + ReceiptIssued.
  * cancel_subscription(subscriber_or_admin, sub_id): sets active=false; emits
    SubscriptionCancelled.
  * #[view] get_subscription(sub_id), is_due(sub_id), next_charge_time(sub_id).

# CROSS-CUTTING REQUIREMENTS
- Multi-token: every billing entry point generic over <CoinType>; validate against
  the supported-token registry.
- Access control on all privileged/admin ops; assert_not_paused on billing ops.
- Payment verification: emit a ReceiptIssued event with payer, merchant, amount,
  fee, token, timestamp, and source id for every successful payment/charge.
- Gas optimization: use tables (not vectors) for O(1) lookups, avoid copying large
  structs, use inline helpers where sensible, minimize storage writes, prefer
  references over moves.
- Use Option<T>, String, TypeInfo/type_name as appropriate. No unused imports.
- Every abort path uses a named constant from errors.move.

# TESTS (must all pass under `aptos move test`)
Use #[test] / #[test_only]; set up framework timestamp via
aptos_framework::timestamp, mint a fake CoinType with a test-only coin, and fund
accounts. Cover at minimum:
- create + pay invoice succeeds; merchant balance increases by amount minus fee;
  status becomes Paid; ReceiptIssued emitted.
- double-pay rejection (#[expected_failure] E_INVOICE_ALREADY_PAID).
- cancel invoice then pay fails (E_INVOICE_CANCELLED).
- dispute flow: flag_dispute then resolve_dispute transitions state correctly;
  invalid transitions abort.
- subscription authorize + first charge succeeds.
- charging too early aborts (E_CHARGE_TOO_EARLY) — advance timestamp to prove the
  happy path across a cycle.
- charging past max_cycles aborts (E_MAX_CYCLES_REACHED) and sub auto-deactivates.
- amount > cap and unsupported-token paths abort.
- non-admin calling admin ops aborts (E_NOT_AUTHORIZED / E_NOT_ADMIN); billing
  while paused aborts (E_PAUSED).

# README.md
- Overview and feature list (automated billing, multi-token, subscriptions,
  invoicing, payment verification/receipts, dispute resolution, access control,
  gas optimization).
- Prerequisites: Aptos CLI install, `aptos init` for a devnet profile.
- Build: `aptos move compile --named-addresses billing=<addr>`
- Test:  `aptos move test`
- Publish: `aptos move publish --named-addresses billing=<addr> --profile devnet`
- Module + entry-function reference with example CLI `aptos move run` calls for
  create_invoice, pay_invoice, authorize, charge, and admin ops.
- Architecture notes explaining the pull + pre-authorization subscription model
  and why it needs no trusted scheduler.

# DELIVERY
Produce all files with complete, compiling code. After writing, run the tests
mentally/actually and fix anything until `aptos move test` is fully green. Then
give a short summary of the module structure and how the pieces fit together.