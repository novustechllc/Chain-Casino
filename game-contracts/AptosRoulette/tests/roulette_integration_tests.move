//! MIT License
//!
//! Integration Tests for AptosRoulette Module
//!
//! Tests roulette mechanics, initialization, and casino integration.

#[test_only]
module roulette_game::RouletteIntegrationTests {
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
    use roulette_game::AptosRoulette;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const ROULETTE_ADDR: address = @roulette_game;
    const WHALE_INVESTOR_ADDR: address = @0x1001;
    const PLAYER_ADDR: address = @0x2001;

    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT for liquidity
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT for testing
    const STANDARD_BET: u64 = 5000000; // 0.05 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 30000000; // 0.3 APT

    fun setup_roulette_ecosystem(): (signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let roulette_signer = account::create_account_for_test(ROULETTE_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[CASINO_ADDR, ROULETTE_ADDR, WHALE_INVESTOR_ADDR, PLAYER_ADDR];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, ROULETTE_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, PLAYER_FUNDING);

        (aptos_framework, casino_signer, roulette_signer, whale_investor, player)
    }

    #[test]
    fun test_roulette_initialization_and_basic_gameplay() {
        let (_, casino_signer, roulette_signer, whale_investor, player) =
            setup_roulette_ecosystem();

        // === PHASE 1: CASINO SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);

        // Provide initial liquidity
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // === PHASE 2: GAME REGISTRATION ===
        CasinoHouse::register_game(
            &casino_signer,
            ROULETTE_ADDR,
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            270, // 2.70% house edge
            1_050_000_000, // max_payout: 35x max_bet = 35 * 30M = 1.05B1000000
            string::utf8(b"https://chaincasino.apt/roulette"),
            string::utf8(
                b"https://chaincasino.apt/icons/roulette.png"
            ),
            string::utf8(
                b"European roulette with 37 numbers and 35:1 single number payouts"
            )
        );

        // === PHASE 3: GAME INITIALIZATION ===
        AptosRoulette::initialize_game(&roulette_signer);

        // Verify initialization success
        assert!(AptosRoulette::is_initialized(), 1);
        assert!(AptosRoulette::is_registered(), 2);
        assert!(AptosRoulette::is_ready(), 3);
        assert!(AptosRoulette::object_exists(), 4);

        // === PHASE 4: VERIFY ROULETTE CONFIGURATION ===
        let (min_bet, max_bet, payout_mult, house_edge) =
            AptosRoulette::get_game_config();
        assert!(min_bet == MIN_BET, 5);
        assert!(max_bet == MAX_BET, 6);
        assert!(payout_mult == 35, 7); // Single number pays 35:1
        assert!(house_edge == 270, 8); // 2.70%

        // Test wheel info
        let (number_count, wheel_type, payout_ratio) = AptosRoulette::get_wheel_info();
        assert!(number_count == 37, 9); // 0-36
        assert!(wheel_type == string::utf8(b"European"), 10);
        assert!(payout_ratio == 35, 11);

        // Test roulette range
        let (min_number, max_number) = AptosRoulette::get_roulette_range();
        assert!(min_number == 0, 12);
        assert!(max_number == 36, 13);

        // === PHASE 5: TEST NUMBER VALIDATION ===
        assert!(AptosRoulette::is_valid_roulette_number(0), 14); // 0 is valid
        assert!(AptosRoulette::is_valid_roulette_number(36), 15); // 36 is valid
        assert!(!AptosRoulette::is_valid_roulette_number(37), 16); // 37 is invalid
        assert!(!AptosRoulette::is_valid_roulette_number(100), 17); // 100 is invalid

        // === PHASE 6: TEST PAYOUT CALCULATION ===
        let payout_5apt = AptosRoulette::calculate_single_number_payout(STANDARD_BET);
        assert!(payout_5apt == STANDARD_BET * 35, 18); // 35:1 payout

        let payout_min = AptosRoulette::calculate_single_number_payout(MIN_BET);
        assert!(payout_min == MIN_BET * 35, 19);

        // === PHASE 7: TEST ACTUAL ROULETTE SPINS ===
        let initial_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Test betting on different numbers (0-36)
        let test_numbers = vector[0, 7, 17, 23, 36]; // Sample European roulette numbers
        let i = 0;
        while (i < vector::length(&test_numbers)) {
            let bet_number = *vector::borrow(&test_numbers, i);
            AptosRoulette::test_only_spin_roulette(&player, bet_number, STANDARD_BET);
            i = i + 1;
        };

        // Verify player spent money
        let final_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        assert!(final_balance < initial_balance, 20);

        // === PHASE 8: TEST TREASURY INTEGRATION ===
        let treasury_balance = AptosRoulette::game_treasury_balance();
        assert!(treasury_balance >= 0, 21);

        let treasury_addr = AptosRoulette::game_treasury_address();
        assert!(treasury_addr != @0x0, 22);

        // Test payout capacity
        assert!(AptosRoulette::can_handle_payout(MAX_BET), 23);

        // === PHASE 9: VERIFY SYSTEM STABILITY ===
        assert!(AptosRoulette::is_ready(), 24);
        assert!(CasinoHouse::treasury_balance() > 0, 25);
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_NUMBER)]
    fun test_invalid_roulette_number() {
        let (_, casino_signer, roulette_signer, whale_investor, player) =
            setup_roulette_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            ROULETTE_ADDR,
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            270, // 2.70% house edge
            1_050_000_000, // max_payout: 35x max_bet = 35 * 30M = 1.05B1000000
            string::utf8(b"https://chaincasino.apt/roulette"),
            string::utf8(
                b"https://chaincasino.apt/icons/roulette.png"
            ),
            string::utf8(
                b"European roulette with 37 numbers and 35:1 single number payouts"
            )
        );

        AptosRoulette::initialize_game(&roulette_signer);

        // Try to bet on number 37 (invalid for European roulette) - should fail
        AptosRoulette::test_only_spin_roulette(&player, 37, STANDARD_BET);
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_low() {
        let (_, casino_signer, roulette_signer, whale_investor, player) =
            setup_roulette_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            ROULETTE_ADDR,
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            270, // 2.70% house edge
            1_050_000_000, // max_payout: 35x max_bet = 35 * 30M = 1.05B1000000
            string::utf8(b"https://chaincasino.apt/roulette"),
            string::utf8(
                b"https://chaincasino.apt/icons/roulette.png"
            ),
            string::utf8(
                b"European roulette with 37 numbers and 35:1 single number payouts"
            )
        );

        AptosRoulette::initialize_game(&roulette_signer);

        // Try to bet below minimum - should fail
        AptosRoulette::test_only_spin_roulette(&player, 17, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_high() {
        let (_, casino_signer, roulette_signer, whale_investor, player) =
            setup_roulette_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            ROULETTE_ADDR,
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            270, // 2.70% house edge
            1_050_000_000, // max_payout: 35x max_bet = 35 * 30M = 1.05B1000000
            string::utf8(b"https://chaincasino.apt/roulette"),
            string::utf8(
                b"https://chaincasino.apt/icons/roulette.png"
            ),
            string::utf8(
                b"European roulette with 37 numbers and 35:1 single number payouts"
            )
        );

        AptosRoulette::initialize_game(&roulette_signer);

        // Try to bet above maximum - should fail
        AptosRoulette::test_only_spin_roulette(&player, 23, MAX_BET + 1);
    }
}
