//! Comprehensive test suite for CasinoHouse module

#[test_only]
module casino::CasinoHouseTest {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 500000000; // 5 APT
    const HOUSE_EDGE: u64 = 150; // 1.5%

    // Error constants for testing
    const E_NOT_ADMIN: u64 = 0x01;
    const E_INVALID_AMOUNT: u64 = 0x02;
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    const E_GAME_ALREADY_REGISTERED: u64 = 0x05;
    const E_INSUFFICIENT_TREASURY: u64 = 0x06;
    const E_INVALID_SETTLEMENT: u64 = 0x07;
    const E_INSUFFICIENT_TREASURY_FOR_PAYOUT: u64 = 0x08;
    const E_PAYOUT_EXCEEDS_EXPECTED: u64 = 0x09;
    const E_BET_ALREADY_SETTLED: u64 = 0x0A;

    // Store capabilities for testing
    struct TestGameAuth has key {
        capability: GameCapability
    }

    fun setup_test(): (signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        coin::register<AptosCoin>(&casino_account);
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);

        (aptos_framework, casino_account)
    }

    fun create_player(framework: &signer, addr: address, balance: u64): signer {
        let player = account::create_account_for_test(addr);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(framework, addr, balance);
        player
    }

    //
    // Initialization Tests
    //

    #[test]
    fun test_init_module_success() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 2);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = casino::CasinoHouse)]
    fun test_init_unauthorized() {
        let fake_admin = account::create_account_for_test(@0x999);
        CasinoHouse::init_module_for_test(&fake_admin);
    }

    //
    // Game Registration Tests
    //

    #[test]
    fun test_register_game_success() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Dice Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        assert!(CasinoHouse::is_game_registered(@0x123), 1);
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 1, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_GAME_ALREADY_REGISTERED, location = casino::CasinoHouse
        )
    ]
    fun test_register_game_duplicate() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let cap1 =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Game 1"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability: cap1 });

        // This will abort, but compiler needs to see value handling
        let _cap2 =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Game 2"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability: _cap2 });
    }

    #[test]
    fun test_unregister_game() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        assert!(CasinoHouse::is_game_registered(@0x123), 1);
        CasinoHouse::unregister_game(&casino_account, @0x123);
        assert!(!CasinoHouse::is_game_registered(@0x123), 2);
    }

    //
    // Bet Placement Tests
    //

    #[test]
    fun test_place_bet_success() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        // Fund treasury
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET * 2);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_player(&framework, @0x999, MIN_BET * 2);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id = CasinoHouse::place_bet(
            &auth.capability, bet_coins, @0x999, MIN_BET * 2
        );

        assert!(bet_id == 1, 1);
        assert!(
            CasinoHouse::treasury_balance() == MIN_BET * 3,
            2
        );
    }

    // Note: Cannot test unregistered game scenario since GameCapability
    // can only be created by CasinoHouse module (Move security feature)

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = casino::CasinoHouse)]
    fun test_place_bet_below_minimum() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET - 1);

        let auth = borrow_global<TestGameAuth>(@casino);
        CasinoHouse::place_bet(&auth.capability, bet_coins, @0x999, MIN_BET);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_INSUFFICIENT_TREASURY_FOR_PAYOUT, location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_insufficient_treasury() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        CasinoHouse::place_bet(
            &auth.capability,
            bet_coins,
            @0x999,
            INITIAL_BALANCE
        );
    }

    //
    // Bet Settlement Tests
    //

    #[test]
    fun test_settle_bet_success() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        // Fund treasury and place bet
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET * 2);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id = CasinoHouse::place_bet(
            &auth.capability, bet_coins, @0x999, MIN_BET * 2
        );

        let initial_balance = coin::balance<AptosCoin>(@0x999);
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x999, MIN_BET);

        assert!(
            coin::balance<AptosCoin>(@0x999) == initial_balance + MIN_BET,
            1
        );
    }

    #[test]
    #[expected_failure(abort_code = E_BET_ALREADY_SETTLED, location = casino::CasinoHouse)]
    fun test_settle_bet_already_settled() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        // Setup and place bet
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET * 2);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id = CasinoHouse::place_bet(
            &auth.capability, bet_coins, @0x999, MIN_BET * 2
        );

        // Settle once
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x999, MIN_BET);

        // Try to settle again
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x999, MIN_BET);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_PAYOUT_EXCEEDS_EXPECTED, location = casino::CasinoHouse
        )
    ]
    fun test_settle_bet_payout_exceeds_expected() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        // Setup and place bet
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET * 3);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id = CasinoHouse::place_bet(
            &auth.capability, bet_coins, @0x999, MIN_BET * 2
        );

        // Try to settle with payout exceeding expected
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x999, MIN_BET * 3);
    }

    //
    // Treasury Operations Tests
    //

    #[test]
    fun test_treasury_operations() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        // Test deposit
        let deposit_coins = coin::withdraw<AptosCoin>(&casino_account, 1000000);
        CasinoHouse::deposit_to_treasury(deposit_coins);
        assert!(CasinoHouse::treasury_balance() == 1000000, 1);

        // Test redeem
        let redeemed_coins = CasinoHouse::redeem_from_treasury(500000);
        coin::deposit(@casino, redeemed_coins);
        assert!(CasinoHouse::treasury_balance() == 500000, 2);
    }

    #[test]
    #[expected_failure(
        abort_code = E_INSUFFICIENT_TREASURY, location = casino::CasinoHouse
    )]
    fun test_redeem_from_empty_treasury() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let coins = CasinoHouse::redeem_from_treasury(1);
        coin::deposit(@casino, coins);
    }

    //
    // View Functions Tests
    //

    #[test]
    fun test_view_functions() {
        let (_, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        // Initially empty
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 0, 1);
        assert!(!CasinoHouse::is_game_registered(@0x123), 2);
        assert!(CasinoHouse::treasury_balance() == 0, 3);

        // After registering game
        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 1, 4);
        assert!(CasinoHouse::is_game_registered(@0x123), 5);

        let _game_info = CasinoHouse::get_game_info(@0x123);
    }

    #[test]
    fun test_multiple_bets_incrementing_id() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        // Fund treasury
        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET * 6);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player1 = create_player(&framework, @0x111, MIN_BET * 2);
        let player2 = create_player(&framework, @0x222, MIN_BET * 2);

        let bet_coins1 = coin::withdraw<AptosCoin>(&player1, MIN_BET);
        let bet_coins2 = coin::withdraw<AptosCoin>(&player2, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id1 =
            CasinoHouse::place_bet(
                &auth.capability,
                bet_coins1,
                @0x111,
                MIN_BET * 2
            );
        let bet_id2 =
            CasinoHouse::place_bet(
                &auth.capability,
                bet_coins2,
                @0x222,
                MIN_BET * 2
            );

        assert!(bet_id1 == 1, 1);
        assert!(bet_id2 == 2, 2);
    }

    #[test]
    fun test_zero_payout_settlement() acquires TestGameAuth {
        let (framework, casino_account) = setup_test();
        CasinoHouse::init_module_for_test(&casino_account);

        let capability =
            CasinoHouse::register_game(
                &casino_account,
                @0x123,
                string::utf8(b"Test Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
        move_to(&casino_account, TestGameAuth { capability });

        let treasury_coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        CasinoHouse::deposit_to_treasury(treasury_coins);

        let player = create_player(&framework, @0x999, MIN_BET);
        let bet_coins = coin::withdraw<AptosCoin>(&player, MIN_BET);

        let auth = borrow_global<TestGameAuth>(@casino);
        let bet_id = CasinoHouse::place_bet(&auth.capability, bet_coins, @0x999, MIN_BET);

        // House wins - zero payout
        CasinoHouse::settle_bet(&auth.capability, bet_id, @0x999, 0);

        // Treasury should retain all funds
        assert!(
            CasinoHouse::treasury_balance() == MIN_BET * 2,
            1
        );
    }
}
