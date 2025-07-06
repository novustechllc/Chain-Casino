#[test_only]
module aptos_fortune::aptos_fortune_tests {
    use std::signer;
    use std::string;
    use std::option;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::CasinoHouse;
    use casino::InvestorToken;
    use aptos_fortune::AptosFortune;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const GAME_ADDR: address = @aptos_fortune;
    const PLAYER_ADDR: address = @0xA1B2C3D4E5F6;
    const INVESTOR_ADDR: address = @0xF1E2D3C4B5A6;

    // Betting constants
    const MIN_BET: u64 = 10000000; // 0.1 APT
    const MAX_BET: u64 = 100000000; // 1 APT
    const STANDARD_BET: u64 = 50000000; // 0.5 APT
    const LARGE_FUNDING: u64 = 20000000000; // 200 APT - FIXED: Increased for casino treasury requirements

    fun setup_test_environment(): (signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let game_signer = account::create_account_for_test(GAME_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);
        let investor = account::create_account_for_test(INVESTOR_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores for all addresses - CRITICAL FIX
        let aptos_metadata =
            option::extract(&mut coin::paired_metadata<aptos_coin::AptosCoin>());
        let all_addresses = vector[CASINO_ADDR, GAME_ADDR, PLAYER_ADDR, INVESTOR_ADDR];
        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts - now safe because stores exist
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, LARGE_FUNDING);
        aptos_coin::mint(&aptos_framework, INVESTOR_ADDR, LARGE_FUNDING);

        (casino_signer, game_signer, player, investor)
    }

    #[test]
    fun test_game_initialization_and_basic_mechanics() {
        let (casino_signer, game_signer, _player, investor) = setup_test_environment();

        // === PHASE 1: INITIALIZE CASINO ECOSYSTEM ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Fund treasury
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        // === PHASE 2: REGISTER APTOS FORTUNE ===
        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200, // 22% house edge
            2000000000, // 20 APT max payout
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine with frequent wins and partial matches")
        );

        // === PHASE 3: INITIALIZE GAME ===
        AptosFortune::initialize_game_for_test(&game_signer);

        // === PHASE 4: VERIFY GAME IS READY ===
        assert!(AptosFortune::is_ready(), 1);

        // === PHASE 5: VERIFY GAME CONFIGURATION ===
        let (min_bet, max_bet, house_edge, max_payout) = AptosFortune::get_game_config();
        assert!(min_bet == MIN_BET, 2);
        assert!(max_bet == MAX_BET, 3);
        assert!(house_edge == 2200, 4);
        assert!(max_payout == 2000000000, 5);

        // === PHASE 6: VERIFY SYMBOL PROBABILITIES ===
        let (cherry_p, bell_p, coin_p, star_p, diamond_p) =
            AptosFortune::get_symbol_probabilities();
        assert!(cherry_p == 35, 6);
        assert!(bell_p == 30, 7);
        assert!(coin_p == 25, 8);
        assert!(star_p == 8, 9);
        assert!(diamond_p == 2, 10);

        // === PHASE 7: VERIFY PAYOUT TABLE ===
        let (
            cherry_pay,
            bell_pay,
            coin_pay,
            star_pay,
            diamond_pay,
            partial_pay,
            consolation_pay
        ) = AptosFortune::get_payout_table();
        assert!(cherry_pay == 3, 11);
        assert!(bell_pay == 4, 12);
        assert!(coin_pay == 6, 13);
        assert!(star_pay == 12, 14);
        assert!(diamond_pay == 20, 15);
        assert!(partial_pay == 50, 16); // 0.5x bet
        assert!(consolation_pay == 10, 17); // 0.1x bet

        // === PHASE 8: VERIFY GAME INFO ===
        let (creator, _game_object, name, version) = AptosFortune::get_game_info();
        assert!(creator == GAME_ADDR, 18);
        assert!(name == string::utf8(b"AptosFortune"), 19);
        assert!(version == string::utf8(b"v1"), 20);

