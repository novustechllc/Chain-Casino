//! MIT License
//!
//! Unit Tests for CasinoHouse Module
//!
//! Following unit testing best practices:
//! - Fast execution with minimal setup
//! - Test single functionality in isolation
//! - Clear descriptive test names
//! - Arrange-Act-Assert pattern
//! - Both happy path and edge cases
//! - Comprehensive error condition testing

#[test_only]
module casino::CasinoHouseUnitTests {
    use std::string;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::object;
    use aptos_framework::fungible_asset;
    use casino::CasinoHouse;

    // Test constants
    const CASINO_ADMIN: address = @casino;
    const GAME_MODULE_1: address = @0x1001;
    const GAME_MODULE_2: address = @0x1002;
    const UNAUTHORIZED_USER: address = @0x2001;

    const INITIAL_FUNDING: u64 = 10000000000; // 100 APT
    const TEST_BET_AMOUNT: u64 = 50000000; // 0.5 APT
    const TEST_PAYOUT: u64 = 250000000; // 2.5 APT (5x bet)

    /// Minimal test setup - fast and isolated
    fun setup_basic_test(): (signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_admin = account::create_account_for_test(CASINO_ADMIN);
        let game_module_1 = account::create_account_for_test(GAME_MODULE_1);
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_USER);

        // Minimal Aptos setup
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        // Setup stores
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        primary_fungible_store::ensure_primary_store_exists(
            CASINO_ADMIN, aptos_metadata
        );
        primary_fungible_store::ensure_primary_store_exists(
            GAME_MODULE_1, aptos_metadata
        );
        primary_fungible_store::ensure_primary_store_exists(
            UNAUTHORIZED_USER, aptos_metadata
        );

        // Minimal funding
        aptos_coin::mint(&aptos_framework, CASINO_ADMIN, INITIAL_FUNDING);
        aptos_coin::mint(&aptos_framework, GAME_MODULE_1, INITIAL_FUNDING);

