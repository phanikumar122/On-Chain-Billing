#[test_only]
/// access_control_tests.move
/// Tests for the capability-based access control system.
module billing::access_control_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use billing::access_control;
    use billing::invoice;
    use billing::subscription;

    // -----------------------------------------------------------------------
    // Test helpers
    // -----------------------------------------------------------------------

    fun setup(aptos: &signer, billing_signer: &signer) {
        timestamp::set_time_has_started_for_testing(aptos);
        account::create_account_for_test(signer::address_of(billing_signer));
        access_control::init_for_test(billing_signer);
        invoice::init_for_test(billing_signer);
        subscription::init_for_test(billing_signer);
    }

    // -----------------------------------------------------------------------
    // Test: non-admin cannot call admin operations (grant_admin)
    // abort_code = error::permission_denied(301) = 0x50000 | 301 = 327981
    // In Move test framework abort codes are raw u64 values.
    // error::permission_denied(x) = (5 << 16) | x
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing, rando = @0xBEEF)]
    #[expected_failure]
    public fun test_non_admin_grant_fails(
        aptos: signer, billing_signer: signer, rando: signer
    ) {
        setup(&aptos, &billing_signer);
        account::create_account_for_test(signer::address_of(&rando));
        // rando is not admin → should abort
        access_control::grant_admin(&rando, @0xDEAD);
    }

    #[test(aptos = @aptos_framework, billing_signer = @billing, rando = @0xBEEF)]
    #[expected_failure]
    public fun test_non_admin_pause_fails(
        aptos: signer, billing_signer: signer, rando: signer
    ) {
        setup(&aptos, &billing_signer);
        account::create_account_for_test(signer::address_of(&rando));
        access_control::pause(&rando);
    }

    // -----------------------------------------------------------------------
    // Test: pause / unpause flow
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing)]
    public fun test_pause_unpause(aptos: signer, billing_signer: signer) {
        setup(&aptos, &billing_signer);
        assert!(!access_control::is_paused(), 0);
        access_control::pause(&billing_signer);
        assert!(access_control::is_paused(), 1);
        access_control::unpause(&billing_signer);
        assert!(!access_control::is_paused(), 2);
    }

    // -----------------------------------------------------------------------
    // Test: grant / revoke admin
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing, new_admin = @0xA1)]
    public fun test_grant_revoke_admin(
        aptos: signer, billing_signer: signer, new_admin: signer
    ) {
        setup(&aptos, &billing_signer);
        account::create_account_for_test(signer::address_of(&new_admin));
        let new_addr = signer::address_of(&new_admin);

        access_control::grant_admin(&billing_signer, new_addr);
        assert!(access_control::get_admin() == new_addr, 0);

        // new admin revokes back to billing
        access_control::revoke_admin(&new_admin, new_addr);
        assert!(access_control::get_admin() == @billing, 1);
    }

    // -----------------------------------------------------------------------
    // Test: fee basis points
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing)]
    public fun test_set_fee_bps(aptos: signer, billing_signer: signer) {
        setup(&aptos, &billing_signer);
        assert!(access_control::get_fee_bps() == 0, 0);
        access_control::set_fee_bps(&billing_signer, 250); // 2.5%
        assert!(access_control::get_fee_bps() == 250, 1);
    }

    // -----------------------------------------------------------------------
    // Test: non-admin setting fee aborts
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing, rando = @0xDEAD)]
    #[expected_failure]
    public fun test_non_admin_set_fee_fails(
        aptos: signer, billing_signer: signer, rando: signer
    ) {
        setup(&aptos, &billing_signer);
        account::create_account_for_test(signer::address_of(&rando));
        access_control::set_fee_bps(&rando, 500);
    }
}
