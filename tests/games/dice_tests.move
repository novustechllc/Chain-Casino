//! MIT License
//!
//! Comprehensive test suite for DiceGame module

#[test_only]
module dice_game::DiceGameTest {
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::CasinoHouse;
    use dice_game::DiceGame;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 50000000; // 0.5 APT
    const TEST_BET: u64 = 10000000; // 0.1 APT

    // Error constants from DiceGame module
    const E_INVALID_GUESS: u64 = 0x01;
    const E_INVALID_AMOUNT: u64 = 0x02;
    const E_UNAUTHORIZED: u64 = 0x03;
    const E_GAME_NOT_REGISTERED: u64 = 0x04;
    const E_ALREADY_INITIALIZED: u64 = 0x05;

    fun setup_basic_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let dice_account = account::create_account_for_test(@dice_game);

        // Initialize environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Register coin accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&dice_account);

        // Mint initial balances
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE * 10);
        aptos_coin::mint(&aptos_framework, @dice_game, INITIAL_BALANCE);

        (aptos_framework, casino_account, dice_account)
    }

    // Helper to setup casino
    fun setup_with_casino(): (signer, signer, signer) {
        let (aptos_framework, casino_account, dice_account) = setup_basic_test();

        // Initialize casino now that it's public
        CasinoHouse::init_module_for_test(&casino_account);

        (aptos_framework, casino_account, dice_account)
    }

    //
    // View Function Tests (No dependency on casino state)
    //

    #[test]
    fun test_get_game_config() {
        let (min_bet, max_bet, payout_mult, house_edge) = DiceGame::get_game_config();
        assert!(min_bet == MIN_BET, 1);
        assert!(max_bet == MAX_BET, 2);
        assert!(payout_mult == 5, 3);
        assert!(house_edge == 1667, 4);
    }

    #[test]
    fun test_calculate_payout_function() {
        // Test the calculate_payout function - THIS COVERS THE MISSING LINE
        assert!(DiceGame::calculate_payout(0) == 0, 1);
        assert!(DiceGame::calculate_payout(1) == 5, 2);
        assert!(DiceGame::calculate_payout(1000000) == 5000000, 3); // 0.01 APT -> 0.05 APT
        assert!(
            DiceGame::calculate_payout(TEST_BET) == TEST_BET * 5,
            4
        );
        assert!(
            DiceGame::calculate_payout(MAX_BET) == MAX_BET * 5,
            5
        );

        // Test large numbers
        let large_bet = 1000000000; // 10 APT
        assert!(DiceGame::calculate_payout(large_bet) == 5000000000, 6); // 50 APT payout
    }

    #[test]
    fun test_status_functions_before_setup() {
        let (_, _, _) = setup_with_casino();

        // Before any setup
        assert!(!DiceGame::is_registered(), 1);
        assert!(!DiceGame::is_initialized(), 2);
        assert!(!DiceGame::is_ready(), 3);
    }

    //
    // Initialization Error Tests
    //

    #[test]
    #[expected_failure(abort_code = E_UNAUTHORIZED, location = dice_game::DiceGame)]
    fun test_initialize_unauthorized_signer() {
        let (_, casino_account, _) = setup_basic_test();

        // Try to initialize with casino signer instead of dice_game signer
        DiceGame::initialize_game(&casino_account);
    }

    #[test]
    #[expected_failure(abort_code = E_GAME_NOT_REGISTERED, location = dice_game::DiceGame)]
    fun test_initialize_not_registered() {
        let (_, _, dice_account) = setup_with_casino();

        // Try to initialize without casino registration (will fail since we can't call casino package functions)
        DiceGame::initialize_game(&dice_account);
    }

    //
    // Input Validation Tests (Using test_only function)
    //

    #[test]
    #[expected_failure(abort_code = E_INVALID_GUESS, location = dice_game::DiceGame)]
    fun test_play_dice_guess_too_low() {
        let (framework, _, _) = setup_basic_test();

        // Setup a minimal test scenario
        let player = account::create_account_for_test(@0x123);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(&framework, @0x123, TEST_BET);

        // This will fail at guess validation before any casino interaction
        DiceGame::test_only_play_dice(&player, 0, TEST_BET);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_GUESS, location = dice_game::DiceGame)]
    fun test_play_dice_guess_too_high() {
        let (framework, _, _) = setup_basic_test();

        let player = account::create_account_for_test(@0x123);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(&framework, @0x123, TEST_BET);

        // This will fail at guess validation
        DiceGame::test_only_play_dice(&player, 7, TEST_BET);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = dice_game::DiceGame)]
    fun test_play_dice_bet_too_low() {
        let (framework, _, _) = setup_basic_test();

        let player = account::create_account_for_test(@0x123);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(&framework, @0x123, MIN_BET);

        // This will fail at bet amount validation
        DiceGame::test_only_play_dice(&player, 1, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = dice_game::DiceGame)]
    fun test_play_dice_bet_too_high() {
        let (framework, _, _) = setup_basic_test();

        let player = account::create_account_for_test(@0x123);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(&framework, @0x123, MAX_BET * 2);

        // This will fail at bet amount validation
        DiceGame::test_only_play_dice(&player, 1, MAX_BET + 1);
    }

    //
    // Boundary Value Tests
    //

    #[test]
    fun test_payout_calculation_edge_cases() {
        // Test boundary values for payout calculation
        assert!(
            DiceGame::calculate_payout(MIN_BET) == MIN_BET * 5,
            1
        );
        assert!(
            DiceGame::calculate_payout(MAX_BET) == MAX_BET * 5,
            2
        );

        // Test mid-range values
        let mid_bet = (MIN_BET + MAX_BET) / 2;
        assert!(
            DiceGame::calculate_payout(mid_bet) == mid_bet * 5,
            3
        );

        // Test specific values
        assert!(DiceGame::calculate_payout(10000000) == 50000000, 4); // 0.1 APT -> 0.5 APT
        assert!(DiceGame::calculate_payout(25000000) == 125000000, 5); // 0.25 APT -> 1.25 APT
    }

    #[test]
    fun test_config_constants_consistency() {
        let (min_bet, max_bet, payout_mult, house_edge) = DiceGame::get_game_config();

        // Verify constants match expected values
        assert!(min_bet < max_bet, 1);
        assert!(payout_mult == 5, 2); // 5x payout for 1/6 chance = house edge
        assert!(house_edge == 1667, 3); // 16.67% house edge

        // Verify min bet is reasonable (0.01 APT)
        assert!(min_bet == 1000000, 4);

        // Verify max bet is reasonable (0.5 APT)
        assert!(max_bet == 50000000, 5);
    }

    //
    // Integration Test (Without Casino Dependencies)
    //

    #[test]
    fun test_dice_game_state_before_registration() {
        let (_, _, _) = setup_with_casino(); // Now casino is initialized

        // Test the game state when casino hasn't registered it yet
        assert!(!DiceGame::is_registered(), 1);
        assert!(!DiceGame::is_initialized(), 2);
        assert!(!DiceGame::is_ready(), 3);

        // View functions should still work
        let (min_bet, max_bet, payout_mult, house_edge) = DiceGame::get_game_config();
        assert!(min_bet > 0, 4);
        assert!(max_bet > min_bet, 5);
        assert!(payout_mult == 5, 6);
        assert!(house_edge > 0, 7);
    }

    #[test]
    fun test_payout_calculation_comprehensive() {
        // Test a comprehensive range of bet amounts
        let test_amounts = vector[
            1, // Minimal amount
            1000000, // Min bet (0.01 APT)
            5000000, // 0.05 APT
            10000000, // 0.1 APT
            25000000, // 0.25 APT
            50000000, // Max bet (0.5 APT)
            100000000 // 1 APT
        ];

        let i = 0;
        while (i < vector::length(&test_amounts)) {
            let amount = *vector::borrow(&test_amounts, i);
            let expected_payout = amount * 5;
            assert!(DiceGame::calculate_payout(amount) == expected_payout, i);
            i = i + 1;
        };
    }

    #[test]
    fun test_mathematical_house_edge() {
        // Verify the mathematical house edge calculation
        // With 1/6 win chance and 5x payout:
        // Expected value = (1/6 * 4) + (5/6 * -1) = 4/6 - 5/6 = -1/6 ≈ -16.67%

        let bet_amount = 1000000; // 0.01 APT
        let payout = DiceGame::calculate_payout(bet_amount);
        let win_profit = payout - bet_amount; // What player gains when winning

        // Player gains 4x their bet when winning (5x payout - 1x bet)
        assert!(win_profit == bet_amount * 4, 1);

        // With 1/6 win chance, expected value is negative (house edge)
        // This validates our 16.67% house edge configuration
        let (_, _, payout_mult, house_edge_bps) = DiceGame::get_game_config();
        assert!(payout_mult == 5, 2);
        assert!(house_edge_bps == 1667, 3); // 16.67% in basis points
    }
}
