/// events.move
/// All #[event] structs and their emit helpers for the on_chain_billing package.
/// Every field carries enough context for off-chain indexers to reconstruct state
/// without reading raw table entries.
module billing::events {
    use std::string::String;
    use aptos_framework::event;

    // -----------------------------------------------------------------------
    // Invoice events
    // -----------------------------------------------------------------------

    #[event]
    /// Emitted when a new invoice is created.
    struct InvoiceCreated has drop, store {
        invoice_id: u64,
        merchant:   address,
        payer:      address,
        amount:     u64,
        token_name: String,
        due_date:   u64,
        timestamp:  u64,
    }

    #[event]
    /// Emitted when a payer successfully pays an invoice.
    struct InvoicePaid has drop, store {
        invoice_id: u64,
        merchant:   address,
        payer:      address,
        amount:     u64,
        token_name: String,
        timestamp:  u64,
    }

    #[event]
    /// Emitted when an invoice is cancelled by the merchant or admin.
    struct InvoiceCancelled has drop, store {
        invoice_id: u64,
        cancelled_by: address,
        timestamp:    u64,
    }

    #[event]
    /// Emitted when a payer raises a dispute on an invoice.
    struct InvoiceDisputed has drop, store {
        invoice_id: u64,
        payer:      address,
        reason:     String,
        timestamp:  u64,
    }

    #[event]
    /// Emitted when the admin resolves a dispute.
    struct DisputeResolved has drop, store {
        invoice_id:  u64,
        resolved_by: address,
        upheld:      bool,      // true → payer wins; false → merchant wins
        timestamp:   u64,
    }

    // -----------------------------------------------------------------------
    // Subscription events
    // -----------------------------------------------------------------------

    #[event]
    /// Emitted when a subscriber authorizes a new recurring billing agreement.
    struct Subscribed has drop, store {
        sub_id:           u64,
        subscriber:       address,
        merchant:         address,
        amount_per_cycle: u64,
        interval_seconds: u64,
        max_cycles:       u64,
        token_name:       String,
        timestamp:        u64,
    }

    #[event]
    /// Emitted each time a subscription cycle is successfully charged.
    struct Charged has drop, store {
        sub_id:      u64,
        subscriber:  address,
        merchant:    address,
        amount:      u64,
        cycles_used: u64,
        token_name:  String,
        timestamp:   u64,
    }

    #[event]
    /// Emitted when a subscription is cancelled.
    struct SubscriptionCancelled has drop, store {
        sub_id:       u64,
        cancelled_by: address,
        timestamp:    u64,
    }

    // -----------------------------------------------------------------------
    // Access-control events
    // -----------------------------------------------------------------------

    #[event]
    /// Emitted when admin rights are granted to a new address.
    struct AdminGranted has drop, store {
        granted_to: address,
        by:         address,
        timestamp:  u64,
    }

    #[event]
    /// Emitted when admin rights are revoked from an address.
    struct AdminRevoked has drop, store {
        revoked_from: address,
        by:           address,
        timestamp:    u64,
    }

    #[event]
    /// Emitted when the system is paused.
    struct SystemPaused has drop, store {
        by:        address,
        timestamp: u64,
    }

    #[event]
    /// Emitted when the system is unpaused.
    struct SystemUnpaused has drop, store {
        by:        address,
        timestamp: u64,
    }

    // -----------------------------------------------------------------------
    // Payment-verification receipt
    // -----------------------------------------------------------------------

    #[event]
    /// Emitted for every successful payment or subscription charge.
    /// Provides a self-contained payment verification receipt.
    struct ReceiptIssued has drop, store {
        receipt_type: u8,       // 0 = invoice, 1 = subscription
        source_id:    u64,      // invoice_id or sub_id
        payer:        address,
        merchant:     address,
        gross_amount: u64,
        fee_amount:   u64,
        net_amount:   u64,
        token_name:   String,
        timestamp:    u64,
    }

    // -----------------------------------------------------------------------
    // Emit helpers
    // -----------------------------------------------------------------------

    public fun emit_invoice_created(
        invoice_id: u64, merchant: address, payer: address,
        amount: u64, token_name: String, due_date: u64, timestamp: u64,
    ) {
        event::emit(InvoiceCreated { invoice_id, merchant, payer, amount, token_name, due_date, timestamp });
    }

    public fun emit_invoice_paid(
        invoice_id: u64, merchant: address, payer: address,
        amount: u64, token_name: String, timestamp: u64,
    ) {
        event::emit(InvoicePaid { invoice_id, merchant, payer, amount, token_name, timestamp });
    }

    public fun emit_invoice_cancelled(invoice_id: u64, cancelled_by: address, timestamp: u64) {
        event::emit(InvoiceCancelled { invoice_id, cancelled_by, timestamp });
    }

    public fun emit_invoice_disputed(invoice_id: u64, payer: address, reason: String, timestamp: u64) {
        event::emit(InvoiceDisputed { invoice_id, payer, reason, timestamp });
    }

    public fun emit_dispute_resolved(invoice_id: u64, resolved_by: address, upheld: bool, timestamp: u64) {
        event::emit(DisputeResolved { invoice_id, resolved_by, upheld, timestamp });
    }

    public fun emit_subscribed(
        sub_id: u64, subscriber: address, merchant: address,
        amount_per_cycle: u64, interval_seconds: u64, max_cycles: u64,
        token_name: String, timestamp: u64,
    ) {
        event::emit(Subscribed { sub_id, subscriber, merchant, amount_per_cycle, interval_seconds, max_cycles, token_name, timestamp });
    }

    public fun emit_charged(
        sub_id: u64, subscriber: address, merchant: address,
        amount: u64, cycles_used: u64, token_name: String, timestamp: u64,
    ) {
        event::emit(Charged { sub_id, subscriber, merchant, amount, cycles_used, token_name, timestamp });
    }

    public fun emit_subscription_cancelled(sub_id: u64, cancelled_by: address, timestamp: u64) {
        event::emit(SubscriptionCancelled { sub_id, cancelled_by, timestamp });
    }

    public fun emit_admin_granted(granted_to: address, by: address, timestamp: u64) {
        event::emit(AdminGranted { granted_to, by, timestamp });
    }

    public fun emit_admin_revoked(revoked_from: address, by: address, timestamp: u64) {
        event::emit(AdminRevoked { revoked_from, by, timestamp });
    }

    public fun emit_system_paused(by: address, timestamp: u64) {
        event::emit(SystemPaused { by, timestamp });
    }

    public fun emit_system_unpaused(by: address, timestamp: u64) {
        event::emit(SystemUnpaused { by, timestamp });
    }

    public fun emit_receipt(
        receipt_type: u8, source_id: u64,
        payer: address, merchant: address,
        gross_amount: u64, fee_amount: u64, net_amount: u64,
        token_name: String, timestamp: u64,
    ) {
        event::emit(ReceiptIssued {
            receipt_type, source_id, payer, merchant,
            gross_amount, fee_amount, net_amount, token_name, timestamp,
        });
    }
}
