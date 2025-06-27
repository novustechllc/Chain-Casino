//! Test suite for CasinoHouse module - updated for new function signatures

#[test_only]
module casino::CasinoHouseTest {
    use std::string;
    use std::vector;
    use std::signer;
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

    fun setup_game_and_bet(
        casino_account: &signer, game_account: &signer
    ) {
        CasinoHouse::init(casino_account);
        CasinoHouse::register_game(
            casino_account,
            game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(casino_account, MIN_BET);
        let _bet_id = CasinoHouse::place_bet(@0x123, coins, @0x123);
    }

    //
    // Initialization Tests
    //

    #[test]
    fun test_init_success() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);

        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(CasinoHouse::get_params() == 150, 2);
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 3);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_NOT_ADMIN, location = casino::CasinoHouse
        )
    ]
    fun test_init_unauthorized() {
        let (_, _, game_account) = setup_test();
        CasinoHouse::init(&game_account);
    }

    //
    // Game Management Tests
    //

    #[test]
    fun test_register_game_success() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 1, 1);

        let game_info = CasinoHouse::get_game_info(@0x123);
        assert!(CasinoHouse::get_game_name(&game_info) == string::utf8(b"Dice Game"), 2);
        assert!(CasinoHouse::get_game_module_address(&game_info) == @0x123, 3);
        assert!(CasinoHouse::get_game_active(&game_info) == true, 4);
        assert!(CasinoHouse::is_game_active(@0x123) == true, 5);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_NOT_ADMIN, location = casino::CasinoHouse
        )
    ]
    fun test_register_game_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &game_account, // Wrong signer
            &game_account,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_AMOUNT,
            location = casino::CasinoHouse
        )
    ]
    fun test_register_game_invalid_params() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Bad Game"),
            MAX_BET, // min_bet > max_bet
            MIN_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_AMOUNT,
            location = casino::CasinoHouse
        )
    ]
    fun test_register_game_zero_min_bet() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Zero Bet Game"),
            0, // min_bet = 0 should fail
            MAX_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_ALREADY_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_register_game_duplicate() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Game 1"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to register same address again
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Game 2"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
    }

    #[test]
    fun test_unregister_game() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 1, 1);

        CasinoHouse::unregister_game(&casino_account, @0x123);

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_unregister_nonexistent_game() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::unregister_game(&casino_account, @0x123);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_NOT_ADMIN, location = casino::CasinoHouse
        )
    ]
    fun test_unregister_game_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to unregister with wrong signer
        CasinoHouse::unregister_game(&game_account, @0x123);
    }

    #[test]
    fun test_toggle_game() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(CasinoHouse::is_game_active(@0x123) == true, 1);

        CasinoHouse::toggle_game(&casino_account, @0x123, false);
        assert!(CasinoHouse::is_game_active(@0x123) == false, 2);

        CasinoHouse::toggle_game(&casino_account, @0x123, true);
        assert!(CasinoHouse::is_game_active(@0x123) == true, 3);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_toggle_nonexistent_game() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::toggle_game(&casino_account, @0x123, false);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_NOT_ADMIN, location = casino::CasinoHouse
        )
    ]
    fun test_toggle_game_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to toggle with wrong signer
        CasinoHouse::toggle_game(&game_account, @0x123, false);
    }

    #[test]
    fun test_multiple_games_registration() {
        let (_, casino_account, _) = setup_test();
        let game1 = account::create_account_for_test(@0x111);
        let game2 = account::create_account_for_test(@0x222);

        CasinoHouse::init(&casino_account);

        CasinoHouse::register_game(
            &casino_account,
            &game1,
            string::utf8(b"Dice Game"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        CasinoHouse::register_game(
            &casino_account,
            &game2,
            string::utf8(b"Poker Game"),
            MIN_BET * 2,
            MAX_BET * 2,
            HOUSE_EDGE + 50
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 2, 1);

        assert!(CasinoHouse::is_game_active(@0x111) == true, 2);
        assert!(CasinoHouse::is_game_active(@0x222) == true, 3);
    }

    //
    // Public Function Tests (Updated)
    //

    #[test]
    fun test_place_bet() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        let bet_id = CasinoHouse::place_bet(@0x123, coins, @0x123);

        assert!(bet_id == 1, 1);
        assert!(CasinoHouse::treasury_balance() == MIN_BET, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_INACTIVE,
            location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_inactive_game() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::toggle_game(&casino_account, @0x123, false);

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        CasinoHouse::place_bet(@0x123, coins, @0x123);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_unregistered_game() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init(&casino_account);

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        CasinoHouse::place_bet(@0x999, coins, @0x123); // Non-existent game
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_AMOUNT,
            location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_below_minimum() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET - 1);
        CasinoHouse::place_bet(@0x123, coins, @0x123);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_AMOUNT,
            location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_above_maximum() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MAX_BET + 1);
        CasinoHouse::place_bet(@0x123, coins, @0x123);
    }

    #[test]
    fun test_settle_bet() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            string::utf8(b"Test"),
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Place bet first
        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        let bet_id = CasinoHouse::place_bet(@0x123, coins, @0x123);

        // Register winner's account
        let winner_addr = signer::address_of(&game_account);
        coin::register<AptosCoin>(&game_account);

        // Settle bet using test helper
        CasinoHouse::test_settle_bet(
            @0x123,
            bet_id,
            winner_addr,
            MIN_BET / 2,
            MIN_BET / 2
        );
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_SETTLEMENT,
            location = casino::CasinoHouse
        )
    ]
    fun test_settle_bet_zero_amount() {
        let (_, casino_account, game_account) = setup_test();
        setup_game_and_bet(&casino_account, &game_account);

        CasinoHouse::test_settle_bet(@0x123, 1, @0x123, 0, 0);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INSUFFICIENT_TREASURY,
            location = casino::CasinoHouse
        )
    ]
    fun test_settle_bet_insufficient_treasury() {
        let (_, casino_account, game_account) = setup_test();
        setup_game_and_bet(&casino_account, &game_account);

        // Try to payout more than treasury has
        CasinoHouse::test_settle_bet(@0x123, 1, @0x123, MIN_BET * 2, 0);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_INACTIVE,
            location = casino::CasinoHouse
        )
    ]
    fun test_settle_bet_inactive_game() {
        let (_, casino_account, game_account) = setup_test();
        setup_game_and_bet(&casino_account, &game_account);

        // Deactivate game
        CasinoHouse::toggle_game(&casino_account, @0x123, false);

        // Try to settle bet on inactive game
        CasinoHouse::test_settle_bet(@0x123, 1, @0x123, MIN_BET / 2, MIN_BET / 2);
    }

    #[test]
    fun test_settle_bet_with_payout() {
        let (_, casino_account, game_account) = setup_test();
        setup_game_and_bet(&casino_account, &game_account);

        let winner = account::create_account_for_test(@0x999);
        coin::register<AptosCoin>(&winner);

        CasinoHouse::test_settle_bet(@0x123, 1, @0x999, MIN_BET / 2, MIN_BET / 2);

        assert!(
            coin::balance<AptosCoin>(@0x999) == MIN_BET / 2,
            1
        );
    }

    #[test]
    fun test_treasury_operations() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init(&casino_account);

        let coins = coin::withdraw<AptosCoin>(&casino_account, 1000000);
        CasinoHouse::deposit_to_treasury(coins);
        assert!(CasinoHouse::treasury_balance() == 1000000, 1);

        let withdrawn = CasinoHouse::redeem_from_treasury(500000);
        coin::deposit(@casino, withdrawn);
        assert!(CasinoHouse::treasury_balance() == 500000, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INSUFFICIENT_TREASURY,
            location = casino::CasinoHouse
        )
    ]
    fun test_redeem_from_treasury_insufficient() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init(&casino_account);

        CasinoHouse::test_redeem_from_treasury(1); // Will abort before creating coin
    }

    #[test]
    fun test_redeem_from_treasury_success() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init(&casino_account);

        // Add funds first
        let deposit_coins = coin::withdraw<AptosCoin>(&casino_account, 1000);
        CasinoHouse::deposit_to_treasury(deposit_coins);

        // Now redeem
        let withdrawn_coins = CasinoHouse::redeem_from_treasury(500);
        coin::deposit(@casino, withdrawn_coins); // Must handle the coins
    }

    //
    // View Function Tests
    //

    #[test]
    fun test_get_registered_games_empty() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 0, 1);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_get_game_info_nonexistent() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::get_game_info(@0x123);
    }

    #[test]
    fun test_treasury_balance_accuracy() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        assert!(CasinoHouse::treasury_balance() == 0, 1);
    }

    #[test]
    fun test_is_game_active_nonexistent() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        assert!(CasinoHouse::is_game_active(@0x123) == false, 1);
    }

    //
    // Admin Operations Tests
    //

    #[test]
    fun test_set_house_edge() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        assert!(CasinoHouse::get_params() == 150, 1);

        CasinoHouse::set_house_edge(&casino_account, 200);
        assert!(CasinoHouse::get_params() == 200, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_NOT_ADMIN, location = casino::CasinoHouse
        )
    ]
    fun test_set_house_edge_unauthorized() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::set_house_edge(&game_account, 200);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_AMOUNT,
            location = casino::CasinoHouse
        )
    ]
    fun test_set_house_edge_too_high() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::set_house_edge(&casino_account, 1001); // > 10%
    }

    #[test]
    fun test_set_house_edge_boundary_values() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);

        // Test minimum edge (0%)
        CasinoHouse::set_house_edge(&casino_account, 0);
        assert!(CasinoHouse::get_params() == 0, 1);

        // Test maximum edge (10%)
        CasinoHouse::set_house_edge(&casino_account, 1000);
        assert!(CasinoHouse::get_params() == 1000, 2);
    }
}
