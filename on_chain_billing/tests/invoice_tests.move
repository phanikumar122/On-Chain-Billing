#[test_only]
/// invoice_tests.move
/// Comprehensive tests for the invoice lifecycle.
/// Uses a test-only FakeCoin for CoinType.
module billing::invoice_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::timestamp;
    use billing::access_control;
    use billing::invoice;

    // -----------------------------------------------------------------------
    // Fake coin for testing
    // -----------------------------------------------------------------------

    struct FakeCoin {}

    struct FakeCaps has key {
        mint: MintCapability<FakeCoin>,
        burn: BurnCapability<FakeCoin>,
    }

    /// Initialize FakeCoin and store caps under billing address.
    fun init_coin(billing_signer: &signer) {
        let (burn, freeze, mint) = coin::initialize<FakeCoin>(
            billing_signer,
            string::utf8(b"FakeCoin"),
            string::utf8(b"FAK"),
            6,
            false,
        );
        coin::destroy_freeze_cap(freeze);
        move_to(billing_signer, FakeCaps { mint, burn });
    }

    fun fund_account_from_store(billing_signer: &signer, acct: &signer, amount: u64)
    acquires FakeCaps {
        let addr = signer::address_of(acct);
        if (!coin::is_account_registered<FakeCoin>(addr)) {
            coin::register<FakeCoin>(acct);
        };
        let caps = borrow_global<FakeCaps>(signer::address_of(billing_signer));
        let coins = coin::mint<FakeCoin>(amount, &caps.mint);
        coin::deposit(addr, coins);
    }

    // -----------------------------------------------------------------------
    // Common setup — initializes everything under billing_signer
    // -----------------------------------------------------------------------

    fun setup(
        aptos: &signer,
        billing_signer: &signer,
        merchant: &signer,
        payer: &signer,
    ) acquires FakeCaps {
        timestamp::set_time_has_started_for_testing(aptos);
        // Create CoinConversionMap required by coin::deposit in newer Aptos framework
        coin::create_coin_conversion_map(aptos);

        account::create_account_for_test(signer::address_of(billing_signer));
        account::create_account_for_test(signer::address_of(merchant));
        account::create_account_for_test(signer::address_of(payer));

        access_control::init_for_test(billing_signer);
        invoice::init_for_test(billing_signer);

        init_coin(billing_signer);

        access_control::register_token<FakeCoin>(billing_signer);

        // Register billing address for receiving fees
        coin::register<FakeCoin>(billing_signer);

        // Fund payer
        fund_account_from_store(billing_signer, payer, 1_000_000);
        // Register merchant
        if (!coin::is_account_registered<FakeCoin>(signer::address_of(merchant))) {
            coin::register<FakeCoin>(merchant);
        };
    }

    // -----------------------------------------------------------------------
    // Test 1: create + pay succeeds; merchant balance correct; status = Paid
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xC1, payer = @0xC2)]
    public fun test_create_and_pay_invoice(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);

        let merchant_addr = signer::address_of(&merchant);
        let payer_addr    = signer::address_of(&payer);

        invoice::create_invoice<FakeCoin>(
            &merchant, payer_addr, 100_000,
            timestamp::now_seconds() + 3600,
            string::utf8(b"Test invoice"),
        );

        assert!(invoice::get_invoice_status(0) == invoice::status_pending(), 0);
        assert!(invoice::get_invoice_merchant(0) == merchant_addr, 1);
        assert!(invoice::get_invoice_payer(0) == payer_addr, 2);

        let payer_before    = coin::balance<FakeCoin>(payer_addr);
        let merchant_before = coin::balance<FakeCoin>(merchant_addr);

        invoice::pay_invoice<FakeCoin>(&payer, 0);

        assert!(invoice::get_invoice_status(0) == invoice::status_paid(), 3);
        assert!(coin::balance<FakeCoin>(merchant_addr) == merchant_before + 100_000, 4);
        assert!(coin::balance<FakeCoin>(payer_addr) == payer_before - 100_000, 5);
    }

    // -----------------------------------------------------------------------
    // Test 2: double pay rejected
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xD1, payer = @0xD2)]
    #[expected_failure]
    public fun test_double_pay_rejected(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"dup"),
        );
        invoice::pay_invoice<FakeCoin>(&payer, 0);
        invoice::pay_invoice<FakeCoin>(&payer, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 3: cancel then pay fails
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xE1, payer = @0xE2)]
    #[expected_failure]
    public fun test_cancelled_pay_rejected(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"cancel"),
        );
        invoice::cancel_invoice(&merchant, 0);
        invoice::pay_invoice<FakeCoin>(&payer, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 4a: dispute — payer wins → Cancelled
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xF1, payer = @0xF2)]
    public fun test_dispute_payer_wins(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"disputed"),
        );
        invoice::flag_dispute(&payer, 0, string::utf8(b"Wrong amount"));
        assert!(invoice::get_invoice_status(0) == invoice::status_disputed(), 0);

        invoice::resolve_dispute(&billing_signer, 0, true);
        assert!(invoice::get_invoice_status(0) == invoice::status_cancelled(), 1);
    }

    // -----------------------------------------------------------------------
    // Test 4b: dispute — merchant wins → Paid
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xF3, payer = @0xF4)]
    public fun test_dispute_merchant_wins(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"disputed2"),
        );
        invoice::flag_dispute(&payer, 0, string::utf8(b"Disagree"));
        invoice::resolve_dispute(&billing_signer, 0, false);
        assert!(invoice::get_invoice_status(0) == invoice::status_paid(), 0);
    }

    // -----------------------------------------------------------------------
    // Test 5: resolve on non-disputed fails
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xF5, payer = @0xF6)]
    #[expected_failure]
    public fun test_resolve_non_disputed_fails(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"nodispute"),
        );
        invoice::resolve_dispute(&billing_signer, 0, true); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 6: non-payer cannot pay
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xB1, payer = @0xB2, rando = @0xB3)]
    #[expected_failure]
    public fun test_wrong_payer_rejected(
        aptos: signer, billing_signer: signer, merchant: signer,
        payer: signer, rando: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        account::create_account_for_test(signer::address_of(&rando));
        fund_account_from_store(&billing_signer, &rando, 500_000);

        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"wrong payer"),
        );
        invoice::pay_invoice<FakeCoin>(&rando, 0); // should abort
    }

    // -----------------------------------------------------------------------
    // Test 7: billing while paused aborts
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xA5, payer = @0xA6)]
    #[expected_failure]
    public fun test_create_invoice_while_paused(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        access_control::pause(&billing_signer);
        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"paused"),
        );
    }

    // -----------------------------------------------------------------------
    // Test 8: unsupported token aborts
    // -----------------------------------------------------------------------

    struct OtherCoin {}

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xA7, payer = @0xA8)]
    #[expected_failure]
    public fun test_unsupported_token_rejected(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        invoice::create_invoice<OtherCoin>(
            &merchant, signer::address_of(&payer), 50_000,
            timestamp::now_seconds() + 3600, string::utf8(b"bad token"),
        );
    }

    // -----------------------------------------------------------------------
    // Test 9: platform fee → merchant receives net; billing address receives fee
    // -----------------------------------------------------------------------

    #[test(aptos = @aptos_framework, billing_signer = @billing,
           merchant = @0xA9, payer = @0xAA)]
    public fun test_invoice_with_fee(
        aptos: signer, billing_signer: signer, merchant: signer, payer: signer
    ) acquires FakeCaps {
        setup(&aptos, &billing_signer, &merchant, &payer);
        access_control::set_fee_bps(&billing_signer, 100); // 1%

        invoice::create_invoice<FakeCoin>(
            &merchant, signer::address_of(&payer), 100_000,
            timestamp::now_seconds() + 3600, string::utf8(b"fee test"),
        );

        let merchant_before = coin::balance<FakeCoin>(signer::address_of(&merchant));
        invoice::pay_invoice<FakeCoin>(&payer, 0);

        assert!(coin::balance<FakeCoin>(signer::address_of(&merchant)) == merchant_before + 99_000, 0);
        assert!(coin::balance<FakeCoin>(@billing) == 1_000, 1);
    }
}
