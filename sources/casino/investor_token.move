//! MIT License
//!
//! Investor Token for ChainCasino Platform
//!
//! ERC-20 compatible token representing ownership in casino profits.

module casino::InvestorToken {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::event;
    use aptos_framework::timestamp;
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

    /// Type of investor token operation
    enum TokenOperation has copy, drop, store {
        /// User deposited APT and minted CCIT tokens
        Mint {
            apt_amount: u64,
            tokens_minted: u64
        },
        /// User redeemed CCIT tokens for APT
        Redeem {
            tokens_burned: u64,
            apt_received: u64,
            fee_paid: u64
        }
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

    #[event]
    /// Emitted for all token operations with detailed info
    struct TokenOperationEvent has drop, store {
        user: address,
        operation: TokenOperation,
        nav_before: u64,
        nav_after: u64,
        timestamp: u64
    }

    #[event]
    /// Emitted when treasury composition changes
    struct TreasuryCompositionEvent has drop, store {
        central_balance: u64,
        total_game_balance: u64,
        total_balance: u64,
        nav_per_token: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize the InvestorToken fungible asset automatically on deployment
    fun init_module(deployer: &signer) {
        assert!(signer::address_of(deployer) == @casino, E_UNAUTHORIZED_INIT);

        let constructor_ref = object::create_named_object(deployer, b"InvestorToken");

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"ChainCasino Investor Token"),
            string::utf8(b"CCIT"),
            8,
            string::utf8(b"https://chaincasino.eu/ccit-logo.png"),
            string::utf8(b"https://chaincasino.eu")
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

    #[test_only]
    /// Test helper for initialization in tests
    public fun init_module_for_test(test_signer: &signer) {
        init_module(test_signer);
    }

    //
    // Core Economic Interface
    //

    #[view]
    /// Calculate current Net Asset Value per token (aggregates all treasuries)
    public fun nav(): u64 {
        let total_treasury_balance = treasury_balance();
        let total_supply = total_supply();

        if (total_supply == 0) {
            NAV_SCALE
        } else {
            let treasury_u128 = (total_treasury_balance as u128);
            let nav_scale_u128 = (NAV_SCALE as u128);
            let supply_u128 = (total_supply as u128);

            let result_u128 = (treasury_u128 * nav_scale_u128) / supply_u128;
            (result_u128 as u64)
        }
    }

    /// Deposit APT and mint proportional InvestorTokens
    public entry fun deposit_and_mint(
        user: &signer, amount: u64
    ) acquires InvestorTokenRefs, DividendMetadata {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let total_treasury_balance = treasury_balance();
        let total_supply = total_supply();
        let metadata = get_metadata();

        let tokens_to_mint =
            if (total_supply == 0) { amount }
            else {
                let amount_u128 = (amount as u128);
                let supply_u128 = (total_supply as u128);
                let treasury_u128 = (total_treasury_balance as u128);

                let result_u128 = (amount_u128 * supply_u128) / treasury_u128;
                (result_u128 as u64)
            };

        // Withdraw APT from user as FungibleAsset
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let deposit_fa = primary_fungible_store::withdraw(user, aptos_metadata, amount);

        // Transfer APT to central treasury (deposits flow to central)
        CasinoHouse::deposit_to_treasury(deposit_fa);

        // Mint tokens to user
        let refs = borrow_global<InvestorTokenRefs>(object::object_address(&metadata));
        let fa = fungible_asset::mint(&refs.mint_ref, tokens_to_mint);

        let user_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(user), metadata
            );
        fungible_asset::deposit(user_store, fa);

        update_nav_tracking();
        emit_treasury_composition_event();

        let user_addr = signer::address_of(user);
        event::emit(
            TokenOperationEvent {
                user: user_addr,
                operation: TokenOperation::Mint {
                    apt_amount: amount,
                    tokens_minted: tokens_to_mint
                },
                nav_before: nav(),
                nav_after: nav(),
                timestamp: timestamp::now_seconds()
            }
        );
    }

    /// Burn InvestorTokens and redeem APT at current NAV
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

        let total_treasury_balance = treasury_balance();
        assert!(net_amount <= total_treasury_balance, E_INSUFFICIENT_TREASURY);

        // Burn user tokens
        let refs = borrow_global<InvestorTokenRefs>(object::object_address(&metadata));
        let fa_to_burn = primary_fungible_store::withdraw(user, metadata, tokens);
        fungible_asset::burn(&refs.burn_ref, fa_to_burn);

        // Withdraw from central treasury and pay user (only if net_amount > 0)
        if (net_amount > 0) {
            let payout_fa = CasinoHouse::redeem_from_treasury(net_amount);
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
        emit_treasury_composition_event();

        event::emit(
            TokenOperationEvent {
                user: user_addr,
                operation: TokenOperation::Redeem {
                    tokens_burned: tokens,
                    apt_received: net_amount,
                    fee_paid: fee
                },
                nav_before: current_nav,
                nav_after: nav(),
                timestamp: timestamp::now_seconds()
            }
        );
    }

    //
    // Fee Calculation Interface
    //

    fun calculate_fee(gross_amount: u64): u64 {
        let percentage_fee = (gross_amount * DEFAULT_FEE_BPS) / 10000;
        math64::max(percentage_fee, MIN_FEE_APT)
    }

    //
    // Treasury Composition Tracking
    //

    fun emit_treasury_composition_event() {
        let central_balance = CasinoHouse::central_treasury_balance();
        let total_balance = CasinoHouse::treasury_balance();
        let total_game_balance = total_balance - central_balance;
        let nav_per_token = nav();

        event::emit(
            TreasuryCompositionEvent {
                central_balance,
                total_game_balance,
                total_balance,
                nav_per_token
            }
        );
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
    /// Get total treasury balance (central + all game treasuries)
    public fun treasury_balance(): u64 {
        CasinoHouse::treasury_balance()
    }

    #[view]
    /// Get central treasury balance only
    public fun central_treasury_balance(): u64 {
        CasinoHouse::central_treasury_balance()
    }

    #[view]
    /// Get treasury composition breakdown
    public fun treasury_composition(): (u64, u64, u64) {
        let central_balance = CasinoHouse::central_treasury_balance();
        let total_balance = CasinoHouse::treasury_balance();
        let game_balance = total_balance - central_balance;
        (central_balance, game_balance, total_balance)
    }

    //
    // Internal Functions
    //

    fun update_nav_tracking() acquires DividendMetadata {
        let metadata = get_metadata();
        let metadata_addr = object::object_address(&metadata);
        let dividend_data = borrow_global_mut<DividendMetadata>(metadata_addr);
        dividend_data.treasury_backing_ratio = nav();
    }
}
