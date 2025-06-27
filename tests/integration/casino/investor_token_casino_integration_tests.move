//! Integration tests between CasinoHouse and InvestorToken modules
//!
//! Tests cross-module interactions, treasury synchronization, and profit flow.

#[test_only]
module casino::IntegrationTest {
    use std::string;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;
    use casino::InvestorToken;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const TEST_DEPOSIT: u64 = 100000000; // 1 APT
    const GAME_BET: u64 = 10000000; // 0.1 APT
    const NAV_SCALE: u64 = 1000000;

    // Error constants
    const E_INSUFFICIENT_TREASURY_CASINO: u64 = 0x06;
    const E_INSUFFICIENT_TREASURY_TOKEN: u64 = 0x73;

    fun setup_integration_test(): (signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let investor1 = account::create_account_for_test(@0x111);
        let investor2 = account::create_account_for_test(@0x222);

        // Initialize test environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        // Register coin stores
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&investor1);
        coin::register<AptosCoin>(&investor2);

        // Mint initial balances
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        // Initialize both modules
        CasinoHouse::init(&casino_account);
        InvestorToken::init(&casino_account);

        // Register test game
        CasinoHouse::register_game(
            &casino_account,
            &casino_account,
            string::utf8(b"TestGame"),
            100,
            100000000, // max_bet: 1 APT
            150 // house_edge: 1.5%
        );

