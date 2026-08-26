/// treasury.move
/// Generic multi-token treasury helpers for on_chain_billing.
///
/// All coin movement in the package flows through this module so that:
///   - Fee computation is centralised and consistent.
///   - Token-support validation is enforced at a single point.
///
/// Design notes:
///   - No funds are custodied here; we transfer directly between accounts.
///   - `compute_fee` uses integer arithmetic; fee rounds DOWN (floor).
module billing::treasury {
    use aptos_framework::coin;
    use aptos_framework::type_info;
    use std::string::String;
    use billing::access_control;

    // -----------------------------------------------------------------------
    // Fee computation
    // -----------------------------------------------------------------------

    /// Compute the platform fee and net amount for a given gross `amount`.
    /// `fee_bps` is in basis points (100 bps = 1%).
    /// Returns (net_amount, fee_amount) where net + fee == amount.
    public fun compute_fee(amount: u64, fee_bps: u64): (u64, u64) {
        if (fee_bps == 0 || amount == 0) {
            return (amount, 0)
        };
        // fee = floor(amount * fee_bps / 10_000)
        let fee = (amount as u128) * (fee_bps as u128) / 10_000u128;
        let fee64 = (fee as u64);
        (amount - fee64, fee64)
    }

    // -----------------------------------------------------------------------
    // Transfer helpers
    // -----------------------------------------------------------------------

    /// Transfer `amount` of `CoinType` from `from` to `to`.
    public fun transfer<CoinType>(from: &signer, to: address, amount: u64) {
        coin::transfer<CoinType>(from, to, amount);
    }

    /// Transfer `gross_amount` of `CoinType` from `payer` to `merchant`,
    /// skimming the platform fee to the `billing` treasury address.
    /// Returns (net_amount, fee_amount).
    public fun transfer_with_fee<CoinType>(
        payer:        &signer,
        merchant:     address,
        gross_amount: u64,
    ): (u64, u64) {
        let fee_bps = access_control::get_fee_bps();
        let (net, fee) = compute_fee(gross_amount, fee_bps);

        if (net > 0) {
            coin::transfer<CoinType>(payer, merchant, net);
        };
        if (fee > 0) {
            coin::transfer<CoinType>(payer, @billing, fee);
        };

        (net, fee)
    }

    // -----------------------------------------------------------------------
    // Coin-type name helper (reused by invoice / subscription)
    // -----------------------------------------------------------------------

    public fun coin_type_name<CoinType>(): String {
        type_info::type_name<CoinType>()
    }
}
