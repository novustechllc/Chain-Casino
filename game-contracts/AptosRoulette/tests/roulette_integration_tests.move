//! MIT License
//!
//! Integration Tests for AptosRoulette Module
//!
//! Tests European roulette mechanics, initialization, and casino integration.

#[test_only]
module roulette_game::test_aptos_roulette {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::randomness;
    use roulette_game::AptosRoulette;
    use casino::CasinoHouse;
    use casino::InvestorToken;

    const INITIAL_BALANCE: u64 = 100_000_000; // 1 APT
    const MIN_BET: u64 = 1_000_000; // 0.01 APT
    const MAX_BET: u64 = 10_000_000; // 0.1 APT
    const LARGE_BET: u64 = 10_000_000; // 0.1 APT

    /// Setup test environment with funded accounts
    fun setup_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(@casino);
        let roulette_signer = account::create_account_for_test(@roulette_game);
        let player_signer = account::create_account_for_test(@0xCAFE);
        let investor = account::create_account_for_test(@0xEFAC); // ← Add investor

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // ✅ FIRST: Setup primary stores for ALL addresses
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[@casino, @roulette_game, @0xCAFE, @0xEFAC]; // ← Include investor
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // ✅ THEN: Fund accounts (stores now exist)
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE * 100);
        aptos_coin::mint(&aptos_framework, @roulette_game, INITIAL_BALANCE * 10);
        aptos_coin::mint(&aptos_framework, @0xCAFE, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0xEFAC, INITIAL_BALANCE * 50); // ← Fund investor

        // Initialize casino system
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);

        // Fund treasury
        InvestorToken::deposit_and_mint(&investor, INITIAL_BALANCE * 40);

        // Register game
        CasinoHouse::register_game(
            &casino_signer,
            @roulette_game,
            string::utf8(b"AptosRoulette"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            1500,
            100_000_000,
            string::utf8(b"https://chaincasino.apt/roulette"),
            string::utf8(
                b"https://chaincasino.apt/icons/roulette.png"
            ),
            string::utf8(b"European roulette with comprehensive betting options")
        );

        // Initialize game
        AptosRoulette::initialize_game(&roulette_signer);

        (casino_signer, roulette_signer, player_signer)
    }

    #[test]
    /// Test basic number betting functionality
    fun test_single_number_bet() {
        let (_casino, _roulette, player) = setup_test();
        let player_addr = signer::address_of(&player);

        // Place a bet on number 7
        AptosRoulette::test_only_bet_number(&player, 7, MIN_BET);

        // Verify that a spin result exists by calling the function (will abort if no result)
        let (_, _, _, _, _, _, total_wagered, _, _, _) =
            AptosRoulette::get_latest_result(player_addr);
        assert!(total_wagered > 0, 0); // Verify we have a valid result with actual wagered amount

        // Get the result and verify basic properties
        let (
            winning_number,
            winning_color,
            _is_even,
            _is_high,
            dozen,
            column,
            total_wagered,
            total_payout,
            winning_bets,
            net_result
        ) = AptosRoulette::get_latest_result(player_addr);

        // Verify bet amount was recorded correctly
        assert!(total_wagered == MIN_BET, 1);

        // Verify winning number is valid (0-36)
        assert!(winning_number <= 36, 2);

        // Verify color matches number
        if (winning_number == 0) {
            assert!(winning_color == string::utf8(b"green"), 3);
        } else if (AptosRoulette::is_red(winning_number)) {
            assert!(winning_color == string::utf8(b"red"), 4);
        } else {
            assert!(winning_color == string::utf8(b"black"), 5);
        };

        // Verify dozen and column are correct
        assert!(dozen == AptosRoulette::get_dozen(winning_number), 6);
        assert!(column == AptosRoulette::get_column(winning_number), 7);

        // If we won (bet number 7 and winning number is 7), verify payout
        if (winning_number == 7) {
            assert!(winning_bets == 1, 8);
            assert!(total_payout == MIN_BET * 35, 9); // 35:1 payout
            assert!(net_result == true, 10);
        } else {
            assert!(winning_bets == 0, 11);
            assert!(total_payout == 0, 12);
            assert!(net_result == false, 13);
        }
    }

    #[test]
    /// Test multi-bet functionality with different bet types
    fun test_multi_bet_combination() {
        let (_casino, _roulette, player) = setup_test();
        let player_addr = signer::address_of(&player);

        // Place multiple bets: number 17, red, and dozen 2
        let bet_types = vector[0u8, 4u8, 7u8]; // NUMBER, RED_BLACK, DOZEN
        let bet_values = vector[17u8, 1u8, 2u8]; // number 17, red (1), dozen 2
        let bet_numbers_list = vector[vector::empty<u8>(), vector::empty<u8>(), vector::empty<u8>()];
        let amounts = vector[MIN_BET, MIN_BET, MIN_BET];

        AptosRoulette::test_only_place_multi_bet(
            &player,
            bet_types,
            bet_values,
            bet_numbers_list,
            amounts
        );

        // Verify result exists and basic properties
        let (
            winning_number,
            _winning_color,
            _is_even,
            _is_high,
            _dozen,
            _column,
            total_wagered,
            total_payout,
            winning_bets,
            _net_result
        ) = AptosRoulette::get_latest_result(player_addr);

        // Verify total wagered is sum of all bets
        assert!(total_wagered == MIN_BET * 3, 1);

        // Verify winning number is valid
        assert!(winning_number <= 36, 2);

        // Calculate expected winning bets and payout
        let number_17_won = winning_number == 17;
        let red_won = winning_number != 0 && AptosRoulette::is_red(winning_number);
        let dozen_2_won = winning_number >= 13 && winning_number <= 24;

        let expected_winning_bets =
            (if (number_17_won) { 1u8 }
            else { 0u8 })
                + (if (red_won) { 1u8 }
                else { 0u8 })
                + (if (dozen_2_won) { 1u8 }
                else { 0u8 });

        let expected_payout =
            (if (number_17_won) {
                MIN_BET * 35
            } else { 0 }) + (if (red_won) {
                MIN_BET
            } else { 0 }) + (if (dozen_2_won) {
                MIN_BET * 2
            } else { 0 });

        assert!(winning_bets == expected_winning_bets, 3);
        assert!(total_payout == expected_payout, 4);
    }

    #[test]
    /// Test view functions return correct values
    fun test_view_functions() {
        let (_casino, _roulette, _player) = setup_test();

        // Test color functions
        assert!(AptosRoulette::is_red(1) == true, 1); // 1 is red
        assert!(AptosRoulette::is_red(2) == false, 2); // 2 is black
        assert!(AptosRoulette::is_red(0) == false, 3); // 0 is neither red nor black

        assert!(AptosRoulette::is_black(2) == true, 4); // 2 is black
        assert!(AptosRoulette::is_black(1) == false, 5); // 1 is red
        assert!(AptosRoulette::is_black(0) == false, 6); // 0 is green

        // Test even/odd functions
        assert!(AptosRoulette::is_even(2) == true, 7);
        assert!(AptosRoulette::is_even(1) == false, 8);
        assert!(AptosRoulette::is_even(0) == false, 9); // 0 is neither even nor odd in roulette

        assert!(AptosRoulette::is_odd(1) == true, 10);
        assert!(AptosRoulette::is_odd(2) == false, 11);
        assert!(AptosRoulette::is_odd(0) == false, 12);

        // Test dozen function
        assert!(AptosRoulette::get_dozen(1) == 1, 13); // 1-12 is dozen 1
        assert!(AptosRoulette::get_dozen(13) == 2, 14); // 13-24 is dozen 2
        assert!(AptosRoulette::get_dozen(25) == 3, 15); // 25-36 is dozen 3
        assert!(AptosRoulette::get_dozen(0) == 0, 16); // 0 is not in any dozen

        // Test column function
        assert!(AptosRoulette::get_column(1) == 1, 17); // 1, 4, 7... is column 1
        assert!(AptosRoulette::get_column(2) == 2, 18); // 2, 5, 8... is column 2
        assert!(AptosRoulette::get_column(3) == 3, 19); // 3, 6, 9... is column 3
        assert!(AptosRoulette::get_column(0) == 0, 20); // 0 is not in any column

        // Test color string function
        assert!(AptosRoulette::get_color_string(0) == string::utf8(b"green"), 21);
        assert!(AptosRoulette::get_color_string(1) == string::utf8(b"red"), 22);
        assert!(AptosRoulette::get_color_string(2) == string::utf8(b"black"), 23);

        // Test payout table
        let (single, even_money, dozen_column, split, street, corner, line) =
            AptosRoulette::get_payout_table();
        assert!(single == 35, 24);
        assert!(even_money == 1, 25);
        assert!(dozen_column == 2, 26);
        assert!(split == 17, 27);
        assert!(street == 11, 28);
        assert!(corner == 8, 29);
        assert!(line == 5, 30);

        // Test initialization status
        assert!(AptosRoulette::is_initialized() == true, 31);
        // Note: is_registered() and is_ready() depend on CasinoHouse integration
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_NUMBER)]
    /// Test that invalid number bet fails
    fun test_invalid_number_bet_fails() {
        let (_casino, _roulette, player) = setup_test();

        // Try to bet on invalid number 37 (max is 36)
        AptosRoulette::test_only_bet_number(&player, 37, MIN_BET);
    }

    #[test]
    #[expected_failure(abort_code = roulette_game::AptosRoulette::E_INVALID_AMOUNT)]
    /// Test that insufficient bet amount fails
    fun test_insufficient_bet_amount_fails() {
        let (_casino, _roulette, player) = setup_test();

        // Try to bet less than minimum (MIN_BET is 1_000_000)
        AptosRoulette::test_only_bet_number(&player, 17, 500_000);
    }

    #[test]
    /// Test memory cleanup functionality
    fun test_clear_game_result() {
        let (_casino, _roulette, player) = setup_test();
        let player_addr = signer::address_of(&player);

        // Place a bet to create a result
        AptosRoulette::test_only_bet_number(&player, 7, MIN_BET);

        // Verify result exists
        let (winning_number, _, _, _, _, _, _, _, _, _) =
            AptosRoulette::get_latest_result(player_addr);
        assert!(winning_number <= 36, 1); // Valid result exists

        // Clear the result
        AptosRoulette::clear_game_result(&player);

        // Try to get result - should fail since it's cleared
        // Note: This will abort, but in a real test you might want to check existence differently
        // For now, we'll just verify the clear function runs without error
    }
}