        (aptos_framework, casino_account, investor1, investor2)
    }

    //
    // Treasury Synchronization Tests
    //

    #[test]
    fun test_treasury_sync_deposit() {
        let (_, _, investor1, _) = setup_integration_test();

        // Initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(InvestorToken::treasury_balance() == 0, 2);

        // Investor deposit should increase both treasury views
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);

        assert!(CasinoHouse::treasury_balance() == TEST_DEPOSIT, 3);
        assert!(InvestorToken::treasury_balance() == TEST_DEPOSIT, 4);
        assert!(InvestorToken::user_balance(@0x111) == TEST_DEPOSIT, 5);
    }

    #[test]
    fun test_treasury_sync_redemption() {
        let (_, _, investor1, _) = setup_integration_test();

        // Setup: deposit first
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        let initial_treasury = CasinoHouse::treasury_balance();

        // Redeem half tokens
        let redeem_tokens = TEST_DEPOSIT / 2;
        InvestorToken::redeem(&investor1, redeem_tokens);

        let final_treasury = CasinoHouse::treasury_balance();

        // Treasury should decrease (accounting for fees)
        assert!(final_treasury < initial_treasury, 1);
        assert!(final_treasury > 0, 2);

        // Both views should remain synchronized
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 3);
    }

    #[test]
    fun test_treasury_sync_multiple_investors() {
        let (_, _, investor1, investor2) = setup_integration_test();

        // Multiple deposits
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor2, TEST_DEPOSIT * 2);

        let expected_treasury = TEST_DEPOSIT + (TEST_DEPOSIT * 2);
        assert!(CasinoHouse::treasury_balance() == expected_treasury, 1);
        assert!(InvestorToken::treasury_balance() == expected_treasury, 2);

        // Partial redemptions
        InvestorToken::redeem(&investor1, TEST_DEPOSIT / 2);
        InvestorToken::redeem(&investor2, TEST_DEPOSIT);

        // Verify synchronization after mixed operations
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 3);
        assert!(CasinoHouse::treasury_balance() > 0, 4);
    }

    //
    // NAV Impact from Game Profits Tests
    //

    #[test]
    fun test_nav_increase_from_game_profit() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        // Setup: investor deposits
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        let initial_nav = InvestorToken::nav();

        // Simulate game profit via bet settlement
        let profit_amount = GAME_BET;
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, profit_amount);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);

        // Settle with house profit (no winner payout)
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, profit_amount);

        let nav_after_profit = InvestorToken::nav();
        assert!(nav_after_profit > initial_nav, 1);
        assert!(
            InvestorToken::treasury_balance() == TEST_DEPOSIT + profit_amount,
            2
        );
    }

    #[test]
    fun test_nav_proportional_distribution() {
        let (_, casino_account, investor1, investor2) = setup_integration_test();

        // Two investors with different investments
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor2, TEST_DEPOSIT * 3);

        let investor1_tokens = InvestorToken::user_balance(@0x111);
        let investor2_tokens = InvestorToken::user_balance(@0x222);
        let initial_nav = InvestorToken::nav();

        // Generate profit
        let profit_amount = GAME_BET * 2;
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, profit_amount);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, profit_amount);

        let nav_after = InvestorToken::nav();
        assert!(nav_after > initial_nav, 1);

        // Both investors should benefit proportionally
        let investor1_value = (investor1_tokens * nav_after) / NAV_SCALE;
        let investor2_value = (investor2_tokens * nav_after) / NAV_SCALE;

        assert!(investor2_value > investor1_value * 2, 2); // investor2 has 3x more
        assert!(investor1_value > TEST_DEPOSIT, 3); // Both gained value
        assert!(investor2_value > TEST_DEPOSIT * 3, 4);
    }

    #[test]
    fun test_multiple_game_rounds_nav_accumulation() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        let previous_nav = InvestorToken::nav();

        // Multiple game rounds with profits
        let i = 0;
        while (i < 3) {
            let bet_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
            let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
            CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, GAME_BET);

            let current_nav = InvestorToken::nav();
            assert!(current_nav > previous_nav, i + 10);
            i = i + 1;
        };

        // Final NAV should be significantly higher
        let final_nav = InvestorToken::nav();
        assert!(final_nav > NAV_SCALE * 103 / 100, 20); // At least 3% increase
    }

    //
    // Insufficient Treasury Scenarios
    //

    #[test]
    #[
        expected_failure(
            abort_code = E_INSUFFICIENT_TREASURY_CASINO, location = casino::CasinoHouse
        )
    ]
    fun test_game_payout_exceeds_treasury() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        // Small treasury from investor
        InvestorToken::deposit_and_mint(&investor1, GAME_BET);

        // Attempt large payout
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);

        // Try to payout more than treasury has
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x111, GAME_BET * 2 + 1, 0);
    }

    #[test]
    fun test_treasury_boundary_conditions() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);

        // Payout exactly treasury amount minus small buffer
        let available = CasinoHouse::treasury_balance();
        let payout_amount = available - 1000; // Leave 1000 octas

        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, 1000);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x111, payout_amount, 1000);

        assert!(CasinoHouse::treasury_balance() == 2000, 1);
    }

    //
    // Concurrent Operations Tests
    //

    #[test]
    fun test_concurrent_redemption_and_game_settlement() {
        let (_, casino_account, investor1, investor2) = setup_integration_test();

        // Setup multiple investors
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor2, TEST_DEPOSIT);

        // Start game
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);

        // Investor1 redeems while game active
        let redemption_amount = InvestorToken::user_balance(@0x111) / 2;
        InvestorToken::redeem(&investor1, redemption_amount);

        // Settle game with profit
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, GAME_BET);

        // Verify state consistency
        assert!(InvestorToken::treasury_balance() == CasinoHouse::treasury_balance(), 1);
        assert!(InvestorToken::nav() > NAV_SCALE, 2); // Should reflect profit
    }

    #[test]
    fun test_multiple_investor_operations_with_games() {
        let (_, casino_account, investor1, investor2) = setup_integration_test();

        // Interleaved operations
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);

        // Game 1
        let bet_coins1 = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
        let bet_id1 = CasinoHouse::place_bet(@casino, bet_coins1, @0x111);

        InvestorToken::deposit_and_mint(&investor2, TEST_DEPOSIT * 2);

        // Settle game 1
        CasinoHouse::test_settle_bet(@casino, bet_id1, @0x0, 0, GAME_BET);

        // Partial redemption
        InvestorToken::redeem(&investor1, InvestorToken::user_balance(@0x111) / 3);

        // Game 2
        let bet_coins2 = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
        let bet_id2 = CasinoHouse::place_bet(@casino, bet_coins2, @0x222);
        CasinoHouse::test_settle_bet(
            @casino,
            bet_id2,
            @0x222,
            GAME_BET / 2,
            GAME_BET / 2
        );

        // Final consistency checks
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 1);
        assert!(InvestorToken::total_supply() > 0, 2);
        assert!(InvestorToken::nav() > NAV_SCALE, 3);
    }

    //
    // End-to-End Profit Flow Tests
    //

    #[test]
    fun test_complete_profit_cycle() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        let initial_investor_apt = coin::balance<AptosCoin>(@0x111);

        // 1. Investor deposits
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        assert!(InvestorToken::user_balance(@0x111) == TEST_DEPOSIT, 1);

        // 2. Games generate profits
        let total_profit = 0u64;
        let i = 0;
        while (i < 5) {
            let bet_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
            let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
            let round_profit = GAME_BET / 2;
            CasinoHouse::test_settle_bet(
                @casino,
                bet_id,
                @0x111,
                GAME_BET - round_profit,
                round_profit
            );
            total_profit = total_profit + round_profit;
            i = i + 1;
        };

        // 3. Verify NAV increased
        let nav_after_profits = InvestorToken::nav();
        assert!(nav_after_profits > NAV_SCALE, 2);

        // 4. Investor redeems at profit
        let tokens_to_redeem = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&investor1, tokens_to_redeem);

        // 5. Verify profit realization
        let final_investor_apt = coin::balance<AptosCoin>(@0x111);
        let net_gain = final_investor_apt - initial_investor_apt;

        // Should have gained from profits (accounting for fees)
        assert!(net_gain > 0, 3);
        assert!(InvestorToken::user_balance(@0x111) == 0, 4);
    }

    #[test]
    fun test_investor_profit_vs_house_profit_distribution() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        // Track initial states
        let initial_investor_apt = coin::balance<AptosCoin>(@0x111);

        // Investor deposits
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);

        // Generate known profit amount
        let house_profit = GAME_BET;
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_BET);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, house_profit);

        // Calculate expected NAV increase
        let treasury_after = InvestorToken::treasury_balance();
        let expected_treasury = TEST_DEPOSIT + house_profit;
        assert!(treasury_after == expected_treasury, 1);

        // Redeem and verify proportional profit
        let tokens_owned = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&investor1, tokens_owned);

        let final_apt = coin::balance<AptosCoin>(@0x111);
        let net_change = final_apt - initial_investor_apt;

        // Net change should be positive (gained from house profit)
        assert!(net_change > 0, 2);
    }

    //
    // Edge Cases and Error Propagation
    //

    #[test]
    fun test_zero_treasury_edge_cases() {
        let (_, _, investor1, _) = setup_integration_test();

        // Start with empty treasury
        assert!(CasinoHouse::treasury_balance() == 0, 1);

        // Deposit should work
        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        assert!(CasinoHouse::treasury_balance() == TEST_DEPOSIT, 2);

        // Complete redemption should work
        let all_tokens = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&investor1, all_tokens);

        // Treasury should be near zero (minus fees)
        let remaining = CasinoHouse::treasury_balance();
        assert!(remaining < TEST_DEPOSIT / 100, 3); // Less than 1% remaining
    }

    #[test]
    fun test_precision_with_small_amounts() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        // Test with very small amounts
        let tiny_amount = 1000; // 0.00001 APT
        InvestorToken::deposit_and_mint(&investor1, tiny_amount);

        // Small profit
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, 100);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x0, 0, 100);

        let nav_after = InvestorToken::nav();
        assert!(nav_after > NAV_SCALE, 1);

        // Should be able to redeem
        let tokens = InvestorToken::user_balance(@0x111);
        InvestorToken::redeem(&investor1, tokens);
    }

    #[test]
    fun test_state_consistency_after_failures() {
        let (_, casino_account, investor1, _) = setup_integration_test();

        InvestorToken::deposit_and_mint(&investor1, TEST_DEPOSIT);
        let treasury_before = CasinoHouse::treasury_balance();

        // Net-positive operation (500 profit to house)
        let bet_coins = coin::withdraw<AptosCoin>(&casino_account, 1000);
        let bet_id = CasinoHouse::place_bet(@casino, bet_coins, @0x111);
        CasinoHouse::test_settle_bet(@casino, bet_id, @0x111, 500, 500);

        // State should remain consistent with profit retention
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 1);
        assert!(
            CasinoHouse::treasury_balance() == treasury_before + 500,
            2
        ); // Profit retained
    }
}
