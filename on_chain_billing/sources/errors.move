/// errors.move
/// Central abort-code constants for the on_chain_billing package.
/// Ranges:
///   1xx — Invoice domain
///   2xx — Subscription domain
///   3xx — Access / system domain
///
/// Every abort path in the package MUST use a named constant from this module.
/// Where semantically correct the constants are wrapped with the appropriate
/// std::error constructor so callers get canonical Move error categories.
module billing::errors {
    use std::error;

    // -----------------------------------------------------------------------
    // 1xx — Invoice
    // -----------------------------------------------------------------------

    /// The requested invoice does not exist.
    const E_INVOICE_NOT_FOUND_RAW: u64 = 100;
    /// The invoice has already been paid and cannot be modified.
    const E_INVOICE_ALREADY_PAID_RAW: u64 = 101;
    /// The invoice has been cancelled and cannot be acted upon.
    const E_INVOICE_CANCELLED_RAW: u64 = 102;
    /// The invoice is currently under dispute.
    const E_INVOICE_DISPUTED_RAW: u64 = 103;
    /// The amount supplied is zero or otherwise invalid.
    const E_INVALID_AMOUNT_RAW: u64 = 104;
    /// This operation is only permitted on overdue invoices.
    const E_INVOICE_OVERDUE_ONLY_RAW: u64 = 105;
    /// The caller is not the designated payer of this invoice.
    const E_NOT_INVOICE_PAYER_RAW: u64 = 106;
    /// The caller is not the merchant who created this invoice.
    const E_NOT_INVOICE_MERCHANT_RAW: u64 = 107;

    // -----------------------------------------------------------------------
    // 2xx — Subscription
    // -----------------------------------------------------------------------

    /// The requested subscription does not exist.
    const E_SUB_NOT_FOUND_RAW: u64 = 200;
    /// A cycle charge was attempted before the interval has elapsed.
    const E_CHARGE_TOO_EARLY_RAW: u64 = 201;
    /// The charge amount exceeds the authorized per-cycle cap.
    const E_AMOUNT_EXCEEDS_CAP_RAW: u64 = 202;
    /// The subscription has exhausted its maximum allowed cycles.
    const E_MAX_CYCLES_REACHED_RAW: u64 = 203;
    /// The subscription has been cancelled.
    const E_SUB_CANCELLED_RAW: u64 = 204;
    /// The subscriber does not hold enough coins to cover the charge.
    const E_INSUFFICIENT_BALANCE_RAW: u64 = 205;

    // -----------------------------------------------------------------------
    // 3xx — Access / system
    // -----------------------------------------------------------------------

    /// The caller does not have the required capability.
    const E_NOT_AUTHORIZED_RAW: u64 = 300;
    /// The caller is not the admin.
    const E_NOT_ADMIN_RAW: u64 = 301;
    /// Billing operations are suspended while the system is paused.
    const E_PAUSED_RAW: u64 = 302;
    /// Initialization was attempted more than once.
    const E_ALREADY_INITIALIZED_RAW: u64 = 303;
    /// Required initialization has not been performed yet.
    const E_NOT_INITIALIZED_RAW: u64 = 304;
    /// The requested state transition is not permitted.
    const E_INVALID_STATE_TRANSITION_RAW: u64 = 305;
    /// The CoinType is not in the supported-token registry.
    const E_TOKEN_NOT_SUPPORTED_RAW: u64 = 306;

    // -----------------------------------------------------------------------
    // Public accessor functions (wrapped with std::error where appropriate)
    // -----------------------------------------------------------------------

    public fun invoice_not_found(): u64      { error::not_found(E_INVOICE_NOT_FOUND_RAW) }
    public fun invoice_already_paid(): u64   { error::invalid_state(E_INVOICE_ALREADY_PAID_RAW) }
    public fun invoice_cancelled(): u64      { error::invalid_state(E_INVOICE_CANCELLED_RAW) }
    public fun invoice_disputed(): u64       { error::invalid_state(E_INVOICE_DISPUTED_RAW) }
    public fun invalid_amount(): u64         { error::invalid_argument(E_INVALID_AMOUNT_RAW) }
    public fun invoice_overdue_only(): u64   { error::invalid_state(E_INVOICE_OVERDUE_ONLY_RAW) }
    public fun not_invoice_payer(): u64      { error::permission_denied(E_NOT_INVOICE_PAYER_RAW) }
    public fun not_invoice_merchant(): u64   { error::permission_denied(E_NOT_INVOICE_MERCHANT_RAW) }

    public fun sub_not_found(): u64          { error::not_found(E_SUB_NOT_FOUND_RAW) }
    public fun charge_too_early(): u64       { error::invalid_state(E_CHARGE_TOO_EARLY_RAW) }
    public fun amount_exceeds_cap(): u64     { error::invalid_argument(E_AMOUNT_EXCEEDS_CAP_RAW) }
    public fun max_cycles_reached(): u64     { error::invalid_state(E_MAX_CYCLES_REACHED_RAW) }
    public fun sub_cancelled(): u64          { error::invalid_state(E_SUB_CANCELLED_RAW) }
    public fun insufficient_balance(): u64   { error::invalid_state(E_INSUFFICIENT_BALANCE_RAW) }

    public fun not_authorized(): u64         { error::permission_denied(E_NOT_AUTHORIZED_RAW) }
    public fun not_admin(): u64              { error::permission_denied(E_NOT_ADMIN_RAW) }
    public fun paused(): u64                 { error::invalid_state(E_PAUSED_RAW) }
    public fun already_initialized(): u64    { error::already_exists(E_ALREADY_INITIALIZED_RAW) }
    public fun not_initialized(): u64        { error::not_found(E_NOT_INITIALIZED_RAW) }
    public fun invalid_state_transition(): u64 { error::invalid_state(E_INVALID_STATE_TRANSITION_RAW) }
    public fun token_not_supported(): u64    { error::invalid_argument(E_TOKEN_NOT_SUPPORTED_RAW) }
}
