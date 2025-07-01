//! MIT License
//!
//! Integration Tests for CasinoHouse Module
//!
//! Covers game registration, bet flow, treasury operations, and administrative functions
//! to achieve better code coverage while testing core casino functionality.

#[test_only]
module casino::CasinoHouseIntegrationTests {
    use std::string;
    use std::option;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use aptos_framework::object;
    use casino::CasinoHouse;
    use casino::InvestorToken;
    use dice_game::DiceGame;
    use slot_game::SlotMachine;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @dice_game;
    const SLOT_ADDR: address = @slot_game;
    const UNAUTHORIZED_ADDR: address = @0x9999;
    const FAKE_GAME_ADDR: address = @0x8888;

    // User addresses
    const INVESTOR_ADDR: address = @0x1001;
    const PLAYER_ADDR: address = @0x2001;
    const ADMIN_ADDR: address = @0x3001;

    // Funding amounts
    const LARGE_FUNDING: u64 = 100000000000; // 1000 APT
    const STANDARD_FUNDING: u64 = 10000000000; // 100 APT
    const STANDARD_BET: u64 = 5000000; // 0.05 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 50000000; // 0.5 APT

    fun setup_casino_ecosystem(): (signer, signer, signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let slot_signer = account::create_account_for_test(SLOT_ADDR);
        let investor = account::create_account_for_test(INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);
        let admin = account::create_account_for_test(ADMIN_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[
            CASINO_ADDR,
            DICE_ADDR,
            SLOT_ADDR,
            INVESTOR_ADDR,
            PLAYER_ADDR,
            ADMIN_ADDR
        ];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, DICE_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, SLOT_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, INVESTOR_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, STANDARD_FUNDING);
        aptos_coin::mint(&aptos_framework, ADMIN_ADDR, STANDARD_FUNDING);

        (
            aptos_framework,
            casino_signer,
            dice_signer,
            slot_signer,
            investor,
            player,
            admin
        )
    }

    #[test]
    fun test_bet_flow_and_treasury_operations() {
        let (_, casino_signer, dice_signer, _, investor, player, _) =
            setup_casino_ecosystem();

        // === PHASE 1: SETUP COMPLETE ECOSYSTEM ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1667
        );

        DiceGame::initialize_game(&dice_signer);

        let dice_object =
            object::address_to_object<CasinoHouse::GameMetadata>(
                CasinoHouse::derive_game_object_address(
                    CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
                )
            );

        // === PHASE 2: TEST BET PLACEMENT VALIDATION ===

        // Get initial treasury state
        let initial_central_balance = CasinoHouse::central_treasury_balance();
        let initial_game_balance = CasinoHouse::game_treasury_balance(dice_object);
        let initial_total_balance = CasinoHouse::treasury_balance();

        assert!(initial_central_balance > 0, 1); // Should have investor funds
        assert!(initial_game_balance >= 0, 2);
        assert!(
            initial_total_balance >= initial_central_balance + initial_game_balance,
            3
        );

        // === PHASE 3: TEST TREASURY ROUTING LOGIC ===

        // Place bets to test treasury routing (bet flow goes to game treasury or central based on balance)
        let player_apt_before =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Multiple bets to test different treasury routing scenarios
        let bet_rounds = 10;
        let i = 0;
        while (i < bet_rounds) {
            // This tests the complete bet flow including:
            // - Bet validation (amount within min/max)
            // - Treasury routing decision (game vs central)
            // - BetId creation and event emission
            // - Settlement and payout logic
            DiceGame::test_only_play_dice(&player, (((i % 6) + 1) as u8), STANDARD_BET);
            i = i + 1;
        };

        let player_apt_after =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Player should have spent money (though might have won some back)
        assert!(player_apt_after < player_apt_before, 4);

        // === PHASE 4: TEST TREASURY BALANCE AGGREGATION ===

