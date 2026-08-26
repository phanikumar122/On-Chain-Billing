/// invoice.move
/// On-chain invoice lifecycle: creation, payment, cancellation, and dispute
/// resolution for the on_chain_billing package.
///
/// Storage layout:
///   A single `InvoiceStore` resource lives at the `billing` address and holds
///   a `Table<u64, Invoice>` keyed by global invoice id. O(1) lookup, no
///   iteration needed.
///
/// Status machine:
///   Pending → Paid          (via pay_invoice)
///   Pending → Cancelled     (via cancel_invoice)
///   Pending → Disputed      (via flag_dispute)
///   Disputed → Paid         (resolve_dispute, upheld = false → merchant wins)
///   Disputed → Cancelled    (resolve_dispute, upheld = true  → payer wins)
module billing::invoice {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use aptos_framework::timestamp;
    use aptos_framework::table::{Self, Table};
    use billing::access_control;
    use billing::errors;
    use billing::events;
    use billing::treasury;

    // -----------------------------------------------------------------------
    // Status constants
    // -----------------------------------------------------------------------

    const STATUS_PENDING:   u8 = 0;
    const STATUS_PAID:      u8 = 1;
    const STATUS_CANCELLED: u8 = 2;
    const STATUS_DISPUTED:  u8 = 3;

    // Receipt type tag for ReceiptIssued
    const RECEIPT_INVOICE: u8 = 0;

    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    struct Invoice has store, drop {
        id:             u64,
        merchant:       address,
        payer:          address,
        amount:         u64,
        token_name:     String,
        memo:           String,
        created_at:     u64,
        due_date:       u64,
        paid_at:        Option<u64>,
        status:         u8,
        dispute_reason: Option<String>,
    }

    struct InvoiceStore has key {
        invoices: Table<u64, Invoice>,
    }

    // -----------------------------------------------------------------------
    // Store initializer (called once per package publish via init_module)
    // -----------------------------------------------------------------------

    fun init_module(billing_signer: &signer) {
        move_to(billing_signer, InvoiceStore {
            invoices: table::new(),
        });
    }

    // -----------------------------------------------------------------------
    // Public entry: create_invoice
    // -----------------------------------------------------------------------

    /// Create a new invoice from `merchant` to `payer` for `amount` of
    /// `CoinType`. Returns the assigned invoice id.
    /// Asserts: system not paused, amount > 0, token supported.
    public entry fun create_invoice<CoinType>(
        merchant:  &signer,
        payer:     address,
        amount:    u64,
        due_date:  u64,
        memo:      String,
    ) acquires InvoiceStore {
        access_control::assert_not_paused();
        assert!(amount > 0, errors::invalid_amount());
        access_control::assert_token_supported<CoinType>();

        let merchant_addr = signer::address_of(merchant);
        let id = access_control::next_invoice_id();
        let now = timestamp::now_seconds();
        let token_name = treasury::coin_type_name<CoinType>();

        let invoice = Invoice {
            id,
            merchant: merchant_addr,
            payer,
            amount,
            token_name,
            memo,
            created_at: now,
            due_date,
            paid_at: option::none(),
            status: STATUS_PENDING,
            dispute_reason: option::none(),
        };

        let store = borrow_global_mut<InvoiceStore>(@billing);
        table::add(&mut store.invoices, id, invoice);

        events::emit_invoice_created(id, merchant_addr, payer, amount, treasury::coin_type_name<CoinType>(), due_date, now);
    }

    // -----------------------------------------------------------------------
    // Public entry: pay_invoice
    // -----------------------------------------------------------------------

    /// Pay invoice `id`. Transfers amount (minus platform fee) to merchant.
    /// Asserts: invoice exists, status is Pending, caller is payer.
    public entry fun pay_invoice<CoinType>(
        payer: &signer,
        id:    u64,
    ) acquires InvoiceStore {
        access_control::assert_not_paused();

        let payer_addr = signer::address_of(payer);
        let store = borrow_global_mut<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());

        let inv = table::borrow_mut(&mut store.invoices, id);
        assert!(inv.status == STATUS_PENDING,
            if (inv.status == STATUS_PAID)      { errors::invoice_already_paid() }
            else if (inv.status == STATUS_CANCELLED) { errors::invoice_cancelled() }
            else { errors::invoice_disputed() }
        );
        assert!(payer_addr == inv.payer, errors::not_invoice_payer());

        let amount    = inv.amount;
        let merchant  = inv.merchant;
        let token_name = inv.token_name;
        let now = timestamp::now_seconds();

        // Update state before coin transfer (checks-effects-interactions)
        inv.status  = STATUS_PAID;
        inv.paid_at = option::some(now);

        // Transfer via treasury (handles fee split)
        let (net, fee) = treasury::transfer_with_fee<CoinType>(payer, merchant, amount);

