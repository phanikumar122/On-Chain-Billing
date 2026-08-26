/// subscription.move
/// Automated recurring billing via a pull + pre-authorization model.
///
/// How it works:
///   1. A subscriber calls `authorize` to create a Subscription record on-chain.
///      This acts as a signed allowance: "I agree to pay `amount_per_cycle` of
///      `CoinType` every `interval_seconds` for up to `max_cycles` cycles."
///   2. Anyone (merchant, keeper bot, or the subscriber themselves) calls `charge`
///      to pull the next payment. The CONTRACT enforces all timing and cap rules —
///      no trusted scheduler is required.
///   3. Once `max_cycles` is reached the subscription auto-deactivates.
///
/// Storage layout:
///   A single `SubStore` resource lives at the `billing` address holding
///   a `Table<u64, Subscription>` keyed by global subscription id. O(1) lookup.
module billing::subscription {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use aptos_framework::timestamp;
    use aptos_framework::table::{Self, Table};
    use billing::access_control;
    use billing::errors;
    use billing::events;
    use billing::treasury;

    // Receipt type tag
    const RECEIPT_SUBSCRIPTION: u8 = 1;

    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    struct Subscription has store, drop {
        id:               u64,
        subscriber:       address,
        merchant:         address,
        amount_per_cycle: u64,
        interval_seconds: u64,
        max_cycles:       u64,
        cycles_used:      u64,
        /// None = never charged; Some(t) = last charge timestamp.
        last_charged_at:  Option<u64>,
        active:           bool,
        token_name:       String,
    }

    struct SubStore has key {
        subs: Table<u64, Subscription>,
    }

    // -----------------------------------------------------------------------
    // Store initializer
    // -----------------------------------------------------------------------

    fun init_module(billing_signer: &signer) {
        move_to(billing_signer, SubStore {
            subs: table::new(),
        });
    }

    // -----------------------------------------------------------------------
    // Public entry: authorize
    // -----------------------------------------------------------------------

    /// Authorize a recurring billing agreement.
    /// Creates a Subscription resource acting as an on-chain allowance.
    /// No coins are locked — the payment is pulled on each `charge` call.
    public entry fun authorize<CoinType>(
        subscriber:       &signer,
        merchant:         address,
        amount_per_cycle: u64,
        interval_seconds: u64,
        max_cycles:       u64,
    ) acquires SubStore {
        access_control::assert_not_paused();
        assert!(amount_per_cycle > 0, errors::invalid_amount());
        assert!(interval_seconds > 0, errors::invalid_amount());
        assert!(max_cycles > 0, errors::invalid_amount());
        access_control::assert_token_supported<CoinType>();

        let sub_addr = signer::address_of(subscriber);
        let id = access_control::next_sub_id();
        let now = timestamp::now_seconds();
        let token_name = treasury::coin_type_name<CoinType>();

        let sub = Subscription {
            id,
            subscriber:       sub_addr,
            merchant,
            amount_per_cycle,
            interval_seconds,
            max_cycles,
            cycles_used:      0,
            last_charged_at:  option::none(), // None = never charged; first charge always allowed
            active:           true,
            token_name,
        };

        let store = borrow_global_mut<SubStore>(@billing);
        table::add(&mut store.subs, id, sub);

        events::emit_subscribed(
            id, sub_addr, merchant, amount_per_cycle,
            interval_seconds, max_cycles, token_name, now,
        );
    }

    // -----------------------------------------------------------------------
    // Public entry: charge
    // -----------------------------------------------------------------------

    /// Pull the next subscription payment.
    /// Callable by ANYONE — the contract enforces all invariants:
    ///   - Subscription must be active.
    ///   - `interval_seconds` must have elapsed since last charge (or first charge).
    ///   - `cycles_used` must be < `max_cycles`.
    public entry fun charge<CoinType>(
        caller: &signer,
        sub_id: u64,
    ) acquires SubStore {
        access_control::assert_not_paused();

        let now = timestamp::now_seconds();
        let store = borrow_global_mut<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());

        let sub = table::borrow_mut(&mut store.subs, sub_id);
        assert!(sub.active, errors::sub_cancelled());
        assert!(sub.cycles_used < sub.max_cycles, errors::max_cycles_reached());

