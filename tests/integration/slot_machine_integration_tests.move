//! MIT License
//!
//! Integration Tests for SlotMachine Module
//!
//! Covers slot machine mechanics, initialization edge cases, and administrative functions
//! to achieve better code coverage while testing practical functionality.

#[test_only]
module slot_game::SlotMachineIntegrationTests {
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
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use slot_game::SlotMachine;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const SLOT_ADDR: address = @slot_game;
    const UNAUTHORIZED_ADDR: address = @0x9999;
    const WHALE_INVESTOR_ADDR: address = @0x1001;
    const PLAYER_ADDR: address = @0x2001;

    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT for liquidity
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT for testing
    const STANDARD_BET: u64 = 5000000; // 0.05 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 50000000; // 0.5 APT

    fun setup_slot_ecosystem(): (signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let slot_signer = account::create_account_for_test(SLOT_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[CASINO_ADDR, SLOT_ADDR, WHALE_INVESTOR_ADDR, PLAYER_ADDR];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, SLOT_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, PLAYER_FUNDING);

        (aptos_framework, casino_signer, slot_signer, whale_investor, player)
    }

    #[test]
    fun test_slot_initialization_and_configuration() {
        let (_, casino_signer, slot_signer, whale_investor, _) = setup_slot_ecosystem();

        // === PHASE 1: CASINO SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Provide initial liquidity
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // === PHASE 2: GAME REGISTRATION ===
        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550, // 15.5% house edge
            12_500_000_000
        );

        // === PHASE 3: TEST BEFORE INITIALIZATION ===
        // Verify game is not ready before initialization
        assert!(!SlotMachine::is_initialized(), 1);
        assert!(!SlotMachine::is_ready(), 2);

        // === PHASE 4: SUCCESSFUL INITIALIZATION ===
        SlotMachine::initialize_game(&slot_signer);

        // Verify initialization success
        assert!(SlotMachine::is_initialized(), 3);
        assert!(SlotMachine::is_registered(), 4);
        assert!(SlotMachine::is_ready(), 5);
        assert!(SlotMachine::object_exists(), 6);

        // === PHASE 5: VERIFY CONFIGURATION ===
        let (min_bet, max_bet, house_edge) = SlotMachine::get_game_config();
        assert!(min_bet == MIN_BET, 7);
        assert!(max_bet == MAX_BET, 8);
        assert!(house_edge == 1550, 9);

        // Verify symbol weights
        let (cherry_w, bell_w, coin_w, chain_w, seven_w) =
            SlotMachine::get_symbol_weights();
        assert!(cherry_w == 40, 10);
        assert!(bell_w == 30, 11);
        assert!(coin_w == 20, 12);
        assert!(chain_w == 8, 13);
        assert!(seven_w == 2, 14);

        // Verify payout multipliers
        let (cherry_p, bell_p, coin_p, chain_p, seven_p) =
            SlotMachine::get_payout_multipliers();
        assert!(cherry_p == 1, 15);
        assert!(bell_p == 2, 16);
        assert!(coin_p == 5, 17);
        assert!(chain_p == 20, 18);
        assert!(seven_p == 100, 19);

        // === PHASE 6: VERIFY TREASURY INTEGRATION ===
        let treasury_balance = SlotMachine::game_treasury_balance();
        assert!(treasury_balance >= 0, 20); // Should exist

        let treasury_addr = SlotMachine::game_treasury_address();
        assert!(treasury_addr != @0x0, 21); // Should have valid address

        let (target_reserve, overflow_threshold, drain_threshold, rolling_volume) =
            SlotMachine::game_treasury_config();
        assert!(target_reserve > 0, 22);
        assert!(overflow_threshold >= target_reserve, 23);
        assert!(drain_threshold <= target_reserve, 24);
        assert!(rolling_volume >= 0, 25);

        // === PHASE 7: VERIFY GAME INFO ===
        let (creator, game_object, game_name, version) = SlotMachine::get_game_info();
        assert!(creator == SLOT_ADDR, 26);
        assert!(game_name == string::utf8(b"SlotMachine"), 27);
        assert!(version == string::utf8(b"v1"), 28);

        let casino_game_obj = SlotMachine::get_casino_game_object();
        assert!(game_object == casino_game_obj, 29);

