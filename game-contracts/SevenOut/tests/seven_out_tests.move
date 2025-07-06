//! MIT License
//!
//! Integration Tests for SevenOut Module
//!
//! Tests Seven Out dice mechanics, initialization, and casino integration.

#[test_only]
module seven_out_game::SevenOutIntegrationTests {
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
    use seven_out_game::SevenOut;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const SEVEN_OUT_ADDR: address = @seven_out_game;
    const WHALE_INVESTOR_ADDR: address = @0x1001;
    const PLAYER_ADDR: address = @0x2001;

    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT for liquidity
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT for testing
    const STANDARD_BET: u64 = 10000000; // 0.1 APT
    const MIN_BET: u64 = 2000000; // 0.02 APT
    const MAX_BET: u64 = 40000000; // 0.4 APT

    fun setup_seven_out_ecosystem(): (signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let seven_out_signer = account::create_account_for_test(SEVEN_OUT_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[CASINO_ADDR, SEVEN_OUT_ADDR, WHALE_INVESTOR_ADDR, PLAYER_ADDR];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, SEVEN_OUT_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, PLAYER_FUNDING);

        (aptos_framework, casino_signer, seven_out_signer, whale_investor, player)
    }

    #[test]
    fun test_seven_out_initialization_and_basic_gameplay() {
        let (_, casino_signer, seven_out_signer, whale_investor, player) =
            setup_seven_out_ecosystem();

        // === PHASE 1: CASINO SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);

        // Provide initial liquidity
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // === PHASE 2: GAME REGISTRATION ===
        CasinoHouse::register_game(
            &casino_signer,
            SEVEN_OUT_ADDR,
            string::utf8(b"SevenOut"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            278, // 2.78% house edge
            80000000, // max_payout: 2x max_bet = 2 * 40M = 80M
            string::utf8(b"https://chaincasino.apt/seven-out"),
            string::utf8(
                b"https://chaincasino.apt/icons/seven-out.png"
            ),
            string::utf8(b"SevenOut Dice Game with a 2:1 payout")
        );

        // === PHASE 3: GAME INITIALIZATION ===
        SevenOut::initialize_game(&seven_out_signer);

        // Verify initialization success
        assert!(SevenOut::is_initialized(), 1);
        assert!(SevenOut::is_registered(), 2);
        assert!(SevenOut::is_ready(), 3);
        assert!(SevenOut::object_exists(), 4);

        // === PHASE 4: VERIFY SEVEN OUT CONFIGURATION ===
        let (min_bet, max_bet, payout_mult, house_edge) = SevenOut::get_game_config();
        assert!(min_bet == MIN_BET, 5);
        assert!(max_bet == MAX_BET, 6);
        assert!(payout_mult == 2, 7); // 2:1 payout
        assert!(house_edge == 278, 8); // 2.78%

        // Test game odds
        let (over_ways, under_ways, push_ways) = SevenOut::get_game_odds();
        assert!(over_ways == 21, 9); // 21 ways to get > 7
        assert!(under_ways == 15, 10); // 15 ways to get < 7
        assert!(push_ways == 6, 11); // 6 ways to get exactly 7

        // === PHASE 5: TEST PAYOUT CALCULATION ===
        let payout_calculation = SevenOut::calculate_payout(STANDARD_BET);
        assert!(payout_calculation == STANDARD_BET * 2, 12); // 2:1 payout

        // === PHASE 6: TEST GAME LOGIC SIMULATION ===
        let over_bet = SevenOut::bet_type_over();
        let under_bet = SevenOut::bet_type_under();

        // Test push scenario (sum = 7)
        assert!(!SevenOut::test_simulate_win(7, over_bet), 13);
        assert!(!SevenOut::test_simulate_win(7, under_bet), 14);

        // Test over bets (sum > 7)
        assert!(SevenOut::test_simulate_win(8, over_bet), 15);
        assert!(SevenOut::test_simulate_win(12, over_bet), 16);
        assert!(!SevenOut::test_simulate_win(6, over_bet), 17);
        assert!(!SevenOut::test_simulate_win(2, over_bet), 18);

        // Test under bets (sum < 7)
        assert!(SevenOut::test_simulate_win(6, under_bet), 19);
        assert!(SevenOut::test_simulate_win(2, under_bet), 20);
        assert!(!SevenOut::test_simulate_win(8, under_bet), 21);
        assert!(!SevenOut::test_simulate_win(12, under_bet), 22);

        // === PHASE 7: TEST ACTUAL SEVEN OUT GAMEPLAY ===
        let initial_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        // Test both bet types using boolean parameters
        SevenOut::test_only_play_seven_out(&player, false, STANDARD_BET); // Under bet
        SevenOut::test_only_play_seven_out(&player, true, STANDARD_BET); // Over bet

        // Verify player spent money
        let final_balance =
            primary_fungible_store::balance(
                PLAYER_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        assert!(final_balance < initial_balance, 23);

        // === PHASE 8: TEST RESULT STORAGE ===
        // Player should have a result stored
        assert!(SevenOut::has_game_result(PLAYER_ADDR), 24);

        // Get result details
        let (die1, die2, dice_sum, _, bet_amount, payout, timestamp, session_id, outcome) =
            SevenOut::get_user_game_result(PLAYER_ADDR);

        assert!(die1 >= 1 && die1 <= 6, 25);
        assert!(die2 >= 1 && die2 <= 6, 26);
        assert!(dice_sum == die1 + die2, 27);
        assert!(bet_amount == STANDARD_BET, 28);
        assert!(timestamp > 0, 29);
        assert!(outcome <= 2, 31); // 0=lose, 1=win, 2=push

        // Test quick result function
        let (quick_die1, quick_die2, quick_sum, quick_outcome, quick_payout) =
            SevenOut::get_quick_result(PLAYER_ADDR);
        assert!(quick_die1 == die1, 33);
        assert!(quick_die2 == die2, 34);
        assert!(quick_sum == dice_sum, 35);
        assert!(quick_outcome == outcome, 36);
        assert!(quick_payout == payout, 37);

        // Test session info
        let (session_info_id, session_timestamp) =
            SevenOut::get_session_info(PLAYER_ADDR);
        assert!(session_info_id == session_id, 38);
        assert!(session_timestamp == timestamp, 39);

        // === PHASE 9: TEST TREASURY INTEGRATION ===
        let treasury_balance = SevenOut::game_treasury_balance();
        assert!(treasury_balance >= 0, 40);

        let treasury_addr = SevenOut::game_treasury_address();
        assert!(treasury_addr != @0x0, 41);

        // Test payout capacity
        assert!(SevenOut::can_handle_payout(MAX_BET), 42);

        // === PHASE 10: TEST RESULT CLEANUP ===
        SevenOut::clear_game_result(&player);
        assert!(!SevenOut::has_game_result(PLAYER_ADDR), 43);

        // === PHASE 11: VERIFY SYSTEM STABILITY ===
        assert!(SevenOut::is_ready(), 44);
        assert!(CasinoHouse::treasury_balance() > 0, 45);
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = seven_out_game::SevenOut::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_low() {
        let (_, casino_signer, seven_out_signer, whale_investor, player) =
            setup_seven_out_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SEVEN_OUT_ADDR,
            string::utf8(b"SevenOut"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            278,
            80000000,
            string::utf8(b"https://chaincasino.apt/seven-out"),
            string::utf8(
                b"https://chaincasino.apt/icons/seven-out.png"
            ),
            string::utf8(b"SevenOut Dice Game with a 2:1 payout")
        );

        SevenOut::initialize_game(&seven_out_signer);

        // Try to bet below minimum - should fail
        SevenOut::test_only_play_seven_out(&player, true, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = seven_out_game::SevenOut::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_high() {
        let (_, casino_signer, seven_out_signer, whale_investor, player) =
            setup_seven_out_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SEVEN_OUT_ADDR,
            string::utf8(b"SevenOut"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            278,
            80000000,
            string::utf8(b"https://chaincasino.apt/seven-out"),
            string::utf8(
                b"https://chaincasino.apt/icons/seven-out.png"
            ),
            string::utf8(b"SevenOut Dice Game with a 2:1 payout")
        );

        SevenOut::initialize_game(&seven_out_signer);

        // Try to bet above maximum - should fail
        SevenOut::test_only_play_seven_out(&player, false, MAX_BET + 1);
    }

    #[test]
    #[expected_failure(abort_code = seven_out_game::SevenOut::E_UNAUTHORIZED)]
    fun test_unauthorized_initialization() {
        let (_, _, _, _, player) = setup_seven_out_ecosystem();

        // Try to initialize with wrong signer - should fail
        SevenOut::initialize_game(&player);
    }

    #[test]
    #[expected_failure(abort_code = seven_out_game::SevenOut::E_ALREADY_INITIALIZED)]
    fun test_double_initialization() {
        let (_, casino_signer, seven_out_signer, whale_investor, _) =
            setup_seven_out_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SEVEN_OUT_ADDR,
            string::utf8(b"SevenOut"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            278,
            80000000,
            string::utf8(b"https://chaincasino.apt/seven-out"),
            string::utf8(
                b"https://chaincasino.apt/icons/seven-out.png"
            ),
            string::utf8(b"SevenOut Dice Game with a 2:1 payout")
        );

        SevenOut::initialize_game(&seven_out_signer);

        // Try to initialize again - should fail
        SevenOut::initialize_game(&seven_out_signer);
    }

    #[test]
    fun test_comprehensive_bet_scenarios() {
        let (_, casino_signer, seven_out_signer, whale_investor, player) =
            setup_seven_out_ecosystem();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            SEVEN_OUT_ADDR,
            string::utf8(b"SevenOut"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            278,
            80000000,
            string::utf8(b"https://chaincasino.apt/seven-out"),
            string::utf8(
                b"https://chaincasino.apt/icons/seven-out.png"
            ),
            string::utf8(b"SevenOut Dice Game with a 2:1 payout")
        );

        SevenOut::initialize_game(&seven_out_signer);

        // Test multiple bets with different amounts
        let bet_amounts = vector[MIN_BET, STANDARD_BET, MAX_BET];
        let i = 0;
        while (i < vector::length(&bet_amounts)) {
            let amount = *vector::borrow(&bet_amounts, i);

            // Test over bet (true)
            SevenOut::test_only_play_seven_out(&player, true, amount);
            assert!(SevenOut::has_game_result(PLAYER_ADDR), 100 + i);

            // Clear result
            SevenOut::clear_game_result(&player);

            // Test under bet (false)
            SevenOut::test_only_play_seven_out(&player, false, amount);
            assert!(SevenOut::has_game_result(PLAYER_ADDR), 200 + i);

            // Clear result for next iteration
            SevenOut::clear_game_result(&player);

            i = i + 1;
        };

        // Verify system is still stable
        assert!(SevenOut::is_ready(), 300);
    }
}
