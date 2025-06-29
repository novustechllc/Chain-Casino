//! MIT License
//!
//! Critical integration tests for ChainCasino platform

#[test_only]
module casino::CriticalIntegrationTest {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;
    use dice_game::DiceGame;

    // Test constants
    const LARGE_DEPOSIT: u64 = 1000000000; // 10 APT
    const MASSIVE_BET: u64 = 50000000; // 0.5 APT (matches MAX_BET)
    const SMALL_RESERVE: u64 = 25000000; // 0.25 APT

    // Test addresses (all valid hex)
    const INVESTOR_ADDR: address = @0x1000;
    const WHALE_ADDR: address = @0x2000;
    const BLACKJACK_ADDR: address = @0xB1AC;
    const TEMP_GAME_ADDR: address = @0x7E5F;
    const MICRO_INVESTOR_ADDR: address = @0x9000;
    const TEST_GAME_ADDR: address = @0x7E57;
    const PLAYER_BASE: address = @0x3000;

    // Test capability wrapper
    struct TestGameAuth has key {
        capability: GameCapability
    }

    fun setup_critical_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let dice_account = account::create_account_for_test(@dice_game);

        // Initialize environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Register and fund accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&dice_account);
        aptos_coin::mint(&aptos_framework, @casino, LARGE_DEPOSIT * 50);

        // Initialize all modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        // Register and initialize DiceGame
        CasinoHouse::register_game(
            &casino_account,
            @dice_game,
            string::utf8(b"Dice Game"),
            1000000, // 0.01 APT min
            500000000, // 5 APT max
            1667 // 16.67% house edge
        );
        DiceGame::initialize_game(&dice_account);

