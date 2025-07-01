//! MIT License
//!
//! Focused Unit Tests for CasinoHouse Module
//!
//! Tests only business logic that makes sense at unit level:
//! - Initialization validation
//! - Game registration business rules
//! - Limit management validation
//! - View function correctness
//! - Error conditions through public APIs

#[test_only]
module casino::CasinoHouseTests {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::Self;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;

    // Test constants
    const CASINO_ADMIN: address = @casino;
    const GAME_MODULE_1: address = @0x1001;
    const GAME_MODULE_2: address = @0x1002;
    const UNAUTHORIZED_USER: address = @0x2001;

    const INITIAL_FUNDING: u64 = 10000000000; // 100 APT

    /// Minimal setup for business logic testing
    fun setup_basic(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_admin = account::create_account_for_test(CASINO_ADMIN);
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_USER);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        (aptos_framework, casino_admin, unauthorized)
    }

    // ========================================================================================
    // INITIALIZATION BUSINESS LOGIC
    // ========================================================================================

    #[test]
    fun test_init_creates_empty_registries() {
        let (_, casino_admin, _) = setup_basic();

        CasinoHouse::init_module_for_test(&casino_admin);

        // Verify clean initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(CasinoHouse::central_treasury_balance() == 0, 2);

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_init_fails_wrong_admin() {
        let (_, _, unauthorized) = setup_basic();

        CasinoHouse::init_module_for_test(&unauthorized);
    }

    // ========================================================================================
    // GAME REGISTRATION BUSINESS RULES
    // ========================================================================================

    #[test]
    fun test_register_game_creates_complete_setup() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1500 // 15% house edge
        );

        // Verify game is properly registered
        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 1, 1);

        let game_object = *vector::borrow(&games, 0);
        assert!(CasinoHouse::is_game_registered(game_object), 2);
        assert!(CasinoHouse::game_object_exists(game_object), 3);

        // Verify metadata is correct
        let (name, version, module_addr, min_bet, max_bet, house_edge, capability_claimed) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(name == string::utf8(b"TestGame"), 4);
        assert!(version == string::utf8(b"v1"), 5);
        assert!(module_addr == GAME_MODULE_1, 6);
        assert!(min_bet == 1000000, 7);
        assert!(max_bet == 50000000, 8);
        assert!(house_edge == 1500, 9);
        assert!(!capability_claimed, 10);

        // Verify treasury exists
        let treasury_addr = CasinoHouse::get_game_treasury_address(game_object);
        assert!(treasury_addr != @0x0, 11);
        assert!(CasinoHouse::game_treasury_balance(game_object) == 0, 12);
    }

    #[test]
    fun test_register_multiple_games() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Register two different games
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667
        );

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_2,
            string::utf8(b"SlotGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1550
        );

        // Verify both are registered
        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 2, 1);

        let game1 = *vector::borrow(&games, 0);
        let game2 = *vector::borrow(&games, 1);
        assert!(CasinoHouse::is_game_registered(game1), 2);
        assert!(CasinoHouse::is_game_registered(game2), 3);

        // Verify different treasury addresses (Block-STM isolation)
        let treasury1 = CasinoHouse::get_game_treasury_address(game1);
        let treasury2 = CasinoHouse::get_game_treasury_address(game2);
        assert!(treasury1 != treasury2, 4);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_register_game_fails_unauthorized() {
        let (_, casino_admin, unauthorized) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &unauthorized, // Not admin
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_AMOUNT)]
    fun test_register_game_fails_invalid_limits() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            50000000,
            1000000,
            1500 // max < min
        );
    }

    #[test]
    #[expected_failure]
    // Object creation prevents duplicates at framework level
    fun test_register_duplicate_game_fails() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Register once
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        // Try to register same game again - object creation will fail
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
    }

    // ========================================================================================
    // GAME UNREGISTRATION BUSINESS LOGIC
    // ========================================================================================

    #[test]
    fun test_unregister_game_removes_from_registry() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 1, 1);
        let game_object = *vector::borrow(&games, 0);

        CasinoHouse::unregister_game(&casino_admin, game_object);

        // Verify removal
        assert!(!CasinoHouse::is_game_registered(game_object), 2);
        let games_after = CasinoHouse::get_registered_games();
        assert!(vector::length(&games_after) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_unregister_game_fails_unauthorized() {
        let (_, casino_admin, unauthorized) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);

        CasinoHouse::unregister_game(&unauthorized, game_object);
    }

    // Note: Cannot test with fake objects due to Move's object system constraints
    // The unregister function inherently requires valid game objects

    // ========================================================================================
    // LIMIT MANAGEMENT BUSINESS RULES
    // ========================================================================================

    #[test]
    fun test_update_game_limits_changes_metadata() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);

        CasinoHouse::update_game_limits(&casino_admin, game_object, 2000000, 40000000);

        let (_, _, _, min_bet, max_bet, _, _) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(min_bet == 2000000, 1);
        assert!(max_bet == 40000000, 2);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_update_limits_fails_unauthorized() {
        let (_, casino_admin, unauthorized) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);

        CasinoHouse::update_game_limits(&unauthorized, game_object, 2000000, 40000000);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_AMOUNT)]
    fun test_update_limits_fails_invalid_range() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);

        CasinoHouse::update_game_limits(&casino_admin, game_object, 50000000, 1000000); // max < min
    }

    // ========================================================================================
    // VIEW FUNCTION CORRECTNESS
    // ========================================================================================

    #[test]
    fun test_derive_game_object_address_deterministic() {
        // Test deterministic address derivation
        let addr1 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN, string::utf8(b"TestGame"), string::utf8(b"v1")
            );
        let addr2 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN, string::utf8(b"TestGame"), string::utf8(b"v1")
            );
        let addr3 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN,
                string::utf8(b"TestGame"),
                string::utf8(b"v2") // Different version
            );

        assert!(addr1 == addr2, 1); // Same inputs = same address
        assert!(addr1 != addr3, 2); // Different inputs = different address
    }

    #[test]
    fun test_game_object_exists_after_registration() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Register a game
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        // Get the actual game object from registration
        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);

        // Now test that it exists
        assert!(CasinoHouse::game_object_exists(game_object), 1);
        assert!(CasinoHouse::is_game_registered(game_object), 2);
    }

    #[test]
    fun test_treasury_balance_aggregation() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        let initial_total = CasinoHouse::treasury_balance();
        let initial_central = CasinoHouse::central_treasury_balance();
        assert!(initial_total == initial_central, 1); // Initially all in central
        assert!(initial_total == 0, 2); // Initially empty

        // Register games to create game treasuries
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"Game1"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_2,
            string::utf8(b"Game2"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1600
        );

        let games = CasinoHouse::get_registered_games();
        let game1 = *vector::borrow(&games, 0);
        let game2 = *vector::borrow(&games, 1);

        let total_balance = CasinoHouse::treasury_balance();
        let central_balance = CasinoHouse::central_treasury_balance();
        let game1_balance = CasinoHouse::game_treasury_balance(game1);
        let game2_balance = CasinoHouse::game_treasury_balance(game2);

        // Verify aggregation
        assert!(
            total_balance == central_balance + game1_balance + game2_balance,
            3
        );
        assert!(game1_balance == 0, 4); // Game treasuries start empty
        assert!(game2_balance == 0, 5);
    }

    // ========================================================================================
    // ERROR CONDITION VALIDATION
    // ========================================================================================

    // Note: Cannot test treasury functions with fake game objects due to Move's object system
    // These error conditions are validated through integration tests instead

    // ========================================================================================
    // EDGE CASE VALIDATION
    // ========================================================================================

    #[test]
    fun test_zero_house_edge_allowed() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // 0% house edge should be allowed (theoretical fair game)
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"FairGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            0 // 0% house edge
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);
        let (_, _, _, _, _, house_edge, _) = CasinoHouse::get_game_metadata(game_object);
        assert!(house_edge == 0, 1);
    }

    #[test]
    fun test_same_min_max_bet_allowed() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Min = Max should be allowed (fixed bet size)
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"FixedBet"),
            string::utf8(b"v1"),
            10000000,
            10000000,
            1500 // min = max = 0.1 APT
        );

        let games = CasinoHouse::get_registered_games();
        let game_object = *vector::borrow(&games, 0);
        let (_, _, _, min_bet, max_bet, _, _) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(min_bet == max_bet, 1);
        assert!(min_bet == 10000000, 2);
    }
}
