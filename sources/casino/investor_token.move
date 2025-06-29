//! MIT License
//!
//! InvestorToken Fungible Asset Implementation (Refactored)
//!
//! NAV-based investor tokens for the ChainCasino platform.
//! Now uses modern Fungible Asset standard throughout.

module casino::InvestorToken {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{
        Self,
        Metadata,
        MintRef,
        BurnRef,
        TransferRef,
        FungibleAsset
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use aptos_std::math64;
    use casino::CasinoHouse;

    //
    // Error Codes
    //

    /// InvestorToken init not called by @casino
    const E_UNAUTHORIZED_INIT: u64 = 0x70;
    /// Invalid amount (zero or exceeds limits)
    const E_INVALID_AMOUNT: u64 = 0x71;
    /// Insufficient FA balance for operation
    const E_INSUFFICIENT_BALANCE: u64 = 0x72;
    /// Treasury insufficient for redemption
    const E_INSUFFICIENT_TREASURY: u64 = 0x73;
    /// Invalid FA metadata object
    const E_INVALID_METADATA: u64 = 0x74;
    /// FA transfers are frozen
    const E_TRANSFERS_FROZEN: u64 = 0x75;

    //
    // Constants
    //

    /// Fixed-point scale for NAV calculations (6 decimal places)
    const NAV_SCALE: u64 = 1_000_000;
    /// Default redemption fee (0.1%)
    const DEFAULT_FEE_BPS: u64 = 10;
    /// Minimum redemption fee (0.001 APT in octas)
    const MIN_FEE_APT: u64 = 1_000;

    //
    // Resource Specifications
    //

    /// Capability references for FA operations
    struct InvestorTokenRefs has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
        extend_ref: ExtendRef
    }

    /// Economic metadata for dividend tracking
    struct DividendMetadata has key {
        treasury_backing_ratio: u64,
        total_dividends_paid: u64,
        creation_timestamp: u64
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when investor redeems tokens for profit
    struct DividendPaidEvent has drop, store {
        recipient: address,
        amount: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize the InvestorToken fungible asset
    public entry fun init(owner: &signer) {
        assert!(signer::address_of(owner) == @casino, E_UNAUTHORIZED_INIT);

        let constructor_ref = object::create_named_object(owner, b"InvestorToken");

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"ChainCasino Investor Token"),
            string::utf8(b"CCIT"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        let metadata_signer = object::generate_signer(&constructor_ref);
        move_to(
            &metadata_signer,
            InvestorTokenRefs { mint_ref, burn_ref, transfer_ref, extend_ref }
        );

        move_to(
            &metadata_signer,
            DividendMetadata {
                treasury_backing_ratio: NAV_SCALE,
                total_dividends_paid: 0,
                creation_timestamp: timestamp::now_seconds()
            }
        );
    }

    //
    // Core Economic Interface - REFACTORED
    //

    #[view]
    /// Calculate current Net Asset Value per token (safe overflow handling)
    public fun nav(): u64 {
        let treasury_balance = treasury_balance();
        let total_supply = total_supply();

        if (total_supply == 0) {
            NAV_SCALE
        } else {
            let treasury_u128 = (treasury_balance as u128);
            let nav_scale_u128 = (NAV_SCALE as u128);
            let supply_u128 = (total_supply as u128);

            let result_u128 = (treasury_u128 * nav_scale_u128) / supply_u128;
            (result_u128 as u64)
        }
    }

    /// Deposit APT and mint proportional InvestorTokens - REFACTORED
    public entry fun deposit_and_mint(
        user: &signer, amount: u64
    ) acquires InvestorTokenRefs, DividendMetadata {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let treasury_balance = treasury_balance();
        let total_supply = total_supply();
        let metadata = get_metadata();

        let tokens_to_mint =
            if (total_supply == 0) { amount }
            else {
                let amount_u128 = (amount as u128);
                let supply_u128 = (total_supply as u128);
                let treasury_u128 = (treasury_balance as u128);

                let result_u128 = (amount_u128 * supply_u128) / treasury_u128;
                (result_u128 as u64)
            };

        // Withdraw APT from user as FungibleAsset
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let deposit_fa = primary_fungible_store::withdraw(user, aptos_metadata, amount);

        // Transfer APT to casino treasury
        deposit_to_treasury(deposit_fa);

        // Mint tokens to user
        let refs = borrow_global<InvestorTokenRefs>(object::object_address(&metadata));
        let fa = fungible_asset::mint(&refs.mint_ref, tokens_to_mint);

        let user_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(user), metadata
            );
        fungible_asset::deposit(user_store, fa);

