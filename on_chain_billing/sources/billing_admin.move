/// billing_admin.move
/// Entry-function façade that exposes all admin operations to CLI / SDK callers.
/// Every function here is an `entry` wrapper over the internal logic in
/// access_control. This keeps business logic in the library modules while
/// giving external callers clean, ABI-stable entry points.
module billing::billing_admin {
    use billing::access_control;
    use aptos_framework::coin;

    // -----------------------------------------------------------------------
    // Admin management
    // -----------------------------------------------------------------------

    /// Grant the admin role to `new_admin`. Only the current admin may call this.
    public entry fun grant_admin(caller: &signer, new_admin: address) {
        access_control::grant_admin(caller, new_admin);
    }

    /// Revoke admin from `target`; resets admin to the billing address.
    public entry fun revoke_admin(caller: &signer, target: address) {
        access_control::revoke_admin(caller, target);
    }

    // -----------------------------------------------------------------------
    // System pause / unpause
    // -----------------------------------------------------------------------

    /// Suspend all billing operations. Admin only.
    public entry fun pause(caller: &signer) {
        access_control::pause(caller);
    }

    /// Resume billing operations after a pause. Admin only.
    public entry fun unpause(caller: &signer) {
        access_control::unpause(caller);
    }

    // -----------------------------------------------------------------------
    // Token registry
    // -----------------------------------------------------------------------

    /// Register `CoinType` so it can be used in invoices and subscriptions.
    public entry fun register_token<CoinType>(caller: &signer) {
        access_control::register_token<CoinType>(caller);
    }

    /// Remove `CoinType` from the supported-token registry.
    public entry fun deregister_token<CoinType>(caller: &signer) {
        access_control::deregister_token<CoinType>(caller);
    }

    // -----------------------------------------------------------------------
    // Fee configuration
    // -----------------------------------------------------------------------

    /// Set the platform fee in basis points (e.g. 50 = 0.5%). Max 10 000.
    public entry fun set_platform_fee_bps(caller: &signer, bps: u64) {
        access_control::set_fee_bps(caller, bps);
    }

    // -----------------------------------------------------------------------
    // Treasury view functions
    // -----------------------------------------------------------------------

    /// Returns the current platform fee in basis points.
    #[view]
    public fun get_fee_bps(): u64 {
        access_control::get_fee_bps()
    }

    /// Returns the current admin address.
    #[view]
    public fun get_admin(): address {
        access_control::get_admin()
    }

    /// Returns whether the system is paused.
    #[view]
    public fun is_paused(): bool {
        access_control::is_paused()
    }

    /// Returns the on-chain coin balance of the billing treasury address
    /// for the given CoinType. This reflects accumulated platform fees.
    #[view]
    public fun get_treasury_balance<CoinType>(): u64 {
        coin::balance<CoinType>(@billing)
    }
}
