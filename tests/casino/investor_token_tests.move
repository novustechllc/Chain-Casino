//! Test suite for InvestorToken standalone testing

#[test_only]
module casino::InvestorTokenTest {
    use std::string;
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
            string::utf8(b"TestGame"),
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
            string::utf8(b"TestGame"),
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

    #[test]
    fun test_nav_with_profit_injection() {
        let (casino_account, user_account) = setup_test();

        // Deposit initial tokens
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let initial_nav = InvestorToken::nav();

        // Simulate profit via bet flow using updated function names
        let profit_amount = 500000; // 0.005 APT
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, profit_amount);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x123);

        // Settle with house profit (no payout to winner)
        CasinoHouse::test_settle_bet(
            @casino,
            bet_id,
            @0x0, // winner (no payout)
            0, // payout
            profit_amount // profit to house
        );

        let nav_after_profit = InvestorToken::nav();
        assert!(nav_after_profit > initial_nav, 1);
    }

    #[test]
    fun test_precision_edge_cases() {
        let (_casino_account, user_account) = setup_test();

        // Test with minimal amounts
        InvestorToken::deposit_and_mint(&user_account, 1);
        assert!(InvestorToken::user_balance(@0x123) == 1, 1);

        let nav = InvestorToken::nav();
        assert!(nav > 0, 2);
    }

    #[test]
    fun test_treasury_integration() {
        let (_casino_account, user_account) = setup_test();

        // Treasury should start empty
        assert!(InvestorToken::treasury_balance() == 0, 1);

        // After deposit, treasury should increase
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        assert!(InvestorToken::treasury_balance() == TEST_DEPOSIT, 2);

        // After redemption, treasury should decrease
        let redeem_amount = TEST_DEPOSIT / 2;
        InvestorToken::redeem(&user_account, redeem_amount);

        let final_treasury = InvestorToken::treasury_balance();
        assert!(final_treasury < TEST_DEPOSIT, 3);
        assert!(final_treasury > 0, 4); // Should still have some funds due to fees
    }

    #[test]
    fun test_fee_calculation_edge_cases() {
        let (_casino_account, user_account) = setup_test();

        // Large deposit to ensure percentage fee calculation
        let large_deposit = 10000000; // 0.1 APT
        InvestorToken::deposit_and_mint(&user_account, large_deposit);

        let initial_apt = coin::balance<AptosCoin>(@0x123);

        // Redeem substantial amount
        let redeem_tokens = large_deposit / 2;
        InvestorToken::redeem(&user_account, redeem_tokens);

        let final_apt = coin::balance<AptosCoin>(@0x123);
        let received = final_apt - initial_apt;

        // Should receive less than face value due to fees
        assert!(received < redeem_tokens, 1);
        assert!(received > 0, 2);
    }

    #[test]
    fun test_state_consistency() {
        let (_casino_account, user_account) = setup_test();

        // Multiple operations to test state consistency
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT);
        let checkpoint1_supply = InvestorToken::total_supply();

        InvestorToken::redeem(&user_account, checkpoint1_supply / 3);
        InvestorToken::deposit_and_mint(&user_account, TEST_DEPOSIT / 2);

        let final_supply = InvestorToken::total_supply();
        let final_treasury = InvestorToken::treasury_balance();
        let final_nav = InvestorToken::nav();

        // Basic invariants
        assert!(final_supply > 0, 1);
        assert!(final_treasury > 0, 2);
        assert!(final_nav > 0, 3);

        // User balance should match their share of total supply
        let user_balance = InvestorToken::user_balance(@0x123);
        assert!(user_balance == final_supply, 4);
    }
}