        (aptos_framework, casino_admin, game_module_1, unauthorized)
    }

    /// Setup with treasury funding for bet testing
    fun setup_with_treasury(): (signer, signer, signer) {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();

        CasinoHouse::init_module_for_test(&casino_admin);

        // Add substantial treasury funding
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let funding_fa =
            primary_fungible_store::withdraw(
                &casino_admin, aptos_metadata, INITIAL_FUNDING
            );
        CasinoHouse::deposit_to_treasury(funding_fa);

        (casino_admin, game_module_1, game_module_1)
        // reuse for player
    }

    // ========================================================================================
    // INITIALIZATION TESTS
    // ========================================================================================

    #[test]
    fun test_init_module_creates_all_resources() {
        let (_, casino_admin, _, _) = setup_basic_test();

        // Act
        CasinoHouse::init_module_for_test(&casino_admin);

        // Assert - verify all registries exist
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(CasinoHouse::central_treasury_balance() == 0, 2);

        // Registry should be empty initially
        let games = CasinoHouse::get_registered_games();
        assert!(std::vector::length(&games) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_init_module_fails_with_wrong_signer() {
        let (_, _, game_module_1, _) = setup_basic_test();

        // Act & Assert - should fail
        CasinoHouse::init_module_for_test(&game_module_1); // Not casino admin
    }

    // ========================================================================================
    // GAME REGISTRATION TESTS
    // ========================================================================================

    #[test]
    fun test_register_game_success() {
        let (_, casino_admin, _, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Act
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT
            50000000, // 0.5 APT
            1500 // 15% house edge
        );

        // Assert
        let games = CasinoHouse::get_registered_games();
        assert!(std::vector::length(&games) == 1, 1);

        let game_object = *std::vector::borrow(&games, 0);
        assert!(CasinoHouse::is_game_registered(game_object), 2);

        let (name, version, module_addr, min_bet, max_bet, house_edge, capability_claimed) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(name == string::utf8(b"TestGame"), 3);
        assert!(version == string::utf8(b"v1"), 4);
        assert!(module_addr == GAME_MODULE_1, 5);
        assert!(min_bet == 1000000, 6);
        assert!(max_bet == 50000000, 7);
        assert!(house_edge == 1500, 8);
        assert!(!capability_claimed, 9); // Should not be claimed yet
    }

    #[test]
    fun test_register_game_creates_treasury() {
        let (_, casino_admin, _, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Act
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        // Assert - treasury should be created
        let games = CasinoHouse::get_registered_games();
        let game_object = *std::vector::borrow(&games, 0);

        let treasury_addr = CasinoHouse::get_game_treasury_address(game_object);
        assert!(treasury_addr != @0x0, 1); // Should have valid address

        let game_balance = CasinoHouse::game_treasury_balance(game_object);
        assert!(game_balance == 0, 2); // Initially empty

        let (target_reserve, overflow_threshold, drain_threshold, rolling_volume) =
            CasinoHouse::get_game_treasury_config(treasury_addr);
        assert!(target_reserve > 0, 3);
        assert!(overflow_threshold > target_reserve, 4);
        assert!(drain_threshold < target_reserve, 5);
        assert!(rolling_volume == 0, 6); // Initially zero
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_register_game_fails_unauthorized() {
        let (_, casino_admin, _, unauthorized) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Act & Assert
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
        let (_, casino_admin, _, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Act & Assert - max < min should fail
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
    #[expected_failure(abort_code = casino::CasinoHouse::E_GAME_ALREADY_REGISTERED)]
    fun test_register_duplicate_game_fails() {
        let (_, casino_admin, _, _) = setup_basic_test();
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

        // Try to register same game again - should fail
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
    // CAPABILITY MANAGEMENT TESTS
    // ========================================================================================

    #[test]
    fun test_get_game_capability_success() {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Register game
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
        let game_object = *std::vector::borrow(&games, 0);

        // Act
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Assert - capability should be valid and metadata updated
        assert!(CasinoHouse::is_game_capability_claimed(game_object), 1);

        // Capability should contain correct game object
        // Note: We can't directly inspect capability contents due to Move privacy,
        // but we can verify the claim was recorded
        let (_, _, _, _, _, _, capability_claimed) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(capability_claimed, 2);

        // Cleanup - capabilities must be handled
        let CasinoHouse::GameCapability { game_object: _ } = capability;
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED)]
    fun test_get_capability_fails_unregistered_game() {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Create fake game object address
        let fake_game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(@0x999);

        // Act & Assert
        let _capability =
            CasinoHouse::get_game_capability(&game_module_1, fake_game_object);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_get_capability_fails_wrong_module() {
        let (_, casino_admin, game_module_1, unauthorized) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);

        // Act & Assert - wrong signer should fail
        let _capability = CasinoHouse::get_game_capability(&unauthorized, game_object);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_CAPABILITY_ALREADY_CLAIMED)]
    fun test_get_capability_twice_fails() {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);

        // First claim succeeds
        let capability1 = CasinoHouse::get_game_capability(&game_module_1, game_object);
        let CasinoHouse::GameCapability { game_object: _ } = capability1;

        // Second claim should fail
        let _capability2 = CasinoHouse::get_game_capability(&game_module_1, game_object);
    }

    // ========================================================================================
    // BET PLACEMENT TESTS
    // ========================================================================================

    #[test]
    fun test_place_bet_success() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

        // Register and setup game
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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Prepare bet
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);

        // Act
        let bet_id = CasinoHouse::place_bet(&capability, bet_fa, player_addr, TEST_PAYOUT);

        // Assert
        assert!(bet_id > 0, 1); // Should get valid bet ID

        // Treasury balance should increase
        let treasury_balance = CasinoHouse::treasury_balance();
        assert!(treasury_balance >= TEST_BET_AMOUNT, 2);

        // Cleanup capability
        let CasinoHouse::GameCapability { game_object: _ } = capability;
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED)]
    fun test_place_bet_fails_unregistered_game() {
        let (casino_admin, _, player) = setup_with_treasury();

        // Create fake capability (this would normally be impossible in real usage)
        let fake_game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(@0x999);
        let fake_capability = CasinoHouse::GameCapability { game_object: fake_game_object };

        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);

        // Act & Assert
        let _bet_id =
            CasinoHouse::place_bet(
                &fake_capability,
                bet_fa,
                player_addr,
                TEST_PAYOUT
            );
    }

    #[test]
    #[expected_failure(
        abort_code = casino::CasinoHouse::E_INSUFFICIENT_TREASURY_FOR_PAYOUT
    )]
    fun test_place_bet_fails_insufficient_treasury() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);

        // Try to bet with payout exceeding treasury
        let excessive_payout = INITIAL_FUNDING * 2; // More than treasury has

        // Act & Assert
        let _bet_id =
            CasinoHouse::place_bet(
                &capability,
                bet_fa,
                player_addr,
                excessive_payout
            );
    }

    // ========================================================================================
    // BET SETTLEMENT TESTS
    // ========================================================================================

    #[test]
    fun test_settle_bet_win_success() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Place bet
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);
        let bet_id = CasinoHouse::place_bet(&capability, bet_fa, player_addr, TEST_PAYOUT);

        // Record player balance before settlement
        let player_balance_before =
            primary_fungible_store::balance(player_addr, aptos_metadata);

        // Act - settle with full payout (player wins)
        CasinoHouse::settle_bet(&capability, bet_id, player_addr, TEST_PAYOUT);

        // Assert
        let player_balance_after =
            primary_fungible_store::balance(player_addr, aptos_metadata);
        assert!(
            player_balance_after == player_balance_before + TEST_PAYOUT,
            1
        );

        // Cleanup
        let CasinoHouse::GameCapability { game_object: _ } = capability;
    }

    #[test]
    fun test_settle_bet_loss_success() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Place bet
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);
        let bet_id = CasinoHouse::place_bet(&capability, bet_fa, player_addr, TEST_PAYOUT);

        let player_balance_before =
            primary_fungible_store::balance(player_addr, aptos_metadata);

        // Act - settle with zero payout (player loses)
        CasinoHouse::settle_bet(&capability, bet_id, player_addr, 0);

        // Assert - player balance unchanged (no payout)
        let player_balance_after =
            primary_fungible_store::balance(player_addr, aptos_metadata);
        assert!(player_balance_after == player_balance_before, 1);

        // Cleanup
        let CasinoHouse::GameCapability { game_object: _ } = capability;
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_SETTLEMENT)]
    fun test_settle_bet_fails_invalid_bet_id() {
        let (casino_admin, game_module_1, _) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Act & Assert - settle non-existent bet
        CasinoHouse::settle_bet(&capability, 999, @0x123, 0);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_BET_ALREADY_SETTLED)]
    fun test_settle_bet_twice_fails() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Place bet
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);
        let bet_id = CasinoHouse::place_bet(&capability, bet_fa, player_addr, TEST_PAYOUT);

        // Settle once
        CasinoHouse::settle_bet(&capability, bet_id, player_addr, 0);

        // Try to settle again - should fail
        CasinoHouse::settle_bet(&capability, bet_id, player_addr, TEST_PAYOUT);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_PAYOUT_EXCEEDS_EXPECTED)]
    fun test_settle_bet_fails_excessive_payout() {
        let (casino_admin, game_module_1, player) = setup_with_treasury();

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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Place bet
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let bet_fa =
            primary_fungible_store::withdraw(&player, aptos_metadata, TEST_BET_AMOUNT);
        let player_addr = std::signer::address_of(&player);
        let bet_id = CasinoHouse::place_bet(&capability, bet_fa, player_addr, TEST_PAYOUT);

        // Try to settle with more than expected payout
        CasinoHouse::settle_bet(
            &capability,
            bet_id,
            player_addr,
            TEST_PAYOUT + 1
        );
    }

    // ========================================================================================
    // LIMIT MANAGEMENT TESTS
    // ========================================================================================

    #[test]
    fun test_update_game_limits_success() {
        let (_, casino_admin, _, _) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);

        // Act
        CasinoHouse::update_game_limits(&casino_admin, game_object, 2000000, 40000000);

        // Assert
        let (_, _, _, min_bet, max_bet, _, _) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(min_bet == 2000000, 1);
        assert!(max_bet == 40000000, 2);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_update_limits_fails_unauthorized() {
        let (_, casino_admin, _, unauthorized) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);

        // Act & Assert
        CasinoHouse::update_game_limits(&unauthorized, game_object, 2000000, 40000000);
    }

    #[test]
    fun test_request_limit_update_reduce_risk() {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Act - game requests more conservative limits
        CasinoHouse::request_limit_update(&capability, 2000000, 40000000); // Increase min, decrease max

        // Assert
        let (_, _, _, min_bet, max_bet, _, _) =
            CasinoHouse::get_game_metadata(game_object);
        assert!(min_bet == 2000000, 1); // Increased (more conservative)
        assert!(max_bet == 40000000, 2); // Decreased (more conservative)

        // Cleanup
        let CasinoHouse::GameCapability { game_object: _ } = capability;
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_AMOUNT)]
    fun test_request_limit_update_fails_increase_risk() {
        let (_, casino_admin, game_module_1, _) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);
        let capability = CasinoHouse::get_game_capability(&game_module_1, game_object);

        // Act & Assert - try to decrease min (increase risk) should fail
        CasinoHouse::request_limit_update(&capability, 500000, 40000000); // Decrease min = more risk
    }

    // ========================================================================================
    // TREASURY OPERATION TESTS
    // ========================================================================================

    #[test]
    fun test_treasury_balance_aggregation() {
        let (casino_admin, game_module_1, _) = setup_with_treasury();

        // Register two games to test aggregation
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
        let game1 = *std::vector::borrow(&games, 0);
        let game2 = *std::vector::borrow(&games, 1);

        // Check initial balances
        let total_balance = CasinoHouse::treasury_balance();
        let central_balance = CasinoHouse::central_treasury_balance();
        let game1_balance = CasinoHouse::game_treasury_balance(game1);
        let game2_balance = CasinoHouse::game_treasury_balance(game2);

        // Assert aggregation is correct
        assert!(
            total_balance == central_balance + game1_balance + game2_balance,
            1
        );
        assert!(central_balance == INITIAL_FUNDING, 2); // All funds in central initially
        assert!(game1_balance == 0, 3); // Game treasuries start empty
        assert!(game2_balance == 0, 4);
    }

    #[test]
    fun test_derive_game_object_address() {
        // Test deterministic address derivation
        let addr1 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN,
                string::utf8(b"TestGame"),
                string::utf8(b"v1")
            );

        let addr2 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN,
                string::utf8(b"TestGame"),
                string::utf8(b"v1")
            );

        let addr3 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN,
                string::utf8(b"TestGame"),
                string::utf8(b"v2") // Different version
            );

        // Same inputs should give same address
        assert!(addr1 == addr2, 1);

        // Different inputs should give different address
        assert!(addr1 != addr3, 2);
    }

    // ========================================================================================
    // VIEW FUNCTION TESTS
    // ========================================================================================

    #[test]
    fun test_game_object_exists() {
        let (_, casino_admin, _, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Before registration
        let game_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN, string::utf8(b"TestGame"), string::utf8(b"v1")
            );
        let game_object = object::address_to_object<CasinoHouse::GameMetadata>(game_addr);
        assert!(!CasinoHouse::game_object_exists(game_object), 1);

        // After registration
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        assert!(CasinoHouse::game_object_exists(game_object), 2);
    }

    #[test]
    fun test_treasury_composition() {
        let (casino_admin, _, _) = setup_with_treasury();

        // Should start with all funds in central
        let central = CasinoHouse::central_treasury_balance();
        let total = CasinoHouse::treasury_balance();

        assert!(central == INITIAL_FUNDING, 1);
        assert!(total == INITIAL_FUNDING, 2);
        assert!(central == total, 3); // All in central, no game treasuries yet
    }

    // ========================================================================================
    // UNREGISTRATION TESTS
    // ========================================================================================

    #[test]
    fun test_unregister_game_success() {
        let (_, casino_admin, _, _) = setup_basic_test();
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
        assert!(std::vector::length(&games) == 1, 1);

        let game_object = *std::vector::borrow(&games, 0);
        assert!(CasinoHouse::is_game_registered(game_object), 2);

        // Act
        CasinoHouse::unregister_game(&casino_admin, game_object);

        // Assert
        assert!(!CasinoHouse::is_game_registered(game_object), 3);

        let games_after = CasinoHouse::get_registered_games();
        assert!(std::vector::length(&games_after) == 0, 4);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_unregister_game_fails_unauthorized() {
        let (_, casino_admin, _, unauthorized) = setup_basic_test();
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
        let game_object = *std::vector::borrow(&games, 0);

        // Act & Assert
        CasinoHouse::unregister_game(&unauthorized, game_object);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_GAME_NOT_REGISTERED)]
    fun test_unregister_game_fails_not_registered() {
        let (_, casino_admin, _, _) = setup_basic_test();
        CasinoHouse::init_module_for_test(&casino_admin);

        let fake_game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(@0x999);

        // Act & Assert
        CasinoHouse::unregister_game(&casino_admin, fake_game_object);
    }
}
