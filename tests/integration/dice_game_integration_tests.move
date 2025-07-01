//! MIT License
//!
//! Integration Tests for DiceGame Module
//!
//! Covers dice game mechanics, initialization edge cases, and administrative functions
//! to achieve better code coverage while testing dice-specific functionality.

#[test_only]
module dice_game::DiceGameIntegrationTests {
    use std::string;
    use std::option;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use dice_game::DiceGame;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @dice_game;
    const UNAUTHORIZED_ADDR: address = @0x9999;
    const WHALE_INVESTOR_ADDR: address = @0x1001;
    const PLAYER_ADDR: address = @0x2001;
    const PLAYER2_ADDR: address = @0x2002;

    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT for liquidity
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT for testing
    const STANDARD_BET: u64 = 5000000; // 0.05 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 50000000; // 0.5 APT
    const PAYOUT_MULTIPLIER: u64 = 5; // 5x payout for correct guess

    fun setup_dice_ecosystem(): (signer, signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);
        let player2 = account::create_account_for_test(PLAYER2_ADDR);

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
            WHALE_INVESTOR_ADDR,
            PLAYER_ADDR,
            PLAYER2_ADDR
        ];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, DICE_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, PLAYER2_ADDR, PLAYER_FUNDING);

        (aptos_framework, casino_signer, dice_signer, whale_investor, player, player2)
    }

    #[test]
    fun test_dice_initialization_and_configuration() {
        let (_, casino_signer, dice_signer, whale_investor, _, _) =
            setup_dice_ecosystem();

        // === PHASE 1: CASINO SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Provide initial liquidity
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // === PHASE 2: GAME REGISTRATION ===
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1667 // 16.67% house edge
        );

        // === PHASE 3: TEST BEFORE INITIALIZATION ===
        // Verify game is not ready before initialization
        assert!(!DiceGame::is_initialized(), 1);
        assert!(!DiceGame::is_ready(), 2);

        // === PHASE 4: SUCCESSFUL INITIALIZATION ===
        DiceGame::initialize_game(&dice_signer);

        // Verify initialization success
        assert!(DiceGame::is_initialized(), 3);
        assert!(DiceGame::is_registered(), 4);
        assert!(DiceGame::is_ready(), 5);
        assert!(DiceGame::object_exists(), 6);

        // === PHASE 5: VERIFY GAME CONFIGURATION ===
        let (min_bet, max_bet, payout_mult, house_edge) = DiceGame::get_game_config();
        assert!(min_bet == MIN_BET, 7);
        assert!(max_bet == MAX_BET, 8);
        assert!(payout_mult == PAYOUT_MULTIPLIER, 9);
        assert!(house_edge == 1667, 10);

        // === PHASE 6: VERIFY PAYOUT CALCULATIONS ===
        let test_bet = 10000000; // 0.1 APT
        let expected_payout = DiceGame::calculate_payout(test_bet);
        assert!(
            expected_payout == test_bet * PAYOUT_MULTIPLIER,
            11
        );

        let min_payout = DiceGame::calculate_payout(MIN_BET);
        assert!(min_payout == MIN_BET * PAYOUT_MULTIPLIER, 12);

        let max_payout = DiceGame::calculate_payout(MAX_BET);
        assert!(max_payout == MAX_BET * PAYOUT_MULTIPLIER, 13);

        // === PHASE 7: VERIFY TREASURY INTEGRATION ===
        let treasury_balance = DiceGame::game_treasury_balance();
        assert!(treasury_balance >= 0, 14);

        let treasury_addr = DiceGame::game_treasury_address();
        assert!(treasury_addr != @0x0, 15);

        let (target_reserve, overflow_threshold, drain_threshold, rolling_volume) =
            DiceGame::game_treasury_config();
        assert!(target_reserve > 0, 16);
        assert!(overflow_threshold >= target_reserve, 17);
        assert!(drain_threshold <= target_reserve, 18);
        assert!(rolling_volume >= 0, 19);

        // === PHASE 8: VERIFY GAME INFO AND OBJECTS ===
        let (creator, game_object, game_name, version) = DiceGame::get_game_info();
        assert!(creator == DICE_ADDR, 20);
        assert!(game_name == string::utf8(b"DiceGame"), 21);
        assert!(version == string::utf8(b"v1"), 22);

        let casino_game_obj = DiceGame::get_casino_game_object();
        assert!(game_object == casino_game_obj, 23);

        // === PHASE 9: VERIFY PAYOUT CAPACITY ===
        assert!(DiceGame::can_handle_payout(STANDARD_BET), 24);
        assert!(DiceGame::can_handle_payout(MAX_BET), 25);

        // Test with larger amounts
        let large_bet = MAX_BET / 2;
        assert!(DiceGame::can_handle_payout(large_bet), 26);

        // === PHASE 10: VERIFY OBJECT ADDRESS DERIVATION ===
        let derived_addr =
            DiceGame::derive_game_object_address(
                DICE_ADDR,
                string::utf8(b"DiceGame"),
                string::utf8(b"v1")
            );
        let actual_addr = DiceGame::get_game_object_address();
        assert!(derived_addr == actual_addr, 27);

        // Test different parameters give different addresses
        let different_addr =
            DiceGame::derive_game_object_address(
                DICE_ADDR,
                string::utf8(b"DiceGame"),
                string::utf8(b"v2") // Different version
            );
        assert!(different_addr != actual_addr, 28);
    }

    #[test]
    fun test_dice_gameplay_mechanics_and_all_guesses() {
        let (_, casino_signer, dice_signer, whale_investor, player, player2) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // === PHASE 1: TEST ALL VALID GUESS VALUES (1-6) ===

        let initial_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Test each possible dice guess (1 through 6)
        let guess = 1;
        while (guess <= 6) {
            DiceGame::test_only_play_dice(&player, (guess as u8), STANDARD_BET);
            guess = guess + 1;
        };

        // Verify player balance changed (6 bets were made)
        let balance_after_guesses =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        assert!(balance_after_guesses < initial_balance, 1);

        // === PHASE 2: TEST BOUNDARY BET AMOUNTS ===

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

        // Test mid-range bets
        if (current_balance >= 25000000) { // 0.25 APT
            DiceGame::test_only_play_dice(&player, 5, 25000000);
        };

        // === PHASE 3: EXTENSIVE GAMEPLAY TO TEST WIN/LOSE SCENARIOS ===

        // Multiple rounds to test both winning and losing scenarios
        // Due to randomness, we'll get a mix of wins and losses
        let extensive_rounds = 30;
        let bet_per_round = 2000000; // 0.02 APT

        let player2_initial =
            primary_fungible_store::balance(
                PLAYER2_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Ensure sufficient funds
        let total_needed = extensive_rounds * bet_per_round;
        assert!(player2_initial >= total_needed, 2);

        let round = 0;
        while (round < extensive_rounds) {
            // Cycle through different guesses to increase variety
            let current_guess = ((round % 6) + 1) as u8;
            DiceGame::test_only_play_dice(&player2, current_guess, bet_per_round);
            round = round + 1;
        };

        let player2_final =
            primary_fungible_store::balance(
                PLAYER2_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Player 2 should have spent money (though might have won some back)
        assert!(player2_final < player2_initial, 3);

        // === PHASE 4: VERIFY SYSTEM STABILITY AFTER EXTENSIVE PLAY ===

        // Game should remain operational
        assert!(DiceGame::is_ready(), 4);
        assert!(CasinoHouse::treasury_balance() > 0, 5);

        // Payout capacity should still be available
        assert!(DiceGame::can_handle_payout(MAX_BET), 6);

        // Treasury should have reasonable balance
        let final_treasury = DiceGame::game_treasury_balance();
        assert!(final_treasury >= 0, 7);

        // === PHASE 5: TEST DIFFERENT BETTING PATTERNS ===

        // Test ascending bet amounts (if funds allow)
        let current_player_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let bet_sizes = vector[1000000, 2000000, 5000000, 10000000]; // Various sizes
        let i = 0;
        while (i < vector::length(&bet_sizes) && current_player_balance > 20000000) {
            let bet_size = *vector::borrow(&bet_sizes, i);
            if (current_player_balance >= bet_size) {
                DiceGame::test_only_play_dice(&player, ((i % 6) + 1) as u8, bet_size);
                current_player_balance = primary_fungible_store::balance(
                    PLAYER_ADDR,
                    option::extract(&mut coin::paired_metadata<AptosCoin>())
                );
            };
            i = i + 1;
        };

        // Final verification
        assert!(DiceGame::is_ready(), 8);
    }

    #[test]
    fun test_dice_administrative_functions_and_comprehensive_views() {
        let (_, casino_signer, dice_signer, whale_investor, _, _) =
            setup_dice_ecosystem();

        // Setup ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // === PHASE 1: TEST ADMINISTRATIVE LIMIT UPDATES ===

        // Test valid limit update (reducing risk: higher min, lower max)
        DiceGame::request_limit_update(&dice_signer, 2000000, 40000000); // 0.02 APT min, 0.4 APT max

        // Verify limits were updated in casino metadata
        let casino_game_obj = DiceGame::get_casino_game_object();
        let (_, _, _, min_bet, max_bet, _, _) =
            CasinoHouse::get_game_metadata(casino_game_obj);
        assert!(min_bet == 2000000, 1);
        assert!(max_bet == 40000000, 2);

        // Test another valid update (further risk reduction)
        DiceGame::request_limit_update(&dice_signer, 5000000, 35000000); // 0.05 APT min, 0.35 APT max

        let (_, _, _, min_bet2, max_bet2, _, _) =
            CasinoHouse::get_game_metadata(casino_game_obj);
        assert!(min_bet2 == 5000000, 3);
        assert!(max_bet2 == 35000000, 4);

        // === PHASE 2: COMPREHENSIVE VIEW FUNCTION TESTING ===

        // Test all configuration getters with updated values
        let (min_view, max_view, payout_view, house_edge_view) =
            DiceGame::get_game_config();
        assert!(min_view == MIN_BET, 5); // Original constants
        assert!(max_view == MAX_BET, 6);
        assert!(payout_view == PAYOUT_MULTIPLIER, 7);
        assert!(house_edge_view == 1667, 8);

        // Test payout calculation with various amounts
        assert!(DiceGame::calculate_payout(1000000) == 5000000, 9); // 0.01 APT -> 0.05 APT
        assert!(DiceGame::calculate_payout(10000000) == 50000000, 10); // 0.1 APT -> 0.5 APT
        assert!(DiceGame::calculate_payout(0) == 0, 11); // Edge case: 0 bet

        // Test game status functions
        assert!(DiceGame::is_initialized(), 12);
        assert!(DiceGame::is_registered(), 13);
        assert!(DiceGame::is_ready(), 14);
        assert!(DiceGame::object_exists(), 15);

        // Test treasury-related view functions
        let treasury_balance = DiceGame::game_treasury_balance();
        let treasury_addr = DiceGame::game_treasury_address();
        let (target, overflow, drain, volume) = DiceGame::game_treasury_config();

        assert!(treasury_balance >= 0, 16);
        assert!(treasury_addr != @0x0, 17);
        assert!(target > 0, 18);
        assert!(overflow >= target, 19);
        assert!(drain <= target, 20);
        assert!(volume >= 0, 21);

        // Test casino game object and info consistency
        let casino_obj = DiceGame::get_casino_game_object();
        let (creator, game_obj, name, version) = DiceGame::get_game_info();

        assert!(casino_obj == game_obj, 22);
        assert!(creator == DICE_ADDR, 23);
        assert!(name == string::utf8(b"DiceGame"), 24);
        assert!(version == string::utf8(b"v1"), 25);

        // Test address derivation functions
        let object_addr = DiceGame::get_game_object_address();
        let derived_addr =
            DiceGame::derive_game_object_address(
                DICE_ADDR,
                string::utf8(b"DiceGame"),
                string::utf8(b"v1")
            );
        assert!(object_addr == derived_addr, 26);

        // Test payout capacity with current treasury state
        assert!(DiceGame::can_handle_payout(min_bet2), 27); // Updated min
        assert!(DiceGame::can_handle_payout(max_bet2), 28); // Updated max
        assert!(DiceGame::can_handle_payout(STANDARD_BET), 29); // Standard bet

        // === PHASE 3: STRESS TEST VIEW FUNCTIONS ===

        // Test view functions multiple times to ensure stability
        let stress_iterations = 10;
        let iter = 0;
        while (iter < stress_iterations) {
            // Call various view functions
            let (_, _, _, _) = DiceGame::get_game_config();
            let _ = DiceGame::calculate_payout(STANDARD_BET);
            let _ = DiceGame::is_ready();
            let _ = DiceGame::game_treasury_balance();
            let (_, _, _, _) = DiceGame::get_game_info();

            iter = iter + 1;
        };

        // === PHASE 4: FINAL SYSTEM VALIDATION ===

        // Verify everything is still consistent after all operations
        assert!(DiceGame::is_ready(), 30);
        assert!(CasinoHouse::is_game_registered(casino_obj), 31);
        assert!(CasinoHouse::treasury_balance() > 0, 32);

        // Verify updated limits are still in effect
        let (_, _, _, final_min, final_max, _, _) =
            CasinoHouse::get_game_metadata(casino_obj);
        assert!(final_min == 5000000, 33); // Last update value
        assert!(final_max == 35000000, 34); // Last update value
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_UNAUTHORIZED)]
    fun test_unauthorized_initialization() {
        let (_, casino_signer, _, whale_investor, _, _) = setup_dice_ecosystem();
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Setup casino
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1667
        );

        // Try to initialize with wrong signer - should fail
        DiceGame::initialize_game(&unauthorized);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_ALREADY_INITIALIZED)]
    fun test_double_initialization() {
        let (_, casino_signer, dice_signer, whale_investor, _, _) =
            setup_dice_ecosystem();

        // Setup casino and initialize once
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to initialize again - should fail
        DiceGame::initialize_game(&dice_signer);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_GUESS)]
    fun test_invalid_guess_too_low() {
        let (_, casino_signer, dice_signer, whale_investor, player, _) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to guess 0 (invalid) - should fail
        DiceGame::test_only_play_dice(&player, 0, STANDARD_BET);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_GUESS)]
    fun test_invalid_guess_too_high() {
        let (_, casino_signer, dice_signer, whale_investor, player, _) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to guess 7 (invalid) - should fail
        DiceGame::test_only_play_dice(&player, 7, STANDARD_BET);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_low() {
        let (_, casino_signer, dice_signer, whale_investor, player, _) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to bet below minimum - should fail
        DiceGame::test_only_play_dice(&player, 3, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_high() {
        let (_, casino_signer, dice_signer, whale_investor, player, _) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to bet above maximum - should fail
        DiceGame::test_only_play_dice(&player, 3, MAX_BET + 1);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_UNAUTHORIZED)]
    fun test_unauthorized_limit_update() {
        let (_, casino_signer, dice_signer, whale_investor, _, _) =
            setup_dice_ecosystem();
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to update limits with unauthorized signer - should fail
        DiceGame::request_limit_update(&unauthorized, 2000000, 40000000);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
    fun test_invalid_limit_update_range() {
        let (_, casino_signer, dice_signer, whale_investor, _, _) =
            setup_dice_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

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

        // Try to set max < min - should fail
        DiceGame::request_limit_update(&dice_signer, 40000000, 20000000);
    }
}