        (aptos_framework, casino_account, dice_account)
    }

    fun create_funded_player(
        framework: &signer, addr: address, balance: u64
    ): signer {
        let player = account::create_account_for_test(addr);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(framework, addr, balance);
        player
    }

    #[test]
    fun test_treasury_depletion_scenario() {
        let (framework, _casino_account, _dice_account) = setup_critical_test();

        // Setup: Large investor position but small treasury reserve
        let investor = create_funded_player(&framework, INVESTOR_ADDR, LARGE_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor, LARGE_DEPOSIT);

        let treasury_after_investment = CasinoHouse::treasury_balance();
        assert!(treasury_after_investment == LARGE_DEPOSIT, 1);

        // Create high-stakes player who could drain treasury
        let whale = create_funded_player(&framework, WHALE_ADDR, MASSIVE_BET * 3);

        // Multiple large bets that could win big
        DiceGame::test_only_play_dice(&whale, 1, MASSIVE_BET); // 5x payout = 10 APT if wins
        DiceGame::test_only_play_dice(&whale, 2, MASSIVE_BET); // Another 10 APT if wins

        let treasury_after_bets = CasinoHouse::treasury_balance();

        // Treasury should have more funds (from bets) regardless of outcomes
        assert!(treasury_after_bets >= treasury_after_investment, 2);

        // Critical test: Can investor still redeem after potential large payouts?
        let redemption_amount = LARGE_DEPOSIT / 4; // Try to redeem 25%
        InvestorToken::redeem(&investor, redemption_amount);

        // Verify system remains stable
        let final_treasury = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();
        assert!(final_treasury > 0, 3);
        assert!(final_nav > 0, 4);
    }

    #[test]
    fun test_multiple_games_treasury_isolation() acquires TestGameAuth {
        let (framework, casino_account, _dice_account) = setup_critical_test();

        // Register second game at different address
        let blackjack_account = account::create_account_for_test(BLACKJACK_ADDR);
        CasinoHouse::register_game(
            &casino_account,
            BLACKJACK_ADDR,
            string::utf8(b"Blackjack"),
            5000000, // 0.05 APT min
            1000000000, // 10 APT max
            200 // 2% house edge
        );
        let bj_capability = CasinoHouse::get_game_capability(&blackjack_account);
        move_to(&blackjack_account, TestGameAuth { capability: bj_capability });

        // Setup investor
        let investor = create_funded_player(&framework, INVESTOR_ADDR, LARGE_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor, LARGE_DEPOSIT);

        // Fund treasury for potential payouts
        let casino_funds = coin::withdraw<AptosCoin>(&casino_account, LARGE_DEPOSIT);
        CasinoHouse::deposit_to_treasury(casino_funds);

        let initial_treasury = CasinoHouse::treasury_balance();

        // Activity on both games
        let dice_player = create_funded_player(&framework, WHALE_ADDR, MASSIVE_BET);
        let bj_player = create_funded_player(&framework, PLAYER_BASE, MASSIVE_BET);

        DiceGame::test_only_play_dice(&dice_player, 3, MASSIVE_BET);

        // Simulate blackjack bet via CasinoHouse directly
        let bj_bet_coins = coin::withdraw<AptosCoin>(&bj_player, MASSIVE_BET);
        let bj_auth = borrow_global<TestGameAuth>(BLACKJACK_ADDR);
        let bet_id =
            CasinoHouse::place_bet(
                &bj_auth.capability,
                bj_bet_coins,
                PLAYER_BASE,
                MASSIVE_BET * 2
            );
        // Simulate blackjack loss (house wins)
        CasinoHouse::settle_bet(&bj_auth.capability, bet_id, PLAYER_BASE, 0);

        // Verify treasury reflects activity from both games
        let final_treasury = CasinoHouse::treasury_balance();
        assert!(final_treasury >= initial_treasury, 1);

        // Verify NAV reflects combined profits
        let final_nav = InvestorToken::nav();
        assert!(final_nav > 0, 2);

        // Both games should still be functional
        assert!(CasinoHouse::is_game_registered(@dice_game), 3);
        assert!(CasinoHouse::is_game_registered(BLACKJACK_ADDR), 4);
    }

    #[test]
    fun test_concurrent_investor_operations() {
        let (framework, casino_account, _dice_account) = setup_critical_test();

        // Multiple investors with different timing
        let investor1 = create_funded_player(&framework, @0x1001, LARGE_DEPOSIT);
        let investor2 = create_funded_player(&framework, @0x1002, LARGE_DEPOSIT);
        let investor3 = create_funded_player(&framework, @0x1003, LARGE_DEPOSIT);

        // Staggered investments
        InvestorToken::deposit_and_mint(&investor1, LARGE_DEPOSIT);
        let nav_after_1 = InvestorToken::nav();

        // Add some profit
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, SMALL_RESERVE);
        CasinoHouse::deposit_to_treasury(profit_coins);

        InvestorToken::deposit_and_mint(&investor2, LARGE_DEPOSIT);
        let nav_after_2 = InvestorToken::nav();

        // More profit
        let profit_coins2 = coin::withdraw<AptosCoin>(&casino_account, SMALL_RESERVE);
        CasinoHouse::deposit_to_treasury(profit_coins2);

        InvestorToken::deposit_and_mint(&investor3, LARGE_DEPOSIT);
        let nav_after_3 = InvestorToken::nav();

        // Concurrent redemptions
        let redeem_amount = LARGE_DEPOSIT / 3;

        let inv1_apt_before = coin::balance<AptosCoin>(@0x1001);
        let inv2_apt_before = coin::balance<AptosCoin>(@0x1002);

        InvestorToken::redeem(&investor1, redeem_amount);
        InvestorToken::redeem(&investor2, redeem_amount);

        let inv1_apt_after = coin::balance<AptosCoin>(@0x1001);
        let inv2_apt_after = coin::balance<AptosCoin>(@0x1002);

        // Both should receive payouts
        assert!(inv1_apt_after > inv1_apt_before, 1);
        assert!(inv2_apt_after > inv2_apt_before, 2);

        // System should remain consistent
        let final_treasury = CasinoHouse::treasury_balance();
        let final_supply = InvestorToken::total_supply();
        let final_nav = InvestorToken::nav();

        assert!(final_treasury > 0, 3);
        assert!(final_supply > 0, 4);
        assert!(final_nav > 0, 5);

        // NAV should reflect profit accumulation
        assert!(final_nav >= nav_after_1, 6);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED)]
    fun test_unregistered_game_settlement_fails() acquires TestGameAuth {
        let (framework, casino_account, _dice_account) = setup_critical_test();

        // Register and get capability
        let temp_game = account::create_account_for_test(TEMP_GAME_ADDR);
        CasinoHouse::register_game(
            &casino_account,
            TEMP_GAME_ADDR,
            string::utf8(b"Temp Game"),
            1000000,
            100000000,
            100
        );
        let capability = CasinoHouse::get_game_capability(&temp_game);
        move_to(&temp_game, TestGameAuth { capability });

        // Fund treasury and place bet
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, SMALL_RESERVE);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_funded_player(&framework, @0x9999, SMALL_RESERVE);
        let bet_coins = coin::withdraw<AptosCoin>(&player, 10000000);

        let auth = borrow_global<TestGameAuth>(TEMP_GAME_ADDR);
        let bet_id = CasinoHouse::place_bet(
            &auth.capability, bet_coins, @0x9999, 20000000
        );

        // Unregister the game
        CasinoHouse::unregister_game(&casino_account, TEMP_GAME_ADDR);

        // Try to settle bet - should fail
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x9999, 10000000);
    }

    #[test]
    fun test_minimum_fee_edge_cases() {
        let (framework, _casino_account, _dice_account) = setup_critical_test();

        // Test with tiny amounts
        let micro_investor = create_funded_player(&framework, MICRO_INVESTOR_ADDR, 10000); // 0.00001 APT
        InvestorToken::deposit_and_mint(&micro_investor, 1000); // Tiny deposit

        let balance_before = coin::balance<AptosCoin>(MICRO_INVESTOR_ADDR);
        let user_tokens = InvestorToken::user_balance(MICRO_INVESTOR_ADDR);

        // Try to redeem tiny amount
        InvestorToken::redeem(&micro_investor, user_tokens);

        let balance_after = coin::balance<AptosCoin>(MICRO_INVESTOR_ADDR);

        // Should handle minimum fees correctly
        // Note: might receive 0 due to fees exceeding redemption value
        assert!(balance_after >= balance_before, 1);
    }

    #[test]
    fun test_massive_profit_nav_calculation() {
        let (framework, casino_account, _dice_account) = setup_critical_test();

        // Small investor position
        let investor = create_funded_player(&framework, INVESTOR_ADDR, LARGE_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor, LARGE_DEPOSIT / 10); // 1 APT

        // Massive house profit injection
        let massive_profit = LARGE_DEPOSIT * 5; // 50 APT profit
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, massive_profit);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // NAV should reflect massive profit
        let nav = InvestorToken::nav();
        let expected_nav = ((LARGE_DEPOSIT / 10 + massive_profit) * 1000000)
            / (LARGE_DEPOSIT / 10);

        assert!(nav == expected_nav, 1);
        assert!(nav > 50000000, 2); // NAV > 50 (massive profit)

        // Investor should be able to redeem at high NAV
        let tokens_to_redeem = (LARGE_DEPOSIT / 10) / 2;
        let apt_before = coin::balance<AptosCoin>(INVESTOR_ADDR);

        InvestorToken::redeem(&investor, tokens_to_redeem);

        let apt_after = coin::balance<AptosCoin>(INVESTOR_ADDR);
        let received = apt_after - apt_before;

        // Should receive much more than face value
        assert!(received > tokens_to_redeem, 3);
    }

    #[test]
    fun test_game_lifecycle_with_active_bets() acquires TestGameAuth {
        let (framework, casino_account, _dice_account) = setup_critical_test();

        // Setup game and investor
        let test_game = account::create_account_for_test(TEST_GAME_ADDR);
        CasinoHouse::register_game(
            &casino_account,
            TEST_GAME_ADDR,
            string::utf8(b"Test Game"),
            1000000,
            100000000,
            150
        );
        let capability = CasinoHouse::get_game_capability(&test_game);
        move_to(&test_game, TestGameAuth { capability });

        let investor = create_funded_player(&framework, INVESTOR_ADDR, LARGE_DEPOSIT);
        InvestorToken::deposit_and_mint(&investor, LARGE_DEPOSIT);

        // Fund treasury for payouts
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, SMALL_RESERVE);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        // Place active bet
        let player = create_funded_player(&framework, WHALE_ADDR, MASSIVE_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, 50000000);

        let auth = borrow_global<TestGameAuth>(TEST_GAME_ADDR);
        let bet_id =
            CasinoHouse::place_bet(
                &auth.capability,
                bet_coins,
                WHALE_ADDR,
                100000000
            );

        // Verify bet is placed
        assert!(CasinoHouse::treasury_balance() > LARGE_DEPOSIT, 1);

        // Settle the bet before unregistering
        CasinoHouse::settle_bet(&auth.capability, bet_id, WHALE_ADDR, 0);

        // Now unregister game
        CasinoHouse::unregister_game(&casino_account, TEST_GAME_ADDR);
        assert!(!CasinoHouse::is_game_registered(TEST_GAME_ADDR), 2);

        // System should remain stable
        assert!(CasinoHouse::treasury_balance() > 0, 3);
        assert!(InvestorToken::nav() > 0, 4);
    }
}
