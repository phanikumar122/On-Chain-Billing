#[test_only]
/// subscription_tests.move
/// Comprehensive tests for the recurring subscription billing module.
module billing::subscription_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::timestamp;
    use billing::access_control;
    use billing::subscription;

    // -----------------------------------------------------------------------
    // Fake coin for subscription tests
    // -----------------------------------------------------------------------

    struct SubCoin {}

    struct SubCaps has key {
        mint: MintCapability<SubCoin>,
        burn: BurnCapability<SubCoin>,
    }

    fun init_coin(billing_signer: &signer) {
        let (burn, freeze, mint) = coin::initialize<SubCoin>(
            billing_signer,
            string::utf8(b"SubCoin"),
            string::utf8(b"SUB"),
            6,
            false,
        );
        coin::destroy_freeze_cap(freeze);
        move_to(billing_signer, SubCaps { mint, burn });
    }

    fun fund_from_store(billing_signer: &signer, acct: &signer, amount: u64)
    acquires SubCaps {
        let addr = signer::address_of(acct);
        if (!coin::is_account_registered<SubCoin>(addr)) {
            coin::register<SubCoin>(acct);
        };
        let caps = borrow_global<SubCaps>(signer::address_of(billing_signer));
        coin::deposit(addr, coin::mint(amount, &caps.mint));
    }

    // -----------------------------------------------------------------------
    // Common setup
    // -----------------------------------------------------------------------

    fun setup(
        aptos: &signer,
        billing_signer: &signer,
        subscriber: &signer,
        merchant: &signer,
    ) acquires SubCaps {
        timestamp::set_time_has_started_for_testing(aptos);
        coin::create_coin_conversion_map(aptos);

        account::create_account_for_test(signer::address_of(billing_signer));
        account::create_account_for_test(signer::address_of(subscriber));
        account::create_account_for_test(signer::address_of(merchant));

        access_control::init_for_test(billing_signer);
        subscription::init_for_test(billing_signer);

        init_coin(billing_signer);
        access_control::register_token<SubCoin>(billing_signer);

        // Billing address registers to receive fees
        coin::register<SubCoin>(billing_signer);

        fund_from_store(billing_signer, subscriber, 10_000_000);
        if (!coin::is_account_registered<SubCoin>(signer::address_of(merchant))) {
            coin::register<SubCoin>(merchant);
        };
    }

    // -----------------------------------------------------------------------
    // Test 1: authorize + first charge succeeds
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x51, merchant = @0x52)]
    public fun test_authorize_and_first_charge(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);
        let merchant_addr = signer::address_of(&merchant);

        subscription::authorize<SubCoin>(
            &subscriber, merchant_addr, 100_000, 3600, 10,
        );

        let bal_before = coin::balance<SubCoin>(merchant_addr);
        subscription::charge<SubCoin>(&subscriber, 0);

        assert!(coin::balance<SubCoin>(merchant_addr) == bal_before + 100_000, 0);
        assert!(subscription::get_subscription_cycles_used(0) == 1, 1);
        assert!(subscription::get_subscription_active(0), 2);
    }

    // -----------------------------------------------------------------------
    // Test 2: charging too early aborts
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x53, merchant = @0x54)]
    #[expected_failure]
    public fun test_charge_too_early(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 50_000, 3600, 5,
        );

        subscription::charge<SubCoin>(&subscriber, 0); // ok
        subscription::charge<SubCoin>(&subscriber, 0); // too early → abort
    }

    // -----------------------------------------------------------------------
    // Test 2b: advance timestamp → second charge succeeds
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x55, merchant = @0x56)]
    public fun test_charge_after_interval(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 50_000, 3600, 5,
        );

        subscription::charge<SubCoin>(&subscriber, 0);
        timestamp::fast_forward_seconds(3600);
        subscription::charge<SubCoin>(&subscriber, 0);

        assert!(subscription::get_subscription_cycles_used(0) == 2, 0);
    }

    // -----------------------------------------------------------------------
    // Test 3: max cycles reached → auto-deactivation + abort on next
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x57, merchant = @0x58)]
    #[expected_failure]
    public fun test_max_cycles_reached(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 100, 3,
        );

        subscription::charge<SubCoin>(&subscriber, 0);
        timestamp::fast_forward_seconds(100);
        subscription::charge<SubCoin>(&subscriber, 0);
        timestamp::fast_forward_seconds(100);
        subscription::charge<SubCoin>(&subscriber, 0); // cycle 3 → deactivates

        assert!(!subscription::get_subscription_active(0), 0);

        timestamp::fast_forward_seconds(100);
        subscription::charge<SubCoin>(&subscriber, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 4: cancel subscription
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x59, merchant = @0x5A)]
    public fun test_cancel_subscription(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 12,
        );
        subscription::cancel_subscription(&subscriber, 0);
        assert!(!subscription::get_subscription_active(0), 0);
    }

    // -----------------------------------------------------------------------
    // Test 5: charge on cancelled subscription aborts
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x5B, merchant = @0x5C)]
    #[expected_failure]
    public fun test_charge_cancelled_sub(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 12,
        );
        subscription::cancel_subscription(&subscriber, 0);
        subscription::charge<SubCoin>(&subscriber, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 6: random address cannot cancel subscription
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x5D, merchant = @0x5E, rando = @0x5F)]
    #[expected_failure]
    public fun test_rando_cannot_cancel_sub(
        aptos: signer, billing_signer: signer,
        subscriber: signer, merchant: signer, rando: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);
        account::create_account_for_test(signer::address_of(&rando));

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 12,
        );
        subscription::cancel_subscription(&rando, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 7: is_due view function
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x61, merchant = @0x62)]
    public fun test_is_due(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 5,
        );

        assert!(subscription::is_due(0), 0);
        subscription::charge<SubCoin>(&subscriber, 0);
        assert!(!subscription::is_due(0), 1);
        timestamp::fast_forward_seconds(3600);
        assert!(subscription::is_due(0), 2);
    }

    // -----------------------------------------------------------------------
    // Test 8: next_charge_time view function
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x63, merchant = @0x64)]
    public fun test_next_charge_time(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);

        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 5,
        );

        assert!(subscription::next_charge_time(0) == 0, 0);
        subscription::charge<SubCoin>(&subscriber, 0);
        let charged_at = timestamp::now_seconds();
        assert!(subscription::next_charge_time(0) == charged_at + 3600, 1);
    }

    // -----------------------------------------------------------------------
    // Test 9: authorize while paused aborts
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           subscriber = @0x65, merchant = @0x66)]
    #[expected_failure]
    public fun test_authorize_while_paused(
        aptos: signer, billing_signer: signer, subscriber: signer, merchant: signer
    ) acquires SubCaps {
        setup(&aptos, &billing_signer, &subscriber, &merchant);
        access_control::pause(&billing_signer);
        subscription::authorize<SubCoin>(
            &subscriber, signer::address_of(&merchant), 10_000, 3600, 5,
        );
    }
}