        let final_central_balance = CasinoHouse::central_treasury_balance();
        let final_game_balance = CasinoHouse::game_treasury_balance(dice_object);
        let final_total_balance = CasinoHouse::treasury_balance();

        // Treasury aggregation should be consistent
        assert!(
            final_total_balance == final_central_balance + final_game_balance,
            5
        );

        // System should remain operational
        assert!(DiceGame::is_ready(), 6);
        assert!(final_total_balance > 0, 7);

        // === PHASE 5: TEST EDGE CASES ===

        // Test minimum bet
        DiceGame::test_only_play_dice(&player, 3, MIN_BET);

        // Test maximum bet (if player has enough funds)
        let current_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        if (current_balance >= MAX_BET) {
            DiceGame::test_only_play_dice(&player, 4, MAX_BET);
        };

        // === PHASE 6: TEST INVESTOR REDEMPTION INTEGRATION ===

        // Test that casino can handle investor redemptions (treasury operations)
        let investor_tokens = InvestorToken::user_balance(INVESTOR_ADDR);
        let redemption_amount = investor_tokens / 10; // Redeem 10%

        let investor_apt_before =
            primary_fungible_store::balance(
                INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::redeem(&investor, redemption_amount);

        let investor_apt_after =
            primary_fungible_store::balance(
                INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        assert!(investor_apt_after > investor_apt_before, 8); // Should receive APT

        // System should remain stable after redemption
        assert!(CasinoHouse::treasury_balance() > 0, 9);
        assert!(DiceGame::is_ready(), 10);
    }

    #[test]
    fun test_administrative_functions_and_comprehensive_coverage() {
        let (_, casino_signer, dice_signer, slot_signer, investor, _, _admin) =
            setup_casino_ecosystem();

        // === PHASE 1: SETUP ECOSYSTEM ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1667
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550
        );

        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        let dice_object =
            object::address_to_object<CasinoHouse::GameMetadata>(
                CasinoHouse::derive_game_object_address(
                    CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
                )
            );
        let slot_object =
            object::address_to_object<CasinoHouse::GameMetadata>(
                CasinoHouse::derive_game_object_address(
                    CASINO_ADDR, string::utf8(b"SlotMachine"), string::utf8(b"v1")
                )
            );

        // === PHASE 2: TEST LIMIT MANAGEMENT ===

        // Test casino admin updating limits
        CasinoHouse::update_game_limits(&casino_signer, dice_object, 2000000, 40000000); // 0.02 - 0.4 APT

        let (_, _, _, new_min, new_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(new_min == 2000000, 1);
        assert!(new_max == 40000000, 2);

        // Test games requesting limit changes (risk reduction only)
        DiceGame::request_limit_update(&dice_signer, 5000000, 35000000); // 0.05 - 0.35 APT

        let (_, _, _, updated_min, updated_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(updated_min == 5000000, 3);
        assert!(updated_max == 35000000, 4);

        // === PHASE 3: TEST VIEW FUNCTIONS COMPREHENSIVELY ===

        // Test all registered games
        let all_games = CasinoHouse::get_registered_games();
        assert!(vector::length(&all_games) == 2, 5);

        // Test game existence and registration status
        assert!(CasinoHouse::game_object_exists(dice_object), 6);
        assert!(CasinoHouse::game_object_exists(slot_object), 7);
        assert!(CasinoHouse::is_game_registered(dice_object), 8);
        assert!(CasinoHouse::is_game_registered(slot_object), 9);

        // Test treasury functions
        let central_balance = CasinoHouse::central_treasury_balance();
        let total_balance = CasinoHouse::treasury_balance();
        let dice_balance = CasinoHouse::game_treasury_balance(dice_object);
        let slot_balance = CasinoHouse::game_treasury_balance(slot_object);

        assert!(central_balance > 0, 10);
        assert!(
            total_balance >= central_balance + dice_balance + slot_balance,
            11
        );

        // Test treasury addresses
        let dice_treasury_addr = CasinoHouse::get_game_treasury_address(dice_object);
        let slot_treasury_addr = CasinoHouse::get_game_treasury_address(slot_object);
        assert!(dice_treasury_addr != slot_treasury_addr, 12);

        // Test treasury configurations
        let (dice_target, dice_overflow, dice_drain, _dice_volume) =
            CasinoHouse::get_game_treasury_config(dice_treasury_addr);
        let (slot_target, slot_overflow, slot_drain, _slot_volume) =
            CasinoHouse::get_game_treasury_config(slot_treasury_addr);

        assert!(dice_target > 0, 13);
        assert!(dice_overflow >= dice_target, 14);
        assert!(dice_drain <= dice_target, 15);
        assert!(slot_target > 0, 16);
        assert!(slot_overflow >= slot_target, 17);
        assert!(slot_drain <= slot_target, 18);

        // === PHASE 4: TEST GAME METADATA DETAILS ===

        let (
            dice_name,
            dice_version,
            dice_addr,
            dice_min_final,
            dice_max_final,
            dice_edge,
            dice_claimed
        ) = CasinoHouse::get_game_metadata(dice_object);

        assert!(dice_name == string::utf8(b"DiceGame"), 19);
        assert!(dice_version == string::utf8(b"v1"), 20);
        assert!(dice_addr == DICE_ADDR, 21);
        assert!(dice_min_final == 5000000, 22); // Updated value
        assert!(dice_max_final == 35000000, 23); // Updated value
        assert!(dice_edge == 1667, 24);
        assert!(dice_claimed, 25); // Should be claimed

        let (
            slot_name, slot_version, slot_addr, slot_min, slot_max, slot_edge, slot_claimed
        ) = CasinoHouse::get_game_metadata(slot_object);

        assert!(slot_name == string::utf8(b"SlotMachine"), 26);
        assert!(slot_version == string::utf8(b"v1"), 27);
        assert!(slot_addr == SLOT_ADDR, 28);
        assert!(slot_min == MIN_BET, 29); // Original value
        assert!(slot_max == MAX_BET, 30); // Original value
        assert!(slot_edge == 1550, 31);
        assert!(slot_claimed, 32); // Should be claimed

        // === PHASE 5: TEST CAPABILITY STATUS FUNCTIONS ===

        assert!(CasinoHouse::is_game_capability_claimed(dice_object), 33);
        assert!(CasinoHouse::is_game_capability_claimed(slot_object), 34);

        // === PHASE 6: TEST OBJECT ADDRESS DERIVATION ===

        let derived_dice_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADDR,
                string::utf8(b"DiceGame"),
                string::utf8(b"v1")
            );
        let actual_dice_addr = object::object_address(&dice_object);
        assert!(derived_dice_addr == actual_dice_addr, 35);

        let derived_slot_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADDR,
                string::utf8(b"SlotMachine"),
                string::utf8(b"v1")
            );
        let actual_slot_addr = object::object_address(&slot_object);
        assert!(derived_slot_addr == actual_slot_addr, 36);

        // === PHASE 7: FINAL SYSTEM VALIDATION ===

        // Ensure system remains operational
        assert!(DiceGame::is_ready(), 37);
        assert!(SlotMachine::is_ready(), 38);
        assert!(CasinoHouse::treasury_balance() > 0, 39);
        assert!(vector::length(&CasinoHouse::get_registered_games()) == 2, 40);
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_unauthorized_game_registration() {
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Try to register game without casino admin - should fail
        CasinoHouse::register_game(
            &unauthorized,
            DICE_ADDR,
            string::utf8(b"UnauthorizedGame"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1500
        );
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_AMOUNT)]
    fun test_invalid_game_limits() {
        let (_, casino_signer, _, _, investor, _, _) = setup_casino_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        // Try to register game with max < min - should fail
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"InvalidGame"),
            string::utf8(b"v1"),
            MAX_BET,
            MIN_BET, // max < min
            1500
        );
    }
}
