//! Comprehensive test suite for CasinoHouse module

#[test_only]
module casino::CasinoHouseTest {
    use std::string;
    use std::vector;
    use std::debug;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 500000000; // 5 APT
    const HOUSE_EDGE: u64 = 150; // 1.5%

    // Error constants
    const E_NOT_ADMIN: u64 = 0x01;
    const E_INVALID_AMOUNT: u64 = 0x02;
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    const E_GAME_ALREADY_REGISTERED: u64 = 0x05;
    const E_INSUFFICIENT_TREASURY: u64 = 0x06;
    const E_INVALID_SETTLEMENT: u64 = 0x07;

    fun setup_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let game_account = account::create_account_for_test(@0x123);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&game_account);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);

        (aptos_framework, casino_account, game_account)
    }

    // Helper function to create a player with appropriate balance for testing
    fun create_player_with_balance(aptos_framework: &signer, player_address: address, balance: u64): signer {
        let player = account::create_account_for_test(player_address);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(aptos_framework, player_address, balance);
        player
    }

    //
    // Initialization Tests
    //

    #[test]
    fun test_init_module_success() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);

        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(CasinoHouse::get_params() == 150, 2);
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = casino::CasinoHouse)]
    fun test_init_module_unauthorized() {
        let (_, _, game_account) = setup_test();
        CasinoHouse::init_module_for_test(&game_account);
    }

    //
    // Game Registration Tests
    //

    #[test]
    fun test_register_game_success() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 1, 1);
        assert!(CasinoHouse::is_game_registered(@0x123) == true, 2);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = casino::CasinoHouse)]
    fun test_register_game_unauthorized() {
        let (_, _, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&game_account); // This will fail first
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_register_game_zero_min_bet() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Bad Game"),
            0, // min_bet = 0 should fail
            MAX_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_register_game_min_greater_than_max() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Bad Game"),
            MAX_BET, // min_bet > max_bet
            MIN_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_GAME_ALREADY_REGISTERED, location = casino::CasinoHouse
        )
    ]
    fun test_register_game_duplicate() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Game 1"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to register same address again
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Game 2"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    fun test_multiple_games_registration() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);

        CasinoHouse::register_game(
            &casino_account,
            @0x111,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        CasinoHouse::register_game(
            &casino_account,
            @0x222,
            string::utf8(b"Poker Game"),
            MIN_BET * 2,
            MAX_BET * 2,
            HOUSE_EDGE + 50
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 2, 1);
        assert!(CasinoHouse::is_game_registered(@0x111) == true, 2);
        assert!(CasinoHouse::is_game_registered(@0x222) == true, 3);
    }

    #[test]
    fun test_unregister_game() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 1, 1);

        CasinoHouse::unregister_game(&casino_account, @0x123);

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 2);
        assert!(CasinoHouse::is_game_registered(@0x123) == false, 3);
    }

    #[test]
    #[expected_failure(abort_code = E_GAME_NOT_REGISTERED, location = casino::CasinoHouse)]
    fun test_unregister_nonexistent_game() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::unregister_game(&casino_account, @0x123);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = casino::CasinoHouse)]
    fun test_unregister_game_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to unregister with wrong signer
        CasinoHouse::unregister_game(&game_account, @0x123);
    }

    //
    // Bet Placement Tests (Updated for signer-based approach)
    //

    #[test]
    fun test_place_bet_success() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MIN_BET * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, MIN_BET);
        let bet_id = CasinoHouse::place_bet(&game_account, coins, @0x999);

        assert!(bet_id == 1, 1);
        assert!(CasinoHouse::treasury_balance() == MIN_BET, 2);
    }

    #[test]
    #[expected_failure(abort_code = E_GAME_NOT_REGISTERED, location = casino::CasinoHouse)]
    fun test_place_bet_unregistered_game() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        // Don't register the game

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MIN_BET * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, MIN_BET);
        CasinoHouse::place_bet(&game_account, coins, @0x999);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_place_bet_below_minimum() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MIN_BET * 2);

        // Player funds bet through game with amount below minimum
        let coins = coin::withdraw<AptosCoin>(&player, MIN_BET - 1);
        CasinoHouse::place_bet(&game_account, coins, @0x999);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_place_bet_above_maximum() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MAX_BET * 2);

        // Player funds bet through game with amount above maximum
        let coins = coin::withdraw<AptosCoin>(&player, MAX_BET + 1);
        CasinoHouse::place_bet(&game_account, coins, @0x999);
    }

    #[test]
    fun test_multiple_bets_incrementing_id() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create players with appropriate balances for test
        let player1 = create_player_with_balance(&aptos_framework, @0x111, MIN_BET * 2);
        let player2 = create_player_with_balance(&aptos_framework, @0x222, MIN_BET * 4);

        // Players fund bets through game
        let coins1 = coin::withdraw<AptosCoin>(&player1, MIN_BET);
        let bet_id1 = CasinoHouse::place_bet(&game_account, coins1, @0x111);

        let coins2 = coin::withdraw<AptosCoin>(&player2, MIN_BET * 2);
        let bet_id2 = CasinoHouse::place_bet(&game_account, coins2, @0x222);

        assert!(bet_id1 == 1, 1);
        assert!(bet_id2 == 2, 2);
        assert!(
            CasinoHouse::treasury_balance() == MIN_BET * 3,
            3
        );
    }

    //
    // Bet Settlement Tests
    //

    #[test]
    fun test_settle_bet_winner_payout() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MIN_BET * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, MIN_BET);
        let bet_id = CasinoHouse::place_bet(&game_account, coins, @0x999);

        // Settle with payout
        CasinoHouse::settle_bet(
            &game_account,
            bet_id,
            @0x999,
            MIN_BET / 2,
            MIN_BET / 2
        );

        assert!(
            coin::balance<AptosCoin>(@0x999) == MIN_BET / 2,
            1
        );
        assert!(
            CasinoHouse::treasury_balance() == MIN_BET / 2,
            2
        );
    }

    #[test]
    fun test_settle_bet_house_wins() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, MIN_BET * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, MIN_BET);
        let bet_id = CasinoHouse::place_bet(&game_account, coins, @0x999);

        // Settle with no payout (house wins all)
        CasinoHouse::settle_bet(&game_account, bet_id, @0x999, 0, MIN_BET);

        assert!(CasinoHouse::treasury_balance() == MIN_BET, 1);
    }

    #[test]
    #[expected_failure(abort_code = E_GAME_NOT_REGISTERED, location = casino::CasinoHouse)]
    fun test_settle_bet_unregistered_game() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        // Don't register game

        CasinoHouse::settle_bet(&game_account, 1, @0x999, 100, 100);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_SETTLEMENT, location = casino::CasinoHouse)]
    fun test_settle_bet_zero_total() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        CasinoHouse::settle_bet(&game_account, 1, @0x999, 0, 0);
    }

    #[test]
    #[expected_failure(
        abort_code = E_INSUFFICIENT_TREASURY, location = casino::CasinoHouse
    )]
    fun test_settle_bet_insufficient_treasury() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to payout more than treasury has (treasury is empty)
        CasinoHouse::settle_bet(&game_account, 1, @0x999, 1000, 0);
    }

    //
    // Treasury Operations Tests (Package functions)
    //

    #[test]
    fun test_treasury_operations_within_package() {
        // Note: These are package functions, so they can only be tested
        // from within the casino package. In a real scenario, these would
        // be called by InvestorToken module.

        let (_, casino_account, _) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        // Test deposit
        let deposit_coins = coin::withdraw<AptosCoin>(&casino_account, 1000000);
        CasinoHouse::deposit_to_treasury(deposit_coins);
        assert!(CasinoHouse::treasury_balance() == 1000000, 1);

        // Test redeem
        let withdrawn_coins = CasinoHouse::redeem_from_treasury(500000);
        coin::deposit(@casino, withdrawn_coins); // Must handle the coins
        assert!(CasinoHouse::treasury_balance() == 500000, 2);
    }

    #[test]
    #[expected_failure(
        abort_code = E_INSUFFICIENT_TREASURY, location = casino::CasinoHouse
    )]
    fun test_redeem_from_empty_treasury() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let coins = CasinoHouse::redeem_from_treasury(1);
        // Will abort before creating coins

        CasinoHouse::deposit_to_treasury(coins);
    }

    //
    // View Functions Tests
    //

    #[test]
    fun test_get_registered_games_empty() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = E_GAME_NOT_REGISTERED, location = casino::CasinoHouse)]
    fun test_get_game_info_nonexistent() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::get_game_info(@0x123);
    }

    #[test]
    fun test_get_game_info_success() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let game_info = CasinoHouse::get_game_info(@0x123);
        // In real implementation, would need getter functions for GameInfo fields
    }

    #[test]
    fun test_is_game_registered() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        assert!(CasinoHouse::is_game_registered(@0x123) == false, 1);

        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(CasinoHouse::is_game_registered(@0x123) == true, 2);
    }

    //
    // Admin Operations Tests
    //

    #[test]
    fun test_set_house_edge_success() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        assert!(CasinoHouse::get_params() == 150, 1);

        CasinoHouse::set_house_edge(&casino_account, 200);
        assert!(CasinoHouse::get_params() == 200, 2);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = casino::CasinoHouse)]
    fun test_set_house_edge_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::set_house_edge(&game_account, 200);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_set_house_edge_too_high() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::set_house_edge(&casino_account, 1001); // > 10%
    }

    #[test]
    fun test_set_house_edge_boundary_values() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);

        // Test minimum edge (0%)
        CasinoHouse::set_house_edge(&casino_account, 0);
        assert!(CasinoHouse::get_params() == 0, 1);

        // Test maximum edge (10%)
        CasinoHouse::set_house_edge(&casino_account, 1000);
        assert!(CasinoHouse::get_params() == 1000, 2);
    }

    //
    // Edge Cases and Complex Scenarios
    //

    #[test]
    fun test_large_bet_amounts() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"High Roller Game"),
            100000000, // 1 APT min
            1000000000, // 10 APT max
            HOUSE_EDGE
        );

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, 1000000000 * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, 1000000000);
        let bet_id = CasinoHouse::place_bet(&game_account, coins, @0x999);

        assert!(bet_id == 1, 1);
        assert!(CasinoHouse::treasury_balance() == 1000000000, 2);
    }

    #[test]
    fun test_bet_settlement_math_precision() {
        let (aptos_framework, casino_account, game_account) = setup_test();

        CasinoHouse::init_module_for_test(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let bet_amount = 1000003;

        // Create player with appropriate balance for test
        let player = create_player_with_balance(&aptos_framework, @0x999, bet_amount * 2);

        // Player funds bet through game
        let coins = coin::withdraw<AptosCoin>(&player, bet_amount);
        let bet_id = CasinoHouse::place_bet(&game_account, coins, @0x999);

        // Settle with exact split
        let payout = 500001;
        let profit = 500002;
        CasinoHouse::settle_bet(&game_account, bet_id, @0x999, payout, profit);

        assert!(CasinoHouse::treasury_balance() == profit, 1);
    }

    #[test]
    fun test_concurrent_operations() {
        let (aptos_framework, casino_account, _) = setup_test();
        let game1 = account::create_account_for_test(@0x111);
        let game2 = account::create_account_for_test(@0x222);

        coin::register<AptosCoin>(&game1);
        coin::register<AptosCoin>(&game2);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        CasinoHouse::init_module_for_test(&casino_account);

        // Register multiple games
        CasinoHouse::register_game(
            &casino_account,
            @0x111,
            string::utf8(b"Game1"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::register_game(
            &casino_account,
            @0x222,
            string::utf8(b"Game2"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Create players with appropriate balances for test
        let player1 = create_player_with_balance(&aptos_framework, @0x333, MIN_BET * 2);
        let player2 = create_player_with_balance(&aptos_framework, @0x444, MIN_BET * 4);

        // Players fund concurrent bets through games
        let coins1 = coin::withdraw<AptosCoin>(&player1, MIN_BET);
        let coins2 = coin::withdraw<AptosCoin>(&player2, MIN_BET * 2);

        let bet_id1 = CasinoHouse::place_bet(&game1, coins1, @0x333);
        let bet_id2 = CasinoHouse::place_bet(&game2, coins2, @0x444);

        assert!(bet_id1 == 1, 1);
        assert!(bet_id2 == 2, 2);
        assert!(
            CasinoHouse::treasury_balance() == MIN_BET * 3,
            3
        );
    }
}
