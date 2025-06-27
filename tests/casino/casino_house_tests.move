//! Test suite for CasinoHouse module - public interface only

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
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(casino_account, MIN_BET);
        let _bet_id = CasinoHouse::place_bet_internal(coins, @0x123, 1);
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
            b"Dice Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 1, 1);

        let game_info = CasinoHouse::get_game_info(1);
        assert!(CasinoHouse::get_game_name(&game_info) == string::utf8(b"Dice Game"), 2);
        assert!(CasinoHouse::get_game_module_address(&game_info) == @0x123, 3);
        assert!(CasinoHouse::get_game_active(&game_info) == true, 4);
        assert!(CasinoHouse::is_game_active(1) == true, 5);
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
            b"Dice Game",
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
            b"Bad Game",
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
            b"Zero Bet Game",
            0, // min_bet = 0 should fail
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
            b"Dice Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(vector::length(&CasinoHouse::get_registered_games()) == 1, 1);

        CasinoHouse::unregister_game(&casino_account, 1);

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
        CasinoHouse::unregister_game(&casino_account, 1);
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
            b"Test Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to unregister with wrong signer
        CasinoHouse::unregister_game(&game_account, 1);
    }

    #[test]
    fun test_toggle_game() {
        let (_, casino_account, game_account) = setup_test();

        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            b"Dice Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        assert!(CasinoHouse::is_game_active(1) == true, 1);

        CasinoHouse::toggle_game(&casino_account, 1, false);
        assert!(CasinoHouse::is_game_active(1) == false, 2);

        CasinoHouse::toggle_game(&casino_account, 1, true);
        assert!(CasinoHouse::is_game_active(1) == true, 3);
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
        CasinoHouse::toggle_game(&casino_account, 1, false);
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
            b"Test Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Try to toggle with wrong signer
        CasinoHouse::toggle_game(&game_account, 1, false);
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
            b"Dice Game",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        CasinoHouse::register_game(
            &casino_account,
            &game2,
            b"Poker Game",
            MIN_BET * 2,
            MAX_BET * 2,
            HOUSE_EDGE + 50
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 2, 1);

        assert!(CasinoHouse::is_game_active(1) == true, 2);
        assert!(CasinoHouse::is_game_active(2) == true, 3);
    }

    #[test]
    fun test_game_id_increment() {
        let (_, casino_account, _) = setup_test();
        let game1 = account::create_account_for_test(@0x111);
        let game2 = account::create_account_for_test(@0x222);

        CasinoHouse::init(&casino_account);

        CasinoHouse::register_game(
            &casino_account,
            &game1,
            b"Game 1",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        CasinoHouse::register_game(
            &casino_account,
            &game2,
            b"Game 2",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let game_info1 = CasinoHouse::get_game_info(1);
        let game_info2 = CasinoHouse::get_game_info(2);

        assert!(CasinoHouse::get_game_module_address(&game_info1) == @0x111, 1);
        assert!(CasinoHouse::get_game_module_address(&game_info2) == @0x222, 2);
    }

    #[test]
    fun test_register_many_games() {
        let (_, casino_account, _) = setup_test();

        CasinoHouse::init(&casino_account);

        // Create predefined game accounts
        let game1 = account::create_account_for_test(@0x1001);
        let game2 = account::create_account_for_test(@0x1002);
        let game3 = account::create_account_for_test(@0x1003);
        let game4 = account::create_account_for_test(@0x1004);
        let game5 = account::create_account_for_test(@0x1005);

        // Register games
        CasinoHouse::register_game(
            &casino_account,
            &game1,
            b"Game 1",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::register_game(
            &casino_account,
            &game2,
            b"Game 2",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::register_game(
            &casino_account,
            &game3,
            b"Game 3",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::register_game(
            &casino_account,
            &game4,
            b"Game 4",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::register_game(
            &casino_account,
            &game5,
            b"Game 5",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Verify all games registered
        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 5, 1);

        // Verify game IDs are sequential
        assert!(CasinoHouse::is_game_active(1), 2);
        assert!(CasinoHouse::is_game_active(3), 3);
        assert!(CasinoHouse::is_game_active(5), 4);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_INVALID_GAME_INTERFACE,
            location = casino::CasinoHouse
        )
    ]
    fun test_register_game_max_limit() {
        let (_, casino_account, _) = setup_test();
        CasinoHouse::init(&casino_account);

        // Predefined addresses for 255 games (254 + 1 to trigger failure)
        let addrs = vector[
            @0x1001, @0x1002, @0x1003, @0x1004, @0x1005, @0x1006, @0x1007, @0x1008, @0x1009, @0x100a, @0x100b, @0x100c, @0x100d, @0x100e, @0x100f, @0x1010, @0x1011, @0x1012, @0x1013, @0x1014, @0x1015, @0x1016, @0x1017, @0x1018, @0x1019, @0x101a, @0x101b, @0x101c, @0x101d, @0x101e, @0x101f, @0x1020, @0x1021, @0x1022, @0x1023, @0x1024, @0x1025, @0x1026, @0x1027, @0x1028, @0x1029, @0x102a, @0x102b, @0x102c, @0x102d, @0x102e, @0x102f, @0x1030, @0x1031, @0x1032, @0x1033, @0x1034, @0x1035, @0x1036, @0x1037, @0x1038, @0x1039, @0x103a, @0x103b, @0x103c, @0x103d, @0x103e, @0x103f, @0x1040, @0x1041, @0x1042, @0x1043, @0x1044, @0x1045, @0x1046, @0x1047, @0x1048, @0x1049, @0x104a, @0x104b, @0x104c, @0x104d, @0x104e, @0x104f, @0x1050, @0x1051, @0x1052, @0x1053, @0x1054, @0x1055, @0x1056, @0x1057, @0x1058, @0x1059, @0x105a, @0x105b, @0x105c, @0x105d, @0x105e, @0x105f, @0x1060, @0x1061, @0x1062, @0x1063, @0x1064, @0x1065, @0x1066, @0x1067, @0x1068, @0x1069, @0x106a, @0x106b, @0x106c, @0x106d, @0x106e, @0x106f, @0x1070, @0x1071, @0x1072, @0x1073, @0x1074, @0x1075, @0x1076, @0x1077, @0x1078, @0x1079, @0x107a, @0x107b, @0x107c, @0x107d, @0x107e, @0x107f, @0x1080, @0x1081, @0x1082, @0x1083, @0x1084, @0x1085, @0x1086, @0x1087, @0x1088, @0x1089, @0x108a, @0x108b, @0x108c, @0x108d, @0x108e, @0x108f, @0x1090, @0x1091, @0x1092, @0x1093, @0x1094, @0x1095, @0x1096, @0x1097, @0x1098, @0x1099, @0x109a, @0x109b, @0x109c, @0x109d, @0x109e, @0x109f, @0x10a0, @0x10a1, @0x10a2, @0x10a3, @0x10a4, @0x10a5, @0x10a6, @0x10a7, @0x10a8, @0x10a9, @0x10aa, @0x10ab, @0x10ac, @0x10ad, @0x10ae, @0x10af, @0x10b0, @0x10b1, @0x10b2, @0x10b3, @0x10b4, @0x10b5, @0x10b6, @0x10b7, @0x10b8, @0x10b9, @0x10ba, @0x10bb, @0x10bc, @0x10bd, @0x10be, @0x10bf, @0x10c0, @0x10c1, @0x10c2, @0x10c3, @0x10c4, @0x10c5, @0x10c6, @0x10c7, @0x10c8, @0x10c9, @0x10ca, @0x10cb, @0x10cc, @0x10cd, @0x10ce, @0x10cf, @0x10d0, @0x10d1, @0x10d2, @0x10d3, @0x10d4, @0x10d5, @0x10d6, @0x10d7, @0x10d8, @0x10d9, @0x10da, @0x10db, @0x10dc, @0x10dd, @0x10de, @0x10df, @0x10e0, @0x10e1, @0x10e2, @0x10e3, @0x10e4, @0x10e5, @0x10e6, @0x10e7, @0x10e8, @0x10e9, @0x10ea, @0x10eb, @0x10ec, @0x10ed, @0x10ee, @0x10ef, @0x10f0, @0x10f1, @0x10f2, @0x10f3, @0x10f4, @0x10f5, @0x10f6, @0x10f7, @0x10f8, @0x10f9, @0x10fa, @0x10fb, @0x10fc, @0x10fd, @0x10fe, @0x10ff
        ];

        // Register 254 games (MAX_GAMES - 1)
        let i = 0;
        while (i < 254) {
            let addr = *vector::borrow(&addrs, i);
            let game_acc = account::create_account_for_test(addr);
            CasinoHouse::register_game(
                &casino_account,
                &game_acc,
                b"G",
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE
            );
            i = i + 1;
        };

        // This 255th registration should fail (next_game_id would be 255 = MAX_GAMES)
        let final_addr = *vector::borrow(&addrs, 254);
        let final_game = account::create_account_for_test(final_addr);
        CasinoHouse::register_game(
            &casino_account,
            &final_game,
            b"Final",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
    }

    //
    // Package Function Tests (Internal)
    //

    #[test]
    fun test_place_bet_internal() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        let bet_id = CasinoHouse::place_bet_internal(coins, @0x123, 1);

        assert!(bet_id == 1, 1);
        assert!(CasinoHouse::treasury_balance() == MIN_BET, 2);
    }

    #[test]
    #[
        expected_failure(
            abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED,
            location = casino::CasinoHouse
        )
    ]
    fun test_place_bet_internal_inactive_game() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );
        CasinoHouse::toggle_game(&casino_account, 1, false);

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        CasinoHouse::place_bet_internal(coins, @0x123, 1);
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
        CasinoHouse::place_bet_internal(coins, @0x123, 99); // Non-existent game_id
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
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET - 1);
        CasinoHouse::place_bet_internal(coins, @0x123, 1);
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
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        let coins = coin::withdraw<AptosCoin>(&casino_account, MAX_BET + 1);
        CasinoHouse::place_bet_internal(coins, @0x123, 1);
    }

    #[test]
    fun test_settle_bet_internal() {
        let (_, casino_account, game_account) = setup_test();
        CasinoHouse::init(&casino_account);
        CasinoHouse::register_game(
            &casino_account,
            &game_account,
            b"Test",
            MIN_BET,
            MAX_BET,
            HOUSE_EDGE
        );

        // Place bet first
        let coins = coin::withdraw<AptosCoin>(&casino_account, MIN_BET);
        let bet_id = CasinoHouse::place_bet_internal(coins, @0x123, 1);

        // Register winner's account
        let winner_addr = signer::address_of(&game_account);
        coin::register<AptosCoin>(&game_account);

        // Settle bet using test helper
        CasinoHouse::test_settle_bet(
            winner_addr,
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

        CasinoHouse::test_settle_bet(
            signer::address_of(&game_account),
            1,
            @0x123,
            0,
            0
        );
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
        CasinoHouse::test_settle_bet(
            signer::address_of(&game_account),
            1,
            @0x123,
            MIN_BET * 2,
            0
        );
    }

    #[test]
    fun test_settle_bet_with_payout() {
        let (_, casino_account, game_account) = setup_test();
        setup_game_and_bet(&casino_account, &game_account);

        let winner = account::create_account_for_test(@0x999);
        coin::register<AptosCoin>(&winner);

        CasinoHouse::test_settle_bet(
            signer::address_of(&game_account),
            1,
            @0x999,
            MIN_BET / 2,
            MIN_BET / 2
        );

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
        CasinoHouse::get_game_info(1);
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
        assert!(CasinoHouse::is_game_active(1) == false, 1);
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
