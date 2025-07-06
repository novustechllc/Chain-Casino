//! MIT License
//!
//! Integration Tests for AptosRoulette Module
//!
//! Tests all bet types, multi-bet functionality, and advanced betting features.

#[test_only]
module roulette_game::EnhancedRouletteTests {
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
    const PLAYER2_ADDR: address = @0x2002;

    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT for liquidity
    const PLAYER_FUNDING: u64 = 10000000000; // 100 APT for testing
    const STANDARD_BET: u64 = 5000000; // 0.05 APT
    const LARGE_BET: u64 = 20000000; // 0.2 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 30000000; // 0.3 APT

    fun setup_enhanced_ecosystem(): (signer, signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let roulette_signer = account::create_account_for_test(ROULETTE_ADDR);
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
            CASINO_ADDR, ROULETTE_ADDR, WHALE_INVESTOR_ADDR, PLAYER_ADDR, PLAYER2_ADDR
        ];
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
        aptos_coin::mint(&aptos_framework, PLAYER2_ADDR, PLAYER_FUNDING);

        (aptos_framework, casino_signer, roulette_signer, whale_investor, player, player2)
    }

fun setup_complete_casino() {
        let (_, casino_signer, roulette_signer, whale_investor, _, _) = setup_enhanced_ecosystem();

        // 1. Initialize core casino system FIRST
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        
        // 2. Fund treasury BEFORE registering any games (critical order!)
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // 3. Register roulette game - CASINO creates the game object
        CasinoHouse::register_game(
            &casino_signer,    
            ROULETTE_ADDR,    
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            270, // 2.70% house edge
            1_050_000_000 // max_payout: 35x max_bet
        );

        // 4. Initialize roulette game - GAME claims the capability
        AptosRoulette::initialize_game(&roulette_signer);
    }

    #[test]
    fun test_enhanced_roulette_initialization() {
        setup_complete_casino();

        // Verify all systems are ready
        assert!(AptosRoulette::is_initialized(), 1);
        assert!(AptosRoulette::is_registered(), 2);
        assert!(AptosRoulette::is_ready(), 3);
        assert!(AptosRoulette::object_exists(), 4);

        // Test enhanced view functions
        let (single, even_money, dozen_col, split, street, corner, line) = 
            AptosRoulette::get_payout_table();
        assert!(single == 35, 5);      // 35:1
        assert!(even_money == 1, 6);   // 1:1
        assert!(dozen_col == 2, 7);    // 2:1
        assert!(split == 17, 8);       // 17:1
        assert!(street == 11, 9);      // 11:1
        assert!(corner == 8, 10);      // 8:1
        assert!(line == 5, 11);        // 5:1

        // Test number property helpers
        assert!(AptosRoulette::is_red(1), 12);
        assert!(AptosRoulette::is_black(2), 13);
        assert!(!AptosRoulette::is_red(0), 14); // 0 is green
        assert!(!AptosRoulette::is_black(0), 15);
        assert!(AptosRoulette::is_even(2), 16);
        assert!(AptosRoulette::is_odd(1), 17);
        assert!(!AptosRoulette::is_even(0), 18); // 0 is neither even nor odd for betting
        assert!(AptosRoulette::is_high(20), 19);
        assert!(AptosRoulette::is_low(10), 20);
    }

    #[test]
    fun test_color_and_property_helpers() {
        setup_complete_casino();

        // Test color functions
        assert!(AptosRoulette::is_red(1), 1);
        assert!(AptosRoulette::is_red(3), 2);
        assert!(AptosRoulette::is_red(36), 3);
        assert!(AptosRoulette::is_black(2), 4);
        assert!(AptosRoulette::is_black(4), 5);
        assert!(AptosRoulette::is_black(35), 6);
        assert!(!AptosRoulette::is_red(0), 7);
        assert!(!AptosRoulette::is_black(0), 8);

        // Test even/odd (excluding 0)
        assert!(AptosRoulette::is_even(2), 9);
        assert!(AptosRoulette::is_even(36), 10);
        assert!(AptosRoulette::is_odd(1), 11);
        assert!(AptosRoulette::is_odd(35), 12);
        assert!(!AptosRoulette::is_even(0), 13);
        assert!(!AptosRoulette::is_odd(0), 14);

        // Test high/low
        assert!(AptosRoulette::is_low(1), 15);
        assert!(AptosRoulette::is_low(18), 16);
        assert!(AptosRoulette::is_high(19), 17);
        assert!(AptosRoulette::is_high(36), 18);
        assert!(!AptosRoulette::is_low(0), 19);
        assert!(!AptosRoulette::is_high(0), 20);

        // Test dozens
        assert!(AptosRoulette::get_dozen(5) == 1, 21);
        assert!(AptosRoulette::get_dozen(15) == 2, 22);
        assert!(AptosRoulette::get_dozen(30) == 3, 23);
        assert!(AptosRoulette::get_dozen(0) == 0, 24);

        // Test columns
        assert!(AptosRoulette::get_column(1) == 1, 25);
        assert!(AptosRoulette::get_column(2) == 2, 26);
        assert!(AptosRoulette::get_column(3) == 3, 27);
        assert!(AptosRoulette::get_column(4) == 1, 28);
        assert!(AptosRoulette::get_column(0) == 0, 29);

        // Test color strings
        assert!(AptosRoulette::get_color_string(1) == string::utf8(b"red"), 30);
        assert!(AptosRoulette::get_color_string(2) == string::utf8(b"black"), 31);
        assert!(AptosRoulette::get_color_string(0) == string::utf8(b"green"), 32);
    }

    #[test]
    fun test_convenience_betting_functions() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        let initial_balance = primary_fungible_store::balance(
            PLAYER_ADDR,
            option::extract(&mut coin::paired_metadata<AptosCoin>())
        );

        // Test red/black betting
        AptosRoulette::test_only_bet_red_black(&player, true, STANDARD_BET); // Bet on red
        AptosRoulette::test_only_bet_red_black(&player, false, STANDARD_BET); // Bet on black

        // Test even/odd betting
        AptosRoulette::test_only_bet_even_odd(&player, true, STANDARD_BET); // Bet on even
        AptosRoulette::test_only_bet_even_odd(&player, false, STANDARD_BET); // Bet on odd

        // Test high/low betting
        AptosRoulette::test_only_bet_high_low(&player, true, STANDARD_BET); // Bet on high (19-36)
        AptosRoulette::test_only_bet_high_low(&player, false, STANDARD_BET); // Bet on low (1-18)

        // Test dozen betting
        AptosRoulette::test_only_bet_dozen(&player, 1, STANDARD_BET); // First dozen (1-12)
        AptosRoulette::test_only_bet_dozen(&player, 2, STANDARD_BET); // Second dozen (13-24)
        AptosRoulette::test_only_bet_dozen(&player, 3, STANDARD_BET); // Third dozen (25-36)

        // Test column betting
        AptosRoulette::test_only_bet_column(&player, 1, STANDARD_BET); // First column
        AptosRoulette::test_only_bet_column(&player, 2, STANDARD_BET); // Second column
        AptosRoulette::test_only_bet_column(&player, 3, STANDARD_BET); // Third column

        // Verify money was spent
        let final_balance = primary_fungible_store::balance(
            PLAYER_ADDR,
            option::extract(&mut coin::paired_metadata<AptosCoin>())
        );
        let expected_spent = STANDARD_BET * 12;
        assert!(final_balance == initial_balance - expected_spent, 1);
    }

    #[test]
    fun test_advanced_betting_functions() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        // Test split betting (adjacent numbers)
        AptosRoulette::test_only_bet_split(&player, 1, 2, STANDARD_BET); // Horizontal split
        AptosRoulette::test_only_bet_split(&player, 1, 4, STANDARD_BET); // Vertical split
        AptosRoulette::test_only_bet_split(&player, 0, 1, STANDARD_BET); // 0 split with 1

        // Test street betting (3 numbers in a row)
        AptosRoulette::test_only_bet_street(&player, 1, STANDARD_BET); // 1,2,3
        AptosRoulette::test_only_bet_street(&player, 4, STANDARD_BET); // 4,5,6
        AptosRoulette::test_only_bet_street(&player, 31, STANDARD_BET); // 31,32,33

        // Test corner betting (4 numbers in square)
        AptosRoulette::test_only_bet_corner(&player, 1, STANDARD_BET); // 1,2,4,5
        AptosRoulette::test_only_bet_corner(&player, 11, STANDARD_BET); // 11,12,14,15
        AptosRoulette::test_only_bet_corner(&player, 32, STANDARD_BET); // 32,33,35,36

        // Test line betting (6 numbers in two rows)
        AptosRoulette::test_only_bet_line(&player, 1, STANDARD_BET); // 1,2,3,4,5,6
        AptosRoulette::test_only_bet_line(&player, 10, STANDARD_BET); // 10,11,12,13,14,15
        AptosRoulette::test_only_bet_line(&player, 31, STANDARD_BET); // 31,32,33,34,35,36

        // Verify all bets were processed
        assert!(AptosRoulette::is_ready(), 1);
    }

    #[test]
    fun test_multi_bet_functionality() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        let initial_balance = primary_fungible_store::balance(
            PLAYER_ADDR,
            option::extract(&mut coin::paired_metadata<AptosCoin>())
        );

        // Place multiple bets in single transaction
        let bet_types = vector[
            0,  // Single number (17)
            1,  // Red
            3,  // Even
            7,  // First dozen
            10  // First column
        ];
        let bet_values = vector[17, 0, 0, 1, 1]; // Only number bet uses value
        let bet_numbers_list = vector[
            vector::empty<u8>(),
            vector::empty<u8>(),
            vector::empty<u8>(),
            vector::empty<u8>(),
            vector::empty<u8>()
        ];
        let amounts = vector[
            STANDARD_BET,
            STANDARD_BET * 2,
            STANDARD_BET,
            LARGE_BET,
            STANDARD_BET
        ];

        AptosRoulette::test_only_place_multi_bet(
            &player, 
            bet_types, 
            bet_values, 
            bet_numbers_list, 
            amounts
        );

        // Verify total amount was spent
        let final_balance = primary_fungible_store::balance(
            PLAYER_ADDR,
            option::extract(&mut coin::paired_metadata<AptosCoin>())
        );
        let total_bet = STANDARD_BET + (STANDARD_BET * 2) + STANDARD_BET + LARGE_BET + STANDARD_BET;
        assert!(final_balance == initial_balance - total_bet, 1);

        // Verify result was stored
        let (winning_num, color, is_even, is_high, dozen, column, wagered, payout, 
             winning_bets, session_id, net_result) = AptosRoulette::get_latest_result(PLAYER_ADDR);
        
        assert!(wagered == total_bet, 2);
        assert!(winning_num <= 36, 3);
        // Other assertions depend on random result
    }

    #[test]
    fun test_complex_multi_bet_with_advanced_types() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        // Complex bet combining all types
        let bet_types = vector[
            13, // Split (1,2)
            14, // Street (4,5,6)
            15, // Corner (11,12,14,15)
            1,  // Red
            5   // High (19-36)
        ];
        let bet_values = vector[1, 4, 11, 0, 0];
        let bet_numbers_list = vector[
            vector[1, 2],           // Split numbers
            vector[4, 5, 6],        // Street numbers
            vector[11, 12, 14, 15], // Corner numbers
            vector::empty<u8>(),    // Red (no specific numbers)
            vector::empty<u8>()     // High (no specific numbers)
        ];
        let amounts = vector[
            LARGE_BET,    // Split bet
            STANDARD_BET, // Street bet
            STANDARD_BET, // Corner bet
            LARGE_BET,    // Red bet
            STANDARD_BET  // High bet
        ];

        AptosRoulette::test_only_place_multi_bet(
            &player,
            bet_types,
            bet_values,
            bet_numbers_list,
            amounts
        );

        // Verify comprehensive result was stored
        let (winning_num, color, is_even, is_high, dozen, column, wagered, payout,
             winning_bets, session_id, net_result) = AptosRoulette::get_latest_result(PLAYER_ADDR);

        assert!(wagered > 0, 1);
        assert!(winning_num <= 36, 2);
        // Color should be red, black, or green
        assert!(
            color == string::utf8(b"red") || 
            color == string::utf8(b"black") || 
            color == string::utf8(b"green"),
            3
        );
    }

    #[test]
    fun test_backward_compatibility() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        // Test that original spin_roulette still works
        AptosRoulette::test_only_spin_roulette(&player, 17, STANDARD_BET);
        AptosRoulette::test_only_spin_roulette(&player, 0, LARGE_BET);
        AptosRoulette::test_only_spin_roulette(&player, 36, STANDARD_BET);

        // Verify result structure includes new fields
        let (winning_num, color, is_even, is_high, dozen, column, wagered, payout,
             winning_bets, session_id, net_result) = AptosRoulette::get_latest_result(PLAYER_ADDR);

        assert!(wagered == STANDARD_BET, 1); // Last bet amount
        assert!(winning_num <= 36, 2);
    }

    #[test]
    fun test_concurrent_players() {
        setup_complete_casino();
        let (_, _, _, _, player1, player2) = setup_enhanced_ecosystem();

        // Both players place different types of bets
        AptosRoulette::test_only_bet_red_black(&player1, true, STANDARD_BET);
        AptosRoulette::test_only_bet_even_odd(&player2, false, LARGE_BET);

        // Both players place advanced bets
        AptosRoulette::test_only_bet_split(&player1, 5, 6, STANDARD_BET);
        AptosRoulette::test_only_bet_corner(&player2, 8, STANDARD_BET);

        // Verify both players have results
        let (p1_num, p1_color, _, _, _, _, p1_wagered, _, _, _, _) = 
            AptosRoulette::get_latest_result(PLAYER_ADDR);
        let (p2_num, p2_color, _, _, _, _, p2_wagered, _, _, _, _) = 
            AptosRoulette::get_latest_result(PLAYER2_ADDR);

        assert!(p1_wagered == STANDARD_BET, 1); // Player 1's last bet
        assert!(p2_wagered == STANDARD_BET, 2); // Player 2's last bet
        assert!(p1_num <= 36, 3);
        assert!(p2_num <= 36, 4);
    }

    // Error condition tests

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_DOZEN)]
    fun test_invalid_dozen() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_dozen(&player, 4, STANDARD_BET); // Invalid dozen (4)
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_COLUMN)]
    fun test_invalid_column() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_column(&player, 0, STANDARD_BET); // Invalid column (0)
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_SPLIT)]
    fun test_invalid_split() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_split(&player, 1, 5, STANDARD_BET); // Not adjacent
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_STREET)]
    fun test_invalid_street() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_street(&player, 2, STANDARD_BET); // 2 is not a valid street start
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_CORNER)]
    fun test_invalid_corner() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_corner(&player, 36, STANDARD_BET); // 36 can't be top-left of corner
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_LINE)]
    fun test_invalid_line() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();
        AptosRoulette::test_only_bet_line(&player, 33, STANDARD_BET); // 33 can't start a line (need 6 numbers)
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_TOO_MANY_BETS)]
    fun test_too_many_bets() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        // Try to place 11 bets (max is 10)
        let bet_types = vector[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]; // 11 bets
        let bet_values = vector[1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 1];
        let bet_numbers_list = vector[
            vector::empty<u8>(), vector::empty<u8>(), vector::empty<u8>(),
            vector::empty<u8>(), vector::empty<u8>(), vector::empty<u8>(),
            vector::empty<u8>(), vector::empty<u8>(), vector::empty<u8>(),
            vector::empty<u8>(), vector::empty<u8>()
        ];
        let amounts = vector[
            MIN_BET, MIN_BET, MIN_BET, MIN_BET, MIN_BET, MIN_BET,
            MIN_BET, MIN_BET, MIN_BET, MIN_BET, MIN_BET
        ];

        AptosRoulette::test_only_place_multi_bet(&player, bet_types, bet_values, bet_numbers_list, amounts);
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_MISMATCHED_BET_ARRAYS)]
    fun test_mismatched_arrays() {
        setup_complete_casino();
        let (_, _, _, _, player, _) = setup_enhanced_ecosystem();

        let bet_types = vector[0, 1]; // 2 types
        let bet_values = vector[17]; // 1 value (mismatch)
        let bet_numbers_list = vector[vector::empty<u8>(), vector::empty<u8>()];
        let amounts = vector[STANDARD_BET, STANDARD_BET];

        AptosRoulette::test_only_place_multi_bet(&player, bet_types, bet_values, bet_numbers_list, amounts);
    }
}