        // Timing check: None = first charge → always allowed.
        // Some(t) = subsequent charge → must wait interval_seconds.
        if (option::is_some(&sub.last_charged_at)) {
            let last = *option::borrow(&sub.last_charged_at);
            let elapsed = now - last;
            assert!(elapsed >= sub.interval_seconds, errors::charge_too_early());
        };

        let subscriber  = sub.subscriber;
        let merchant    = sub.merchant;
        let amount      = sub.amount_per_cycle;
        let token_name  = sub.token_name;

        // Update state before transfer (checks-effects-interactions)
        sub.cycles_used     = sub.cycles_used + 1;
        sub.last_charged_at = option::some(now);
        let cycles_used_now = sub.cycles_used;

        // Auto-deactivate when max reached
        if (cycles_used_now >= sub.max_cycles) {
            sub.active = false;
        };

        // Coin transfer
        let (net, fee) = treasury::transfer_with_fee<CoinType>(caller, merchant, amount);

        events::emit_charged(sub_id, subscriber, merchant, amount, cycles_used_now, token_name, now);
        events::emit_receipt(
            RECEIPT_SUBSCRIPTION, sub_id, subscriber, merchant,
            amount, fee, net, token_name, now,
        );
    }

    // -----------------------------------------------------------------------
    // Public entry: cancel_subscription
    // -----------------------------------------------------------------------

    /// Cancel an active subscription. Only the subscriber or admin may do this.
    public entry fun cancel_subscription(
        caller: &signer,
        sub_id: u64,
    ) acquires SubStore {
        let caller_addr = signer::address_of(caller);
        let store = borrow_global_mut<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());

        let sub = table::borrow_mut(&mut store.subs, sub_id);
        assert!(sub.active, errors::sub_cancelled());

        let is_subscriber = caller_addr == sub.subscriber;
        let is_admin      = caller_addr == access_control::get_admin();
        assert!(is_subscriber || is_admin, errors::not_authorized());

        sub.active = false;
        events::emit_subscription_cancelled(sub_id, caller_addr, timestamp::now_seconds());
    }

    // -----------------------------------------------------------------------
    // #[view] read-only functions
    // -----------------------------------------------------------------------

    #[view]
    public fun get_subscription_active(sub_id: u64): bool acquires SubStore {
        let store = borrow_global<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());
        table::borrow(&store.subs, sub_id).active
    }

    #[view]
    public fun get_subscription_cycles_used(sub_id: u64): u64 acquires SubStore {
        let store = borrow_global<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());
        table::borrow(&store.subs, sub_id).cycles_used
    }

    #[view]
    public fun get_subscription_amount(sub_id: u64): u64 acquires SubStore {
        let store = borrow_global<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());
        table::borrow(&store.subs, sub_id).amount_per_cycle
    }

    #[view]
    /// Returns true if the subscription is active and a charge is due.
    public fun is_due(sub_id: u64): bool acquires SubStore {
        let store = borrow_global<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());
        let sub = table::borrow(&store.subs, sub_id);
        if (!sub.active || sub.cycles_used >= sub.max_cycles) return false;
        if (option::is_none(&sub.last_charged_at)) return true; // never charged
        let last = *option::borrow(&sub.last_charged_at);
        let now = timestamp::now_seconds();
        (now - last) >= sub.interval_seconds
    }

    #[view]
    /// Returns the unix timestamp at which the next charge becomes valid.
    /// Returns 0 if the subscription has never been charged.
    public fun next_charge_time(sub_id: u64): u64 acquires SubStore {
        let store = borrow_global<SubStore>(@billing);
        assert!(table::contains(&store.subs, sub_id), errors::sub_not_found());
        let sub = table::borrow(&store.subs, sub_id);
        if (option::is_none(&sub.last_charged_at)) return 0;
        *option::borrow(&sub.last_charged_at) + sub.interval_seconds
    }

    // -----------------------------------------------------------------------
    // Test-only helpers
    // -----------------------------------------------------------------------

    #[test_only]
    public fun init_for_test(billing_signer: &signer) {
        if (!exists<SubStore>(std::signer::address_of(billing_signer))) {
            move_to(billing_signer, SubStore { subs: table::new() });
        };
    }
}
