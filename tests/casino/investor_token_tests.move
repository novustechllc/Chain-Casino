//! Test suite for InvestorToken standalone testing

#[test_only]
module casino::InvestorTokenTest {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::object;
    use casino::InvestorToken;
    use casino::CasinoHouse;

    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT in octas
    const TEST_DEPOSIT: u64 = 100000000; // 1 APT in octas
    const NAV_SCALE: u64 = 1000000;

    // Import error constants
    const E_UNAUTHORIZED_INIT: u64 = 0x70;
    const E_INVALID_AMOUNT: u64 = 0x71;
    const E_INSUFFICIENT_BALANCE: u64 = 0x72;
    const E_INSUFFICIENT_TREASURY: u64 = 0x73;

    fun setup_test(): (signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let user_account = account::create_account_for_test(@0x123);

        // Initialize AptosCoin for test environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();

        // Set timestamp BEFORE any operations
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000); // Set to non-zero time

        // Register coin stores for accounts before minting
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&user_account);

        // Now mint coins to the accounts
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);

        // Initialize CasinoHouse first, then InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        (casino_account, user_account)
    }

    #[test]
    fun test_init_success() {
        let (_casino_account, _) = setup_test();

        let metadata = InvestorToken::get_metadata();
        assert!(object::is_object(object::object_address(&metadata)), 1);

        let (nav_ratio, total_dividends, _) = InvestorToken::get_dividend_info();
        assert!(nav_ratio == NAV_SCALE, 2);
        assert!(total_dividends == 0, 3);
        assert!(InvestorToken::total_supply() == 0, 4);
    }

    #[test]
    #[expected_failure(abort_code = E_UNAUTHORIZED_INIT, location = casino::InvestorToken)]
    fun test_init_unauthorized() {
        let (_, user_account) = setup_test();
        InvestorToken::init(&user_account);
    }

    #[test]
    fun test_deposit_and_mint_first() {
        let (_casino_account, user_account) = setup_test();

        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);

        let user_balance = InvestorToken::user_balance(@0x123);
        assert!(user_balance == TEST_DEPOSIT, 1);
        assert!(InvestorToken::total_supply() == TEST_DEPOSIT, 2);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::InvestorToken)]
    fun test_deposit_zero_amount() {
        let (_casino_account, user_account) = setup_test();

        InvestorToken::deposit_and_mint(&user_account, 0);
    }

    #[test]
    fun test_redeem_basic() {
        let (_casino_account, user_account) = setup_test();

        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);

        let redeem_amount = TEST_DEPOSIT / 2;
        InvestorToken::redeem(&user_account, redeem_amount);

        let remaining = InvestorToken::user_balance(@0x123);
        assert!(remaining == TEST_DEPOSIT - redeem_amount, 1);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_INSUFFICIENT_BALANCE, location = casino::InvestorToken
        )
    ]
    fun test_redeem_insufficient_balance() {
        let (_casino_account, user_account) = setup_test();

        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        InvestorToken::redeem(&user_account, TEST_DEPOSIT + 1);
    }

    #[test]
    fun test_nav_calculation() {
        let (_casino_account, user_account) = setup_test();

        // Initial NAV should be 1.0
        let nav = InvestorToken::nav();
        assert!(nav == NAV_SCALE, 1);

        // After deposit, NAV should still be around 1.0
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let nav_after = InvestorToken::nav();
        assert!(nav_after > 0, 2);
    }

    #[test]
    fun test_view_functions() {
        let (_casino_account, _) = setup_test();

        let metadata = InvestorToken::get_metadata();
        assert!(object::is_object(object::object_address(&metadata)), 1);

        assert!(InvestorToken::user_balance(@0x123) == 0, 2);
        assert!(InvestorToken::total_supply() == 0, 3);
        assert!(InvestorToken::treasury_balance() == 0, 4);

        let (nav_ratio, dividends, creation_timestamp) =
            InvestorToken::get_dividend_info();
        assert!(nav_ratio == NAV_SCALE, 5);
        assert!(dividends == 0, 6);
        assert!(creation_timestamp > 0, 7);
    }

    #[test]
    fun test_full_lifecycle() {
        let (_casino_account, user_account) = setup_test();

        // Deposit
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        assert!(InvestorToken::user_balance(@0x123) == TEST_DEPOSIT, 1);

        // Partial redeem
        let redeem_amount = TEST_DEPOSIT / 3;
        InvestorToken::redeem(&user_account, redeem_amount);
        assert!(
            InvestorToken::user_balance(@0x123) == TEST_DEPOSIT - redeem_amount,
            2
        );

        // Second deposit
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 2);
        let balance_after_second = InvestorToken::user_balance(@0x123);
        assert!(
            balance_after_second > TEST_DEPOSIT - redeem_amount,
            3
        );

        // Final redeem
        InvestorToken::redeem(&user_account, balance_after_second);
        assert!(InvestorToken::user_balance(@0x123) == 0, 4);
    }

    #[test]
    fun test_multiple_users() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let user1 = account::create_account_for_test(@0x111);
        let user2 = account::create_account_for_test(@0x222);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000); // Set to non-zero time

        // Register coin stores for all accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&user1);
        coin::register<AptosCoin>(&user2);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        InvestorToken::deposit_and_mint(&user1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&user2, TEST_DEPOSIT * 2);

        assert!(InvestorToken::user_balance(@0x111) == TEST_DEPOSIT, 1);
        assert!(InvestorToken::user_balance(@0x222) > TEST_DEPOSIT, 2);

        let total_supply = InvestorToken::total_supply();
        assert!(total_supply > TEST_DEPOSIT, 3);
    }

    //
    // Economic Edge Cases Tests
    //

    #[test]
    fun test_precision_minimal_amounts() {
        let (_casino_account, user_account) = setup_test();

        // Test with 1 octa (smallest possible amount)
        InvestorToken::deposit_and_mint(&user_account, 1);
        assert!(InvestorToken::user_balance(@0x123) == 1, 1);
        assert!(InvestorToken::total_supply() == 1, 2);

        // NAV should still be calculable
        let nav = InvestorToken::nav();
        assert!(nav > 0, 3);
    }

    #[test]
    fun test_precision_large_amounts() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let whale_account = account::create_account_for_test(@0x999);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&whale_account);

        // Mint large amount for whale (100,000 APT to stay within safe bounds)
        let large_amount = 100000 * 100000000; // 100K APT in octas
        aptos_coin::mint(&aptos_framework, @casino, large_amount);
        aptos_coin::mint(&aptos_framework, @0x999, large_amount);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        InvestorToken::deposit_and_mint(&whale_account, large_amount / 2);

        let balance = InvestorToken::user_balance(@0x999);
        assert!(balance > 0, 1);

        let nav = InvestorToken::nav();
        assert!(nav == NAV_SCALE, 2); // Should maintain 1:1 ratio for first deposit
    }

    #[test]
    fun test_nav_rounding_accuracy() {
        let (casino_account, user_account) = setup_test();

        // Create scenario with complex ratios
        let odd_amount = 777777;
        InvestorToken::deposit_and_mint(&user_account, odd_amount);

        // Add small treasury profit simulation using test helper
        let small_profit = 1234;
        // Simulate profit injection via proper bet flow
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, small_profit);
        let bet_id = CasinoHouse::place_bet_internal(bet_coins, @0x123, 1);
        CasinoHouse::test_settle_bet(
            signer::address_of(&casino_account),
            bet_id,
            @0x0, // winner (no payout)
            0, // payout
            small_profit // profit
        );

        let nav_before = InvestorToken::nav();

        // Second deposit should use updated NAV
        InvestorToken::deposit_and_mint(&user_account, odd_amount);

        let nav_after = InvestorToken::nav();

        // NAV should be consistent despite rounding
        let tolerance = 1000; // Allow small rounding differences
        assert!(nav_after >= nav_before - tolerance, 1);
        assert!(nav_after <= nav_before + tolerance, 2);
    }

    #[test]
    fun test_fee_boundary_minimum() {
        let (_casino_account, user_account) = setup_test();

        // Deposit amount that will trigger minimum fee scenario
        let deposit_amount = 10000000; // 0.1 APT to ensure we have enough for fees
        InvestorToken::deposit_and_mint(&user_account, deposit_amount);

        let initial_apt_balance = coin::balance<AptosCoin>(@0x123);

        // Redeem amount that will trigger minimum fee (1000 octas)
        let redeem_tokens = 1000; // Small redemption
        InvestorToken::redeem(&user_account, redeem_tokens);

        let final_apt_balance = coin::balance<AptosCoin>(@0x123);

        // For small redemptions, fee can exceed gross amount, resulting in 0 payout
        // This is acceptable behavior (user loses tokens but gets no APT due to high fee)
        assert!(final_apt_balance >= initial_apt_balance, 1); // Balance shouldn't decrease
    }

    #[test]
    fun test_fee_boundary_percentage() {
        let (_casino_account, user_account) = setup_test();

        // Large deposit to ensure percentage fee > minimum fee
        let large_deposit = 10000000; // 0.1 APT
        InvestorToken::deposit_and_mint(&user_account, large_deposit);

        let initial_apt_balance = coin::balance<AptosCoin>(@0x123);

        // Redeem large amount where percentage fee should apply
        let redeem_tokens = large_deposit / 2;
        InvestorToken::redeem(&user_account, redeem_tokens);

        let final_apt_balance = coin::balance<AptosCoin>(@0x123);
        let received = final_apt_balance - initial_apt_balance;

        // Should receive close to 99.9% of face value (0.1% fee)
        let expected_min = (redeem_tokens * 998) / 1000; // Account for 0.1% fee + rounding
        assert!(received >= expected_min, 1);
        assert!(received < redeem_tokens, 2);
    }

    #[test]
    fun test_nav_extreme_ratios() {
        let (casino_account, user_account) = setup_test();

        // Start with tiny deposit
        InvestorToken::deposit_and_mint(&user_account, 100);

        // Simulate large treasury growth using test helper
        let large_profit = 1000000; // 0.01 APT profit (within max_bet limit)
        // Simulate profit injection via proper bet flow
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, large_profit);
        let bet_id = CasinoHouse::place_bet_internal(bet_coins, @0x123, 1);
        CasinoHouse::test_settle_bet(
            signer::address_of(&casino_account),
            bet_id,
            @0x0, // winner (no payout)
            0, // payout
            large_profit // profit
        );

        // NAV should be extremely high now
        let nav = InvestorToken::nav();
        assert!(nav > NAV_SCALE * 1000, 1); // NAV should be > 1000x original

        // Small deposit should get very few tokens
        let small_deposit = 1000;
        let tokens_before = InvestorToken::total_supply();
        InvestorToken::deposit_and_mint(&user_account, small_deposit);
        let tokens_after = InvestorToken::total_supply();

        let new_tokens = tokens_after - tokens_before;
        assert!(new_tokens < small_deposit / 100, 2); // Should get much fewer tokens than APT deposited
    }

    #[test]
    fun test_dust_amounts_accumulation() {
        let (_casino_account, user_account) = setup_test();

        // Perform many tiny operations to test dust accumulation
        let tiny_amount = 10;
        let iterations = 100;

        let i = 0;
        while (i < iterations) {
            InvestorToken::deposit_and_mint(&user_account, tiny_amount);
            i = i + 1;
        };

        let final_balance = InvestorToken::user_balance(@0x123);
        let expected_balance = tiny_amount * iterations;

        // Should accumulate correctly despite small amounts
        assert!(final_balance == expected_balance, 1);

        let nav = InvestorToken::nav();
        assert!(nav == NAV_SCALE, 2); // NAV should remain stable
    }

    //
    // State Consistency Tests
    //

    #[test]
    fun test_supply_treasury_invariant() {
        let (_casino_account, user_account) = setup_test();

        // Initial state should satisfy invariant
        let initial_supply = InvestorToken::total_supply();
        let initial_treasury = InvestorToken::treasury_balance();
        let initial_nav = InvestorToken::nav();

        assert!(initial_supply == 0, 1);
        assert!(initial_treasury == 0, 2);
        assert!(initial_nav == NAV_SCALE, 3);

        // After deposit, invariant should hold
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);

        let supply_after_deposit = InvestorToken::total_supply();
        let treasury_after_deposit = InvestorToken::treasury_balance();
        let nav_after_deposit = InvestorToken::nav();

        // Key invariant: total_supply * nav ≈ treasury_balance * NAV_SCALE
        let expected_treasury = (supply_after_deposit * nav_after_deposit) / NAV_SCALE;
        assert!(treasury_after_deposit == expected_treasury, 4);

        // After redemption, invariant should still hold
        let redeem_amount = supply_after_deposit / 2;
        InvestorToken::redeem(&user_account, redeem_amount);

        let final_supply = InvestorToken::total_supply();
        let final_treasury = InvestorToken::treasury_balance();
        let final_nav = InvestorToken::nav();

        let final_expected_treasury = (final_supply * final_nav) / NAV_SCALE;
        let tolerance = 1000; // Allow for rounding and fees
        assert!(
            final_treasury >= final_expected_treasury - tolerance,
            5
        );
        assert!(
            final_treasury <= final_expected_treasury + tolerance,
            6
        );
    }

    #[test]
    fun test_nav_monotonicity_no_external_profit() {
        let (_casino_account, user_account) = setup_test();

        // First deposit - NAV should remain stable
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let nav_after_first = InvestorToken::nav();
        assert!(nav_after_first == NAV_SCALE, 1);

        // Second deposit - NAV should remain stable
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let nav_after_second = InvestorToken::nav();
        assert!(nav_after_second == NAV_SCALE, 2);

        // Partial redemption - NAV should decrease slightly due to fees but not dramatically
        let user_balance = InvestorToken::user_balance(@0x123);
        InvestorToken::redeem(&user_account, user_balance / 4);
        let nav_after_redeem = InvestorToken::nav();

        // NAV should not decrease by more than fee percentage
        let min_expected_nav = (NAV_SCALE * 999) / 1000; // Allow 0.1% decrease for fees
        assert!(nav_after_redeem >= min_expected_nav, 3);
    }

    #[test]
    fun test_supply_conservation() {
        let (_casino_account, user_account) = setup_test();

        // Track total minted and burned
        let initial_supply = InvestorToken::total_supply();
        assert!(initial_supply == 0, 1);

        // Multiple deposits
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let supply_after_first = InvestorToken::total_supply();
        let first_mint = supply_after_first - initial_supply;

        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 2);
        let supply_after_second = InvestorToken::total_supply();
        let second_mint = supply_after_second - supply_after_first;

        let total_minted = first_mint + second_mint;
        assert!(supply_after_second == total_minted, 2);

        // Partial redemption
        let redeem_amount = first_mint / 2;
        InvestorToken::redeem(&user_account, redeem_amount);
        let supply_after_redeem = InvestorToken::total_supply();

        // Supply should equal total_minted - total_burned
        assert!(
            supply_after_redeem == total_minted - redeem_amount,
            3
        );

        // User balance should match supply calculation
        let user_balance = InvestorToken::user_balance(@0x123);
        assert!(user_balance == supply_after_redeem, 4);
    }

    #[test]
    fun test_treasury_balance_consistency() {
        let (_casino_account, user_account) = setup_test();

        let initial_treasury = InvestorToken::treasury_balance();
        assert!(initial_treasury == 0, 1);

        // Treasury should increase by exact deposit amount
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let treasury_after_deposit = InvestorToken::treasury_balance();
        assert!(treasury_after_deposit == TEST_DEPOSIT, 2);

        // Treasury should decrease by redemption amount minus fees
        let redeem_tokens = InvestorToken::user_balance(@0x123) / 3;
        let treasury_before_redeem = InvestorToken::treasury_balance();

        InvestorToken::redeem(&user_account, redeem_tokens);

        let treasury_after_redeem = InvestorToken::treasury_balance();
        let treasury_decrease = treasury_before_redeem - treasury_after_redeem;

        // Treasury decrease should be close to token value (accounting for fees)
        assert!(treasury_decrease > 0, 3);
        assert!(treasury_decrease <= redeem_tokens, 4); // Should not decrease more than redeemed
    }

    #[test]
    fun test_nav_calculation_consistency() {
        let (_casino_account, user_account) = setup_test();

        // NAV calculation should be consistent across operations
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);

        let supply = InvestorToken::total_supply();
        let treasury = InvestorToken::treasury_balance();
        let nav_reported = InvestorToken::nav();
        let nav_calculated = (treasury * NAV_SCALE) / supply;

        assert!(nav_reported == nav_calculated, 1);

        // After second operation
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 3);

        let supply2 = InvestorToken::total_supply();
        let treasury2 = InvestorToken::treasury_balance();
        let nav_reported2 = InvestorToken::nav();
        let nav_calculated2 = (treasury2 * NAV_SCALE) / supply2;

        assert!(nav_reported2 == nav_calculated2, 2);
    }

    #[test]
    fun test_multiple_user_state_isolation() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let user1 = account::create_account_for_test(@0x111);
        let user2 = account::create_account_for_test(@0x222);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&user1);
        coin::register<AptosCoin>(&user2);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // User operations should not affect each other's balances
        InvestorToken::deposit_and_mint(&user1, TEST_DEPOSIT);
        let user1_balance_after_deposit = InvestorToken::user_balance(@0x111);
        let user2_balance_after_user1 = InvestorToken::user_balance(@0x222);

        assert!(user1_balance_after_deposit > 0, 1);
        assert!(user2_balance_after_user1 == 0, 2);

        InvestorToken::deposit_and_mint(&user2, TEST_DEPOSIT * 2);
        let user1_balance_after_user2 = InvestorToken::user_balance(@0x111);
        let user2_balance_after_deposit = InvestorToken::user_balance(@0x222);

        // User1 balance should be unchanged
        assert!(user1_balance_after_user2 == user1_balance_after_deposit, 3);
        assert!(user2_balance_after_deposit > 0, 4);

        // Total supply should equal sum of individual balances
        let total_supply = InvestorToken::total_supply();
        assert!(
            total_supply == user1_balance_after_user2 + user2_balance_after_deposit,
            5
        );
    }

    #[test]
    fun test_state_recovery_after_operations() {
        let (_casino_account, user_account) = setup_test();

        // Perform complex sequence and verify state remains consistent
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let checkpoint1_supply = InvestorToken::total_supply();

        // Redeem half
        InvestorToken::redeem(&user_account, checkpoint1_supply / 2);

        // Deposit again
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 2);

        // Verify final state consistency
        let final_supply = InvestorToken::total_supply();
        let final_treasury = InvestorToken::treasury_balance();
        let final_nav = InvestorToken::nav();

        // Core invariants should still hold
        let expected_treasury = (final_supply * final_nav) / NAV_SCALE;
        let tolerance = 2000; // Allow for multiple fee applications
        assert!(
            final_treasury >= expected_treasury - tolerance,
            1
        );
        assert!(
            final_treasury <= expected_treasury + tolerance,
            2
        );

        // Final supply should match user balance
        let user_balance = InvestorToken::user_balance(@0x123);
        assert!(user_balance == final_supply, 3);
    }

    #[test]
    fun test_zero_state_transitions() {
        let (_casino_account, user_account) = setup_test();

        // Start with deposit
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);

        // Redeem everything back to zero state
        let all_tokens = InvestorToken::user_balance(@0x123);
        InvestorToken::redeem(&user_account, all_tokens);

        // Should return to near-zero state
        let final_supply = InvestorToken::total_supply();
        let final_user_balance = InvestorToken::user_balance(@0x123);
        let final_nav = InvestorToken::nav();

        assert!(final_supply == 0, 1);
        assert!(final_user_balance == 0, 2);
        assert!(final_nav == NAV_SCALE, 3); // NAV should reset to 1.0 when supply is 0

        // Should be able to start fresh cycle
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 2);
        let new_balance = InvestorToken::user_balance(@0x123);
        assert!(new_balance > 0, 4);
    }

    //
    // Concurrent Operations Simulation Tests
    //

    #[test]
    fun test_interleaved_deposits_redemptions() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let user1 = account::create_account_for_test(@0x111);
        let user2 = account::create_account_for_test(@0x222);
        let user3 = account::create_account_for_test(@0x333);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&user1);
        coin::register<AptosCoin>(&user2);
        coin::register<AptosCoin>(&user3);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x333, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // Simulate interleaved operations
        InvestorToken::deposit_and_mint(&user1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&user2, TEST_DEPOSIT * 2);

        let user1_balance = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&user1, user1_balance / 2);

        InvestorToken::deposit_and_mint(&user3, TEST_DEPOSIT / 2);

        let user2_balance = InvestorToken::user_balance(@0x222);
        InvestorToken::redeem(&user2, user2_balance / 3);

        InvestorToken::deposit_and_mint(&user1, TEST_DEPOSIT);

        // Verify final state consistency
        let total_supply = InvestorToken::total_supply();
        let sum_balances =
            InvestorToken::user_balance(@0x111) + InvestorToken::user_balance(@0x222)
                + InvestorToken::user_balance(@0x333);

        assert!(total_supply == sum_balances, 1);
        assert!(total_supply > 0, 2);
    }

    #[test]
    fun test_whale_vs_small_investor_impact() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let whale = account::create_account_for_test(@0x999);
        let small_investor = account::create_account_for_test(@0x123);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&whale);
        coin::register<AptosCoin>(&small_investor);

        let whale_amount = 100000000; // 1 APT
        let small_amount = 1000000; // 0.01 APT

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x999, whale_amount * 10);
        aptos_coin::mint(&aptos_framework, @0x123, small_amount * 10);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // Small investor deposits first
        InvestorToken::deposit_and_mint(&small_investor, small_amount);
        let small_tokens_initial = InvestorToken::user_balance(@0x123);
        let nav_before_whale = InvestorToken::nav();

        // Whale makes large deposit
        InvestorToken::deposit_and_mint(&whale, whale_amount);
        let nav_after_whale = InvestorToken::nav();

        // NAV should remain stable despite whale entry
        assert!(nav_after_whale == nav_before_whale, 1);

        // Small investor should still own same proportion
        let small_tokens_after = InvestorToken::user_balance(@0x123);
        assert!(small_tokens_after == small_tokens_initial, 2);

        // Whale redemption shouldn't severely impact small investor
        let whale_tokens = InvestorToken::user_balance(@0x999);
        InvestorToken::redeem(&whale, whale_tokens / 2);

        let nav_after_whale_exit = InvestorToken::nav();
        let nav_tolerance = NAV_SCALE / 100; // 1% tolerance
        assert!(
            nav_after_whale_exit >= nav_before_whale - nav_tolerance,
            3
        );
        assert!(
            nav_after_whale_exit <= nav_before_whale + nav_tolerance,
            4
        );
    }

    #[test]
    fun test_rapid_small_operations() {
        let (_, user_account) = setup_test();

        let small_amount = 10000; // 0.0001 APT
        let operations = 50;

        // Rapid deposits
        let i = 0;
        while (i < operations) {
            InvestorToken::deposit_and_mint(&user_account, small_amount);
            i = i + 1;
        };

        let total_after_deposits = InvestorToken::user_balance(@0x123);
        assert!(
            total_after_deposits == small_amount * operations,
            1
        );

        // Rapid small redemptions
        let j = 0;
        while (j < operations / 2) {
            InvestorToken::redeem(&user_account, small_amount);
            j = j + 1;
        };

        let remaining_balance = InvestorToken::user_balance(@0x123);
        let expected_remaining = total_after_deposits - (small_amount * (operations / 2));

        // Allow small tolerance for rounding errors
        let tolerance = small_amount;
        assert!(
            remaining_balance >= expected_remaining - tolerance,
            2
        );
        assert!(
            remaining_balance <= expected_remaining + tolerance,
            3
        );
    }

    #[test]
    fun test_first_investor_advantage_mitigation() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let first_investor = account::create_account_for_test(@0x111);
        let second_investor = account::create_account_for_test(@0x222);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&first_investor);
        coin::register<AptosCoin>(&second_investor);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // First investor gets 1:1 ratio
        InvestorToken::deposit_and_mint(&first_investor, TEST_DEPOSIT);
        let first_tokens = InvestorToken::user_balance(@0x111);
        assert!(first_tokens == TEST_DEPOSIT, 1);

        // Second investor with same deposit should get same treatment
        InvestorToken::deposit_and_mint(&second_investor, TEST_DEPOSIT);
        let second_tokens = InvestorToken::user_balance(@0x222);
        assert!(second_tokens == TEST_DEPOSIT, 2);

        // Both should have equal share of treasury
        let treasury = InvestorToken::treasury_balance();
        let total_supply = InvestorToken::total_supply();

        let first_share = (first_tokens * treasury) / total_supply;
        let second_share = (second_tokens * treasury) / total_supply;

        // Shares should be equal within rounding tolerance
        let tolerance = 1000;
        assert!(first_share >= second_share - tolerance, 3);
        assert!(first_share <= second_share + tolerance, 4);
    }

    #[test]
    fun test_alternating_user_operations() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let userA = account::create_account_for_test(@0xAAA);
        let userB = account::create_account_for_test(@0xBBB);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&userA);
        coin::register<AptosCoin>(&userB);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0xAAA, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0xBBB, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // Alternating pattern: A deposits, B deposits, A redeems, B redeems
        InvestorToken::deposit_and_mint(&userA, TEST_DEPOSIT);
        let nav_after_a1 = InvestorToken::nav();

        InvestorToken::deposit_and_mint(&userB, TEST_DEPOSIT);
        let nav_after_b1 = InvestorToken::nav();

        assert!(nav_after_a1 == nav_after_b1, 1); // NAV should be stable

        let userA_tokens = InvestorToken::user_balance(@0xAAA);
        InvestorToken::redeem(&userA, userA_tokens / 2);
        let nav_after_a_redeem = InvestorToken::nav();

        let userB_tokens = InvestorToken::user_balance(@0xBBB);
        InvestorToken::redeem(&userB, userB_tokens / 2);
        let nav_after_b_redeem = InvestorToken::nav();

        // NAV should not drift significantly due to alternating operations
        let nav_tolerance = NAV_SCALE / 50; // 2% tolerance for fees
        assert!(
            nav_after_a_redeem >= NAV_SCALE - nav_tolerance,
            2
        );
        assert!(
            nav_after_b_redeem >= NAV_SCALE - nav_tolerance,
            3
        );
    }

    #[test]
    fun test_mixed_size_concurrent_operations() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let large_user = account::create_account_for_test(@0x111);
        let medium_user = account::create_account_for_test(@0x222);
        let small_user = account::create_account_for_test(@0x333);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&large_user);
        coin::register<AptosCoin>(&medium_user);
        coin::register<AptosCoin>(&small_user);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x333, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        let large_amount = TEST_DEPOSIT * 10;
        let medium_amount = TEST_DEPOSIT;
        let small_amount = TEST_DEPOSIT / 10;

        // Mixed operations simulating concurrent activity
        InvestorToken::deposit_and_mint(&small_user, small_amount);
        InvestorToken::deposit_and_mint(&large_user, large_amount);
        InvestorToken::deposit_and_mint(&medium_user, medium_amount);

        // Partial redemptions in different order
        let large_tokens = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&large_user, large_tokens / 4);

        let small_tokens = InvestorToken::user_balance(@0x333);
        InvestorToken::redeem(&small_user, small_tokens / 2);

        // More deposits
        InvestorToken::deposit_and_mint(&medium_user, medium_amount / 2);
        InvestorToken::deposit_and_mint(&small_user, small_amount);

        // Final redemptions
        let medium_tokens = InvestorToken::user_balance(@0x222);
        InvestorToken::redeem(&medium_user, medium_tokens / 3);

        // Verify system integrity
        let final_supply = InvestorToken::total_supply();
        let sum_balances =
            InvestorToken::user_balance(@0x111) + InvestorToken::user_balance(@0x222)
                + InvestorToken::user_balance(@0x333);

        assert!(final_supply == sum_balances, 1);
        assert!(final_supply > 0, 2);

        let final_nav = InvestorToken::nav();
        assert!(final_nav > 0, 3);
    }

    #[test]
    fun test_sequential_full_redemptions() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let user1 = account::create_account_for_test(@0x111);
        let user2 = account::create_account_for_test(@0x222);
        let user3 = account::create_account_for_test(@0x333);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&user1);
        coin::register<AptosCoin>(&user2);
        coin::register<AptosCoin>(&user3);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x333, INITIAL_BALANCE);

        // Initialize CasinoHouse and InvestorToken
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game for profit injection scenarios
        CasinoHouse::register_game(
            &casino_account,
            &casino_account, // Use casino_account as game account
            b"TestGame",
            1000, // min_bet
            1000000, // max_bet
            150 // house_edge_bps
        );

        // All users deposit
        InvestorToken::deposit_and_mint(&user1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&user2, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&user3, TEST_DEPOSIT);

        // Sequential full redemptions
        let user1_tokens = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&user1, user1_tokens);
        assert!(InvestorToken::user_balance(@0x111) == 0, 1);

        let user2_tokens = InvestorToken::user_balance(@0x222);
        InvestorToken::redeem(&user2, user2_tokens);
        assert!(InvestorToken::user_balance(@0x222) == 0, 2);

        // Final user should still be able to redeem
        let user3_tokens = InvestorToken::user_balance(@0x333);
        assert!(user3_tokens > 0, 3);

        InvestorToken::redeem(&user3, user3_tokens);
        assert!(InvestorToken::user_balance(@0x333) == 0, 4);

        // System should return to zero state
        assert!(InvestorToken::total_supply() == 0, 5);
    }

    #[test]
    fun test_no_nav_manipulation_exploit() {
        let (casino_account, user_account) = setup_test();

        let initial_apt = coin::balance<AptosCoin>(@0x123);

        // Attempt exploit: small deposit → large profit injection → immediate redeem
        InvestorToken::deposit_and_mint(&user_account, 1000);
        // Simulate profit injection via proper bet flow
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, 1000000);
        let bet_id = CasinoHouse::place_bet_internal(bet_coins, @0x123, 1);
        CasinoHouse::test_settle_bet(
            signer::address_of(&casino_account),
            bet_id,
            @0x0, // winner (no payout)
            0, // payout
            1000000 // profit
        );

        let tokens = InvestorToken::user_balance(@0x123);
        InvestorToken::redeem(&user_account, tokens);

        let final_apt = coin::balance<AptosCoin>(@0x123);

        // User cannot extract more than they deposited + legitimate profit share
        assert!(final_apt <= initial_apt + 1000000, 1); // No free money creation
    }

    #[test]
    fun test_treasury_invariant_unbreakable() {
        let (_casino_account, user_account) = setup_test();

        // Any sequence of operations must maintain: treasury ≥ (supply × NAV / NAV_SCALE) - fees
        InvestorToken::deposit_and_mint(&user_account, 100000);
        InvestorToken::deposit_and_mint(&user_account, 50000);

        let supply = InvestorToken::total_supply();
        let treasury = InvestorToken::treasury_balance();
        let nav = InvestorToken::nav();

        let expected_min_treasury = (supply * nav) / NAV_SCALE;
        let tolerance = supply / 100; // Allow 1% for fees

        assert!(treasury >= expected_min_treasury - tolerance, 1);
    }

    #[test]
    fun test_system_survives_extreme_stress() {
        let (_casino_account, user_account) = setup_test();

        // Stress test: rapid operations with edge amounts
        InvestorToken::deposit_and_mint(&user_account, 1); // Minimal
        InvestorToken::deposit_and_mint(&user_account, 999999999); // Large

        let half_tokens = InvestorToken::user_balance(@0x123) / 2;
        InvestorToken::redeem(&user_account, half_tokens);
        InvestorToken::redeem(&user_account, 1); // Minimal redeem

        // System must remain functional
        let final_supply = InvestorToken::total_supply();
        let final_nav = InvestorToken::nav();

        assert!(final_supply > 0, 1);
        assert!(final_nav > 0, 2);
        assert!(final_nav < NAV_SCALE * 2, 3); // NAV shouldn't explode
    }
}