        // === PHASE 9: VERIFY GAME IS READY ===
        assert!(AptosFortune::is_ready(), 21);
    }

    #[test]
    fun test_frequent_wins_mechanics() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine with frequent wins")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        let aptos_metadata =
            option::extract(&mut coin::paired_metadata<aptos_coin::AptosCoin>());
        let initial_balance = primary_fungible_store::balance(
            PLAYER_ADDR, aptos_metadata
        );

        // === TEST 1: THREE MATCHING SYMBOLS (FULL PAYOUT) ===
        AptosFortune::test_spin_reels(&player, STANDARD_BET, 1, 1, 1); // Three cherries
        let (
            reel1, reel2, reel3, match_type, matching_symbol, payout, _session, bet_amount
        ) = AptosFortune::get_player_result(PLAYER_ADDR);

        assert!(reel1 == 1 && reel2 == 1 && reel3 == 1, 1);
        assert!(match_type == 3, 2);
        assert!(matching_symbol == 1, 3);
        assert!(payout == STANDARD_BET * 3, 4); // 3x multiplier for cherries
        assert!(bet_amount == STANDARD_BET, 5);

        // === TEST 2: TWO MATCHING SYMBOLS (PARTIAL PAYOUT) ===
        AptosFortune::test_spin_reels(&player, STANDARD_BET, 2, 2, 3); // Two bells, one coin
        let (reel1_2, reel2_2, reel3_2, match_type_2, matching_symbol_2, payout_2, _, _) =
            AptosFortune::get_player_result(PLAYER_ADDR);

        assert!(reel1_2 == 2 && reel2_2 == 2 && reel3_2 == 3, 6);
        assert!(match_type_2 == 2, 7);
        assert!(matching_symbol_2 == 2, 8);
        assert!(payout_2 == (STANDARD_BET * 50) / 100, 9); // 0.5x bet for two matches

        // === TEST 3: ONE MATCHING SYMBOL (CONSOLATION) ===
        AptosFortune::test_spin_reels(&player, STANDARD_BET, 3, 4, 5); // All different
        let (reel1_3, reel2_3, reel3_3, match_type_3, matching_symbol_3, payout_3, _, _) =
            AptosFortune::get_player_result(PLAYER_ADDR);

        assert!(reel1_3 == 3 && reel2_3 == 4 && reel3_3 == 5, 10);
        assert!(match_type_3 == 1, 11);
        assert!(matching_symbol_3 == 5, 12); // Highest symbol (diamond)
        assert!(payout_3 == (STANDARD_BET * 10) / 100, 13); // 0.1x bet consolation

        // === TEST 4: NO MATCHES (RARE CASE) ===
        AptosFortune::test_spin_reels(&player, STANDARD_BET, 1, 2, 3); // All different, low values
        let (reel1_4, reel2_4, reel3_4, match_type_4, matching_symbol_4, payout_4, _, _) =
            AptosFortune::get_player_result(PLAYER_ADDR);

        assert!(reel1_4 == 1 && reel2_4 == 2 && reel3_4 == 3, 14);
        assert!(match_type_4 == 1, 15); // Still gets consolation
        assert!(matching_symbol_4 == 3, 16); // Highest symbol (coin)
        assert!(payout_4 == (STANDARD_BET * 10) / 100, 17); // 0.1x bet consolation

        // === TEST 5: DIAMOND JACKPOT (MAXIMUM PAYOUT) ===
        AptosFortune::test_spin_reels(&player, MAX_BET, 5, 5, 5); // Three diamonds
        let (reel1_5, reel2_5, reel3_5, match_type_5, matching_symbol_5, payout_5, _, _) =
            AptosFortune::get_player_result(PLAYER_ADDR);

        assert!(reel1_5 == 5 && reel2_5 == 5 && reel3_5 == 5, 18);
        assert!(match_type_5 == 3, 19);
        assert!(matching_symbol_5 == 5, 20);
        assert!(payout_5 == MAX_BET * 20, 21); // 20x multiplier = 20 APT

        // Verify balance changes reflect frequent wins
        let final_balance = primary_fungible_store::balance(PLAYER_ADDR, aptos_metadata);

        // Player should have gained money due to frequent wins in tests
        assert!(final_balance > initial_balance, 22);
    }

    #[test]
    fun test_payout_calculations() {
        let bet = 50000000; // 0.5 APT

        // Test 3-match payouts
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 3) == bet * 3,
            1
        ); // Cherry
        assert!(
            AptosFortune::calculate_potential_payout(bet, 2, 3) == bet * 4,
            2
        ); // Bell
        assert!(
            AptosFortune::calculate_potential_payout(bet, 3, 3) == bet * 6,
            3
        ); // Coin
        assert!(
            AptosFortune::calculate_potential_payout(bet, 4, 3) == bet * 12,
            4
        ); // Star
        assert!(
            AptosFortune::calculate_potential_payout(bet, 5, 3) == bet * 20,
            5
        ); // Diamond

        // Test 2-match payout
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 2) == (bet * 50) / 100,
            6
        );

        // Test 1-match payout
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 1) == (bet * 10) / 100,
            7
        );

        // Test no match
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 0) == 0,
            8
        );
    }

    #[test]
    fun test_symbol_display_functions() {
        // Test symbol names
        assert!(AptosFortune::get_symbol_name(1) == b"Cherry", 1);
        assert!(AptosFortune::get_symbol_name(2) == b"Bell", 2);
        assert!(AptosFortune::get_symbol_name(3) == b"Coin", 3);
        assert!(AptosFortune::get_symbol_name(4) == b"Star", 4);
        assert!(AptosFortune::get_symbol_name(5) == b"Diamond", 5);
        assert!(AptosFortune::get_symbol_name(99) == b"Unknown", 6);

        // Test symbol characters
        assert!(AptosFortune::get_symbol_char(1) == b"C", 7);
        assert!(AptosFortune::get_symbol_char(2) == b"B", 8);
        assert!(AptosFortune::get_symbol_char(3) == b"O", 9);
        assert!(AptosFortune::get_symbol_char(4) == b"S", 10);
        assert!(AptosFortune::get_symbol_char(5) == b"D", 11);
        assert!(AptosFortune::get_symbol_char(99) == b"?", 12);
    }

    #[test]
    #[expected_failure(abort_code = aptos_fortune::AptosFortune::E_INVALID_AMOUNT)]
    fun test_bet_too_low() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();

        // Setup game
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Try to bet below minimum
        AptosFortune::test_spin_reels(&player, MIN_BET - 1, 1, 1, 1);
    }

    #[test]
    #[expected_failure(abort_code = aptos_fortune::AptosFortune::E_INVALID_AMOUNT)]
    fun test_bet_too_high() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();

        // Setup game
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Try to bet above maximum
        AptosFortune::test_spin_reels(&player, MAX_BET + 1, 1, 1, 1);
    }

    #[test]
    #[expected_failure(abort_code = aptos_fortune::AptosFortune::E_ALREADY_INITIALIZED)]
    fun test_double_initialization() {
        let (casino_signer, game_signer, _player, investor) = setup_test_environment();

        // Setup game
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Try to initialize again
        AptosFortune::initialize_game_for_test(&game_signer);
    }

    #[test]
    #[expected_failure(abort_code = aptos_fortune::AptosFortune::E_UNAUTHORIZED)]
    fun test_unauthorized_initialization() {
        let (_casino_signer, _game_signer, player, _investor) = setup_test_environment();

        // Try to initialize with wrong signer (should fail authorization check)
        AptosFortune::initialize_game_for_test(&player);
    }

    #[test]
    fun test_is_ready_when_not_initialized() {
        // Test is_ready when GameRegistry doesn't exist
        assert!(!AptosFortune::is_ready(), 1);
    }

    #[test]
    #[lint::allow_unsafe_randomness]
    fun test_production_spin_reels() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine with real randomness")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Test production spin_reels function with real randomness
        AptosFortune::test_only_spin_reels(&player, STANDARD_BET);

        // Verify result was stored
        let (
            reel1,
            reel2,
            reel3,
            match_type,
            _matching_symbol,
            _payout,
            _session,
            bet_amount
        ) = AptosFortune::get_player_result(signer::address_of(&player));

        // Should have valid reel results (1-5)
        assert!(reel1 >= 1 && reel1 <= 5, 1);
        assert!(reel2 >= 1 && reel2 <= 5, 2);
        assert!(reel3 >= 1 && reel3 <= 5, 3);
        assert!(match_type <= 3, 4);
        assert!(bet_amount == STANDARD_BET, 5);
    }

    #[test]
    fun test_clear_result() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();
        let player_addr = signer::address_of(&player);

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Play a game to create a result
        AptosFortune::test_spin_reels(&player, STANDARD_BET, 1, 2, 3);

        // Verify result exists
        let (reel1, _, _, _, _, _, _, _) = AptosFortune::get_player_result(player_addr);
        assert!(reel1 == 1, 1);

        // Clear the result
        AptosFortune::clear_result(&player);

        // Verify result is cleared (should return zeros)
        let (
            reel1_after,
            reel2_after,
            reel3_after,
            match_type_after,
            matching_symbol_after,
            payout_after,
            session_after,
            bet_after
        ) = AptosFortune::get_player_result(player_addr);
        assert!(reel1_after == 0, 2);
        assert!(reel2_after == 0, 3);
        assert!(reel3_after == 0, 4);
        assert!(match_type_after == 0, 5);
        assert!(matching_symbol_after == 0, 6);
        assert!(payout_after == 0, 7);
        assert!(session_after == 0, 8);
        assert!(bet_after == 0, 9);
    }

    #[test]
    fun test_clear_result_when_no_result_exists() {
        let (casino_signer, game_signer, player, investor) = setup_test_environment();

        // Setup complete ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Try to clear result when none exists (should not fail)
        AptosFortune::clear_result(&player);
    }

    #[test]
    fun test_edge_case_payout_calculations() {
        let bet = 50000000; // 0.5 APT

        // Test edge case: invalid symbol should return 0 multiplier
        assert!(
            AptosFortune::calculate_potential_payout(bet, 99, 3) == 0,
            1
        );

        // Test edge case: 0 match type
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 0) == 0,
            2
        );

        // Test all valid 3-match combinations
        assert!(
            AptosFortune::calculate_potential_payout(bet, 1, 3) == bet * 3,
            3
        ); // Cherry
        assert!(
            AptosFortune::calculate_potential_payout(bet, 2, 3) == bet * 4,
            4
        ); // Bell
        assert!(
            AptosFortune::calculate_potential_payout(bet, 3, 3) == bet * 6,
            5
        ); // Coin
        assert!(
            AptosFortune::calculate_potential_payout(bet, 4, 3) == bet * 12,
            6
        ); // Star
        assert!(
            AptosFortune::calculate_potential_payout(bet, 5, 3) == bet * 20,
            7
        ); // Diamond
    }

    #[test]
    fun test_get_casino_game_object_coverage() {
        let (casino_signer, game_signer, _player, investor) = setup_test_environment();

        // Setup game
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&investor, LARGE_FUNDING);

        CasinoHouse::register_game(
            &casino_signer,
            GAME_ADDR,
            string::utf8(b"AptosFortune"),
            string::utf8(b"v1"),
            MIN_BET,
            MAX_BET,
            2200,
            2000000000,
            string::utf8(b"https://chaincasino.apt/aptos-fortune"),
            string::utf8(
                b"https://chaincasino.apt/icons/fortune.png"
            ),
            string::utf8(b"Premium slot machine")
        );

        AptosFortune::initialize_game_for_test(&game_signer);

        // Test get_casino_game_object function
        let game_object = AptosFortune::get_casino_game_object();

        // Verify it's a valid object by checking if it's registered
        assert!(CasinoHouse::is_game_registered(game_object), 1);
    }
}
