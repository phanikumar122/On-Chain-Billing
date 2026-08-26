/// access_control.move
/// Capability-based role system and global Config resource for on_chain_billing.
///
/// The `Config` resource lives at the `billing` address and holds:
///   - The current admin address
///   - A paused flag
///   - Global monotonic counters for invoices and subscriptions
///   - The supported-token registry (keyed by type-name string)
///   - Platform fee in basis points (0–10_000; default 0)
///
/// `init_module` is called exactly once when the package is published.
module billing::access_control {
    use std::signer;
    use std::string::String;
    use aptos_framework::timestamp;
    use aptos_framework::table::{Self, Table};
    use aptos_framework::type_info;
    use billing::errors;
    use billing::events;

    // -----------------------------------------------------------------------
    // Config resource
    // -----------------------------------------------------------------------

    struct Config has key {
        /// Current admin of the billing system.
        admin: address,
        /// When true, all billing operations are suspended.
        paused: bool,
        /// Monotonically increasing counter; next invoice gets this id.
        invoice_counter: u64,
        /// Monotonically increasing counter; next subscription gets this id.
        sub_counter: u64,
        /// Registry of supported coin types, keyed by type name string.
        supported_tokens: Table<String, bool>,
        /// Platform fee in basis points (100 bps = 1%). Default 0.
        fee_bps: u64,
    }

    // -----------------------------------------------------------------------
    // Module initializer (runs once at publish time)
    // -----------------------------------------------------------------------

    fun init_module(billing_signer: &signer) {
        let addr = signer::address_of(billing_signer);
        assert!(!exists<Config>(addr), errors::already_initialized());
        move_to(billing_signer, Config {
            admin: addr,
            paused: false,
            invoice_counter: 0,
            sub_counter: 0,
            supported_tokens: table::new(),
            fee_bps: 0,
        });
    }

    // -----------------------------------------------------------------------
    // Admin management
    // -----------------------------------------------------------------------

    /// Transfer admin role to `new_admin`. Only the current admin can call this.
    public fun grant_admin(caller: &signer, new_admin: address) acquires Config {
        assert_admin(caller);
        let cfg = borrow_global_mut<Config>(@billing);
        cfg.admin = new_admin;
        events::emit_admin_granted(
            new_admin,
            signer::address_of(caller),
            timestamp::now_seconds(),
        );
    }

    /// Revoke admin from `target` by setting admin back to `billing` address.
    /// Only the current admin can call this.
    public fun revoke_admin(caller: &signer, target: address) acquires Config {
        assert_admin(caller);
        let cfg = borrow_global_mut<Config>(@billing);
        cfg.admin = @billing;
        events::emit_admin_revoked(
            target,
            signer::address_of(caller),
            timestamp::now_seconds(),
        );
    }

    // -----------------------------------------------------------------------
    // Pause / unpause
    // -----------------------------------------------------------------------

    public fun pause(caller: &signer) acquires Config {
        assert_admin(caller);
        let cfg = borrow_global_mut<Config>(@billing);
        cfg.paused = true;
        events::emit_system_paused(signer::address_of(caller), timestamp::now_seconds());
    }

    public fun unpause(caller: &signer) acquires Config {
        assert_admin(caller);
        let cfg = borrow_global_mut<Config>(@billing);
        cfg.paused = false;
        events::emit_system_unpaused(signer::address_of(caller), timestamp::now_seconds());
    }

    // -----------------------------------------------------------------------
    // Token registry
    // -----------------------------------------------------------------------

    /// Register a coin type so it can be used in billing operations.
    public fun register_token<CoinType>(caller: &signer) acquires Config {
        assert_admin(caller);
        let name = type_name_of<CoinType>();
        let cfg = borrow_global_mut<Config>(@billing);
        table::upsert(&mut cfg.supported_tokens, name, true);
    }

    /// Deregister a previously supported coin type.
    public fun deregister_token<CoinType>(caller: &signer) acquires Config {
        assert_admin(caller);
        let name = type_name_of<CoinType>();
        let cfg = borrow_global_mut<Config>(@billing);
        if (table::contains(&cfg.supported_tokens, name)) {
            table::remove(&mut cfg.supported_tokens, name);
        };
    }

    // -----------------------------------------------------------------------
    // Fee management
    // -----------------------------------------------------------------------

    /// Set the platform fee in basis points. Max 10 000 (=100%).
    public fun set_fee_bps(caller: &signer, bps: u64) acquires Config {
        assert_admin(caller);
        assert!(bps <= 10_000, errors::invalid_amount());
        borrow_global_mut<Config>(@billing).fee_bps = bps;
    }

    // -----------------------------------------------------------------------
    // Counter vending (called by invoice / subscription modules)
    // -----------------------------------------------------------------------

    /// Reserve and return the next invoice id.
    public fun next_invoice_id(): u64 acquires Config {
        let cfg = borrow_global_mut<Config>(@billing);
        let id = cfg.invoice_counter;
        cfg.invoice_counter = id + 1;
        id
    }

    /// Reserve and return the next subscription id.
    public fun next_sub_id(): u64 acquires Config {
        let cfg = borrow_global_mut<Config>(@billing);
        let id = cfg.sub_counter;
        cfg.sub_counter = id + 1;
        id
    }

    // -----------------------------------------------------------------------
    // Assertions (internal use + cross-module)
    // -----------------------------------------------------------------------

    public fun assert_admin(caller: &signer) acquires Config {
        let cfg = borrow_global<Config>(@billing);
        assert!(signer::address_of(caller) == cfg.admin, errors::not_admin());
    }

    public fun assert_not_paused() acquires Config {
        assert!(!borrow_global<Config>(@billing).paused, errors::paused());
    }

    public fun assert_token_supported<CoinType>() acquires Config {
        let name = type_name_of<CoinType>();
        let cfg = borrow_global<Config>(@billing);
        assert!(
            table::contains(&cfg.supported_tokens, name),
            errors::token_not_supported(),
        );
    }

    // -----------------------------------------------------------------------
    // Read helpers
    // -----------------------------------------------------------------------

    public fun get_fee_bps(): u64 acquires Config {
        borrow_global<Config>(@billing).fee_bps
    }

    public fun get_admin(): address acquires Config {
        borrow_global<Config>(@billing).admin
    }

    public fun is_paused(): bool acquires Config {
        borrow_global<Config>(@billing).paused
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    fun type_name_of<T>(): String {
        type_info::type_name<T>()
    }

    // -----------------------------------------------------------------------
    // Test-only initializer
    // -----------------------------------------------------------------------

    #[test_only]
    public fun init_for_test(billing_signer: &signer) {
        let addr = signer::address_of(billing_signer);
        if (!exists<Config>(addr)) {
            move_to(billing_signer, Config {
                admin: addr,
                paused: false,
                invoice_counter: 0,
                sub_counter: 0,
                supported_tokens: table::new(),
                fee_bps: 0,
            });
        };
    }
}