        update_nav_tracking();
    }

    /// Burn InvestorTokens and redeem APT at current NAV - REFACTORED
    public entry fun redeem(user: &signer, tokens: u64) acquires InvestorTokenRefs, DividendMetadata {
        assert!(tokens > 0, E_INVALID_AMOUNT);

        let user_addr = signer::address_of(user);
        let metadata = get_metadata();

        let user_balance = primary_fungible_store::balance(user_addr, metadata);
        assert!(user_balance >= tokens, E_INSUFFICIENT_BALANCE);

        let current_nav = nav();

        // Calculate gross amount using u128
        let tokens_u128 = (tokens as u128);
        let nav_u128 = (current_nav as u128);
        let scale_u128 = (NAV_SCALE as u128);
        let gross_amount = ((tokens_u128 * nav_u128) / scale_u128) as u64;

        let fee = calculate_fee(gross_amount);
        let net_amount = if (gross_amount > fee) {
            gross_amount - fee
        } else { 0 };

        let treasury_balance = treasury_balance();
        assert!(net_amount <= treasury_balance, E_INSUFFICIENT_TREASURY);

        // Burn user tokens
        let refs = borrow_global<InvestorTokenRefs>(object::object_address(&metadata));
        let fa_to_burn = primary_fungible_store::withdraw(user, metadata, tokens);
        fungible_asset::burn(&refs.burn_ref, fa_to_burn);

        // Withdraw from treasury and pay user (only if net_amount > 0)
        if (net_amount > 0) {
            let payout_fa = redeem_from_treasury(net_amount);
            let aptos_metadata_option =
                coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
            let aptos_metadata = option::extract(&mut aptos_metadata_option);
            let user_aptos_store =
                primary_fungible_store::ensure_primary_store_exists(
                    user_addr, aptos_metadata
                );
            fungible_asset::deposit(user_aptos_store, payout_fa);
        };

        // Calculate profit for dividend event
        let profit =
            if (gross_amount > tokens) {
                gross_amount - tokens
            } else { 0 };

        event::emit(DividendPaidEvent { recipient: user_addr, amount: profit });

        update_nav_tracking();
    }

    //
    // Fee Calculation Interface
    //

    fun calculate_fee(gross_amount: u64): u64 {
        let percentage_fee = (gross_amount * DEFAULT_FEE_BPS) / 10000;
        math64::max(percentage_fee, MIN_FEE_APT)
    }

    //
    // View Interface
    //

    #[view]
    public fun get_metadata(): Object<Metadata> {
        object::address_to_object<Metadata>(
            object::create_object_address(&@casino, b"InvestorToken")
        )
    }

    #[view]
    public fun get_dividend_info(): (u64, u64, u64) acquires DividendMetadata {
        let metadata = get_metadata();
        let metadata_addr = object::object_address(&metadata);
        let dividend_data = borrow_global<DividendMetadata>(metadata_addr);

        (
            dividend_data.treasury_backing_ratio,
            dividend_data.total_dividends_paid,
            dividend_data.creation_timestamp
        )
    }

    #[view]
    public fun user_balance(user: address): u64 {
        let metadata = get_metadata();
        primary_fungible_store::balance(user, metadata)
    }

    #[view]
    public fun total_supply(): u64 {
        let metadata = get_metadata();
        let supply_option = fungible_asset::supply(metadata);
        if (option::is_some(&supply_option)) {
            let supply_u128 = option::extract(&mut supply_option);
            (supply_u128 as u64)
        } else { 0 }
    }

    #[view]
    public fun treasury_balance(): u64 {
        CasinoHouse::treasury_balance()
    }

    //
    // Treasury Integration Functions - REFACTORED
    //

    fun deposit_to_treasury(fa: FungibleAsset) {
        CasinoHouse::deposit_to_treasury(fa);
    }

    fun redeem_from_treasury(amount: u64): FungibleAsset {
        CasinoHouse::redeem_from_treasury(amount)
    }

    fun update_nav_tracking() acquires DividendMetadata {
        let metadata = get_metadata();
        let metadata_addr = object::object_address(&metadata);
        let dividend_data = borrow_global_mut<DividendMetadata>(metadata_addr);
        dividend_data.treasury_backing_ratio = nav();
    }
}