        events::emit_invoice_paid(id, merchant, payer_addr, amount, token_name, now);
        events::emit_receipt(
            RECEIPT_INVOICE, id, payer_addr, merchant,
            amount, fee, net, token_name, now,
        );
    }

    // -----------------------------------------------------------------------
    // Public entry: cancel_invoice
    // -----------------------------------------------------------------------

    /// Cancel invoice `id`. Only the merchant or admin may cancel a pending invoice.
    public entry fun cancel_invoice(caller: &signer, id: u64) acquires InvoiceStore {
        let caller_addr = signer::address_of(caller);
        let store = borrow_global_mut<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());

        let inv = table::borrow_mut(&mut store.invoices, id);
        assert!(inv.status == STATUS_PENDING,
            if (inv.status == STATUS_PAID)      { errors::invoice_already_paid() }
            else if (inv.status == STATUS_CANCELLED) { errors::invoice_cancelled() }
            else { errors::invoice_disputed() }
        );

        let is_merchant = caller_addr == inv.merchant;
        let is_admin    = caller_addr == access_control::get_admin();
        assert!(is_merchant || is_admin, errors::not_invoice_merchant());

        inv.status = STATUS_CANCELLED;
        events::emit_invoice_cancelled(id, caller_addr, timestamp::now_seconds());
    }

    // -----------------------------------------------------------------------
    // Public entry: flag_dispute
    // -----------------------------------------------------------------------

    /// Raise a dispute on a Pending invoice. Only the designated payer may do this.
    public entry fun flag_dispute(
        payer: &signer,
        id:    u64,
        reason: String,
    ) acquires InvoiceStore {
        access_control::assert_not_paused();
        let payer_addr = signer::address_of(payer);
        let store = borrow_global_mut<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());

        let inv = table::borrow_mut(&mut store.invoices, id);
        assert!(inv.status == STATUS_PENDING,
            if (inv.status == STATUS_PAID)      { errors::invoice_already_paid() }
            else if (inv.status == STATUS_CANCELLED) { errors::invoice_cancelled() }
            else { errors::invoice_disputed() }
        );
        assert!(payer_addr == inv.payer, errors::not_invoice_payer());

        inv.status = STATUS_DISPUTED;
        inv.dispute_reason = option::some(reason);

        events::emit_invoice_disputed(id, payer_addr, reason, timestamp::now_seconds());
    }

    // -----------------------------------------------------------------------
    // Public entry: resolve_dispute
    // -----------------------------------------------------------------------

    /// Resolve a disputed invoice. Admin only.
    /// `upheld = true` → payer wins → invoice marked Cancelled (no charge).
    /// `upheld = false` → merchant wins → invoice marked Paid (admin pays from
    ///                                      payer on their behalf, or just marks).
    /// For simplicity the resolution only changes state; actual fund movement
    /// for arbitrated payments is handled off-chain or via a separate release fn.
    public entry fun resolve_dispute(
        admin:  &signer,
        id:     u64,
        upheld: bool,
    ) acquires InvoiceStore {
        access_control::assert_admin(admin);
        let admin_addr = signer::address_of(admin);

        let store = borrow_global_mut<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());

        let inv = table::borrow_mut(&mut store.invoices, id);
        assert!(inv.status == STATUS_DISPUTED, errors::invalid_state_transition());

        if (upheld) {
            // Payer wins → cancel invoice
            inv.status = STATUS_CANCELLED;
        } else {
            // Merchant wins → mark paid (actual transfer done externally)
            inv.status = STATUS_PAID;
            inv.paid_at = option::some(timestamp::now_seconds());
        };

        events::emit_dispute_resolved(id, admin_addr, upheld, timestamp::now_seconds());
    }

    // -----------------------------------------------------------------------
    // #[view] read-only functions
    // -----------------------------------------------------------------------

    #[view]
    public fun get_invoice_status(id: u64): u8 acquires InvoiceStore {
        let store = borrow_global<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());
        table::borrow(&store.invoices, id).status
    }

    #[view]
    public fun get_invoice_merchant(id: u64): address acquires InvoiceStore {
        let store = borrow_global<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());
        table::borrow(&store.invoices, id).merchant
    }

    #[view]
    public fun get_invoice_payer(id: u64): address acquires InvoiceStore {
        let store = borrow_global<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());
        table::borrow(&store.invoices, id).payer
    }

    #[view]
    public fun get_invoice_amount(id: u64): u64 acquires InvoiceStore {
        let store = borrow_global<InvoiceStore>(@billing);
        assert!(table::contains(&store.invoices, id), errors::invoice_not_found());
        table::borrow(&store.invoices, id).amount
    }

    // -----------------------------------------------------------------------
    // Internal helpers (test-only)
    // -----------------------------------------------------------------------

    #[test_only]
    public fun init_for_test(billing_signer: &signer) {
        if (!exists<InvoiceStore>(std::signer::address_of(billing_signer))) {
            move_to(billing_signer, InvoiceStore { invoices: table::new() });
        };
    }

    #[test_only]
    public fun status_pending(): u8   { STATUS_PENDING }
    #[test_only]
    public fun status_paid(): u8      { STATUS_PAID }
    #[test_only]
    public fun status_cancelled(): u8 { STATUS_CANCELLED }
    #[test_only]
    public fun status_disputed(): u8  { STATUS_DISPUTED }
}