        // === PHASE 8: VERIFY PAYOUT CAPACITY ===
        assert!(SlotMachine::can_handle_payout(STANDARD_BET), 30);
        assert!(SlotMachine::can_handle_payout(MAX_BET), 31);
    }

    #[test]
    fun test_slot_symbol_mechanics_and_payouts() {
        let (_, casino_signer, slot_signer, whale_investor, player) =
            setup_slot_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // === PHASE 1: TEST SYMBOL PAYOUT CALCULATIONS ===

        // Test each symbol payout calculation
        let cherry_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 1);
        assert!(cherry_payout == STANDARD_BET * 1, 1); // 1x multiplier

        let bell_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 2);
        assert!(bell_payout == STANDARD_BET * 2, 2); // 2x multiplier

        let coin_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 3);
        assert!(coin_payout == STANDARD_BET * 5, 3); // 5x multiplier

        let chain_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 4);
        assert!(chain_payout == STANDARD_BET * 20, 4); // 20x multiplier

        let seven_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 5);
        assert!(seven_payout == STANDARD_BET * 100, 5); // 100x multiplier

        let unknown_payout = SlotMachine::calculate_symbol_payout(STANDARD_BET, 99);
        assert!(unknown_payout == 0, 6); // Unknown symbol = 0

        // === PHASE 2: TEST SYMBOL NAMES ===

        assert!(SlotMachine::get_symbol_name(1) == b"Cherry", 7);
        assert!(SlotMachine::get_symbol_name(2) == b"Bell", 8);
        assert!(SlotMachine::get_symbol_name(3) == b"Coin", 9);
        assert!(SlotMachine::get_symbol_name(4) == b"Chain", 10);
        assert!(SlotMachine::get_symbol_name(5) == b"Seven", 11);
        assert!(SlotMachine::get_symbol_name(99) == b"Unknown", 12);

        // === PHASE 3: TEST EXTENSIVE GAMEPLAY TO TRIGGER DIFFERENT OUTCOMES ===

        let initial_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Spin many times to potentially hit different symbol combinations
        // This will exercise the internal payout calculation logic
        let spins = 50; // Enough to likely hit different combinations
        let bet_per_spin = 2000000; // 0.02 APT per spin
        let total_bet_amount = spins * bet_per_spin;

        // Ensure player has enough funds
        assert!(initial_balance >= total_bet_amount, 13);

        let i = 0;
        while (i < spins) {
            SlotMachine::test_only_spin_slots(&player, bet_per_spin);
            i = i + 1;
        };

        // Verify player balance changed (some bets were made)
        let final_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        assert!(final_balance < initial_balance, 14); // Should have spent some money

        // Verify game can still handle payouts after extensive play
        assert!(SlotMachine::can_handle_payout(MAX_BET), 15);

        // === PHASE 4: TEST EDGE CASE BETS ===

        // Test minimum bet
        SlotMachine::test_only_spin_slots(&player, MIN_BET);

        // Test maximum bet (if player has enough funds)
        let current_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        if (current_balance >= MAX_BET) {
            SlotMachine::test_only_spin_slots(&player, MAX_BET);
        };

        // Verify system stability after all testing
        assert!(SlotMachine::is_ready(), 16);
        assert!(CasinoHouse::treasury_balance() > 0, 17);
    }

    #[test]
    fun test_slot_administrative_functions_and_error_conditions() {
        let (_, casino_signer, slot_signer, whale_investor, _) = setup_slot_ecosystem();

        // Setup ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // === PHASE 1: TEST ADMINISTRATIVE LIMIT UPDATES ===

        // Test valid limit update (reducing risk: higher min, lower max)
        SlotMachine::request_limit_update(&slot_signer, 2000000, 40000000); // 0.02 APT min, 0.4 APT max

        // Verify limits were updated in casino metadata
        let casino_game_obj = SlotMachine::get_casino_game_object();
        let (_, _, _, min_bet, max_bet, _, _slot_payout1, _) =
            CasinoHouse::get_game_metadata(casino_game_obj);
        assert!(min_bet == 2000000, 1);
        assert!(max_bet == 40000000, 2);

        // Test another valid update (further risk reduction)
        SlotMachine::request_limit_update(&slot_signer, 5000000, 35000000); // 0.05 APT min, 0.35 APT max

        let (_, _, _, min_bet2, max_bet2, _, _slot_payout2, _) =
            CasinoHouse::get_game_metadata(casino_game_obj);
        assert!(min_bet2 == 5000000, 3);
        assert!(max_bet2 == 35000000, 4);

        // === PHASE 2: TEST OBJECT ADDRESS DERIVATION ===

        let derived_addr =
            SlotMachine::derive_game_object_address(
                SLOT_ADDR,
                string::utf8(b"SlotMachine"),
                string::utf8(b"v1")
            );
        let actual_addr = SlotMachine::get_game_object_address();
        assert!(derived_addr == actual_addr, 5);

        // Test with different parameters
        let different_addr =
            SlotMachine::derive_game_object_address(
                SLOT_ADDR,
                string::utf8(b"SlotMachine"),
                string::utf8(b"v2") // Different version
            );
        assert!(different_addr != actual_addr, 6);

        // === PHASE 3: TEST VIEW FUNCTIONS WITH COMPREHENSIVE COVERAGE ===

        // Test all view functions to ensure they work correctly
        let (min_bet_view, max_bet_view, house_edge_view) =
            SlotMachine::get_game_config();
        assert!(min_bet_view >= MIN_BET, 7); // Should be at least original min
        assert!(max_bet_view <= MAX_BET, 8); // Should be at most original max
        assert!(house_edge_view == 1550, 9);

        // Test game status functions
        assert!(SlotMachine::is_initialized(), 10);
        assert!(SlotMachine::is_registered(), 11);
        assert!(SlotMachine::is_ready(), 12);
        assert!(SlotMachine::object_exists(), 13);

        // Test treasury-related functions
        let treasury_balance = SlotMachine::game_treasury_balance();
        let treasury_addr = SlotMachine::game_treasury_address();
        assert!(treasury_balance >= 0, 14);
        assert!(treasury_addr != @0x0, 15);

        // Test payout capacity with current limits
        assert!(SlotMachine::can_handle_payout(min_bet_view), 16);
        assert!(SlotMachine::can_handle_payout(max_bet_view), 17);

        // Test casino game object consistency
        let casino_game_obj_view = SlotMachine::get_casino_game_object();
        assert!(object::object_address(&casino_game_obj_view) != @0x0, 18);

        // Test game info consistency
        let (creator_info, game_object_info, name_info, version_info) =
            SlotMachine::get_game_info();
        assert!(creator_info == SLOT_ADDR, 19);
        assert!(name_info == string::utf8(b"SlotMachine"), 20);
        assert!(version_info == string::utf8(b"v1"), 21);
        assert!(game_object_info == casino_game_obj_view, 22);

        // === PHASE 4: STRESS TEST THE SYSTEM ===

        // Verify system remains stable after all administrative operations
        assert!(CasinoHouse::is_game_registered(casino_game_obj), 23);
        assert!(CasinoHouse::treasury_balance() > 0, 24);
        assert!(SlotMachine::is_ready(), 25);
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_UNAUTHORIZED)]
    fun test_unauthorized_initialization() {
        let (_, casino_signer, _, whale_investor, _) = setup_slot_ecosystem();
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Setup casino
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        // Try to initialize with wrong signer - should fail
        SlotMachine::initialize_game(&unauthorized);
    }

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_ALREADY_INITIALIZED)]
    fun test_double_initialization() {
        let (_, casino_signer, slot_signer, whale_investor, _) = setup_slot_ecosystem();

        // Setup casino and initialize once
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // Try to initialize again - should fail
        SlotMachine::initialize_game(&slot_signer);
    }

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_low() {
        let (_, casino_signer, slot_signer, whale_investor, player) =
            setup_slot_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // Try to bet below minimum - should fail
        SlotMachine::test_only_spin_slots(&player, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_high() {
        let (_, casino_signer, slot_signer, whale_investor, player) =
            setup_slot_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // Try to bet above maximum - should fail
        SlotMachine::test_only_spin_slots(&player, MAX_BET + 1);
    }

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_UNAUTHORIZED)]
    fun test_unauthorized_limit_update() {
        let (_, casino_signer, slot_signer, whale_investor, _) = setup_slot_ecosystem();
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // Try to update limits with unauthorized signer - should fail
        SlotMachine::request_limit_update(&unauthorized, 2000000, 40000000);
    }

    #[test]
    #[expected_failure(abort_code = slot_game::SlotMachine::E_INVALID_AMOUNT)]
    fun test_invalid_limit_update_range() {
        let (_, casino_signer, slot_signer, whale_investor, _) = setup_slot_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1550,
            12_500_000_000
        );

        SlotMachine::initialize_game(&slot_signer);

        // Try to set max < min - should fail
        SlotMachine::request_limit_update(&slot_signer, 40000000, 20000000);
    }
}
