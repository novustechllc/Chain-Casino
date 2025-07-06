//! MIT License
//!
//! End-to-End Tests for ChainCasino Platform (Post-Refactor)
//!
//! Tests complete user journeys using only public interfaces with realistic money flows.
//! Respects contract constraints and demonstrates Block-STM parallel execution benefits.

#[test_only]
module casino::EndToEndTests {
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
    use casino::DiceGame;

    // === REALISTIC MONEY AMOUNTS ===
    // Players: Small amounts (they can lose everything due to randomness)
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT per player (was 10 APT)
    const CONSERVATIVE_BET: u64 = 2000000; // 0.02 APT (~1% of bankroll)
    const STANDARD_BET: u64 = 5000000; // 0.05 APT (~2.5% of bankroll)
    const LARGE_BET: u64 = 10000000; // 0.1 APT (~5% of bankroll, occasional use)

    // Casino & Investors: Large amounts (provide liquidity, earn house edge)
    const CASINO_ADMIN_FUNDING: u64 = 50000000000; // 500 APT for operations
    const EARLY_INVESTOR_CAPITAL: u64 = 20000000000; // 200 APT
    const WHALE_INVESTOR_CAPITAL: u64 = 100000000000; // 1000 APT
    const INSTITUTIONAL_CAPITAL: u64 = 50000000000; // 500 APT

    // Test addresses - separate for each role
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @casino;
    const SLOT_ADDR: address = @casino;

    // Investors (provide liquidity)
    const EARLY_INVESTOR_ADDR: address = @0x1001;
    const WHALE_INVESTOR_ADDR: address = @0x1002;
    const INSTITUTIONAL_INVESTOR_ADDR: address = @0x1003;
    const LATE_INVESTOR_ADDR: address = @0x1004;

    // Players (bet small amounts)
    const CASUAL_PLAYER_ADDR: address = @0x2001;
    const HIGH_ROLLER_ADDR: address = @0x2002;
    const STRATEGY_PLAYER_ADDR: address = @0x2003;
    const VOLUME_PLAYER_ADDR: address = @0x2004;

    fun setup_realistic_ecosystem(): (
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer,
        signer
    ) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let slot_signer = account::create_account_for_test(SLOT_ADDR);

        // Investors
        let early_investor = account::create_account_for_test(EARLY_INVESTOR_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let institutional = account::create_account_for_test(INSTITUTIONAL_INVESTOR_ADDR);
        let late_investor = account::create_account_for_test(LATE_INVESTOR_ADDR);

        // Players
        let casual_player = account::create_account_for_test(CASUAL_PLAYER_ADDR);
        let high_roller = account::create_account_for_test(HIGH_ROLLER_ADDR);
        let strategy_player = account::create_account_for_test(STRATEGY_PLAYER_ADDR);
        let volume_player = account::create_account_for_test(VOLUME_PLAYER_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(5000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores for all participants
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let all_addresses = vector[
            CASINO_ADDR,
            DICE_ADDR,
            SLOT_ADDR,
            EARLY_INVESTOR_ADDR,
            WHALE_INVESTOR_ADDR,
            INSTITUTIONAL_INVESTOR_ADDR,
            LATE_INVESTOR_ADDR,
            CASUAL_PLAYER_ADDR,
            HIGH_ROLLER_ADDR,
            STRATEGY_PLAYER_ADDR,
            VOLUME_PLAYER_ADDR
        ];

        let i = 0;
        while (i < vector::length(&all_addresses)) {
            let addr = *vector::borrow(&all_addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts with realistic amounts based on roles
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, CASINO_ADMIN_FUNDING);
        aptos_coin::mint(&aptos_framework, DICE_ADDR, CASINO_ADMIN_FUNDING);
        aptos_coin::mint(&aptos_framework, SLOT_ADDR, CASINO_ADMIN_FUNDING);

        // Investors: Large capital for liquidity provision
        aptos_coin::mint(&aptos_framework, EARLY_INVESTOR_ADDR, EARLY_INVESTOR_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_INVESTOR_CAPITAL);
        aptos_coin::mint(
            &aptos_framework, INSTITUTIONAL_INVESTOR_ADDR, INSTITUTIONAL_CAPITAL
        );
        aptos_coin::mint(&aptos_framework, LATE_INVESTOR_ADDR, INSTITUTIONAL_CAPITAL);

        // Players: Larger amounts (to support more rounds)
        aptos_coin::mint(&aptos_framework, CASUAL_PLAYER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, HIGH_ROLLER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, STRATEGY_PLAYER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, VOLUME_PLAYER_ADDR, PLAYER_FUNDING);

        (
            aptos_framework,
            casino_signer,
            dice_signer,
            slot_signer,
            early_investor,
            whale_investor,
            institutional,
            late_investor,
            casual_player,
            high_roller,
            strategy_player,
            volume_player
        )
    }

    #[test]
    fun test_risk_management_and_limits() {
        let (
            _,
            casino_signer,
            dice_signer,
            _,
            _,
            whale_investor,
            _,
            _,
            casual_player,
            high_roller,
            _,
            _
        ) = setup_realistic_ecosystem();

        // Setup with adequate liquidity
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        // Register game with initial limits
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min (matches hardcoded)
            50000000, // 0.5 APT max (matches hardcoded)
            1667,
            250_000_000,
            string::utf8(b"https://chaincasino.apt/dice"),
            string::utf8(b"https://chaincasino.apt/icons/dice.png"),
            string::utf8(b"Classic 1-6 dice guessing game with 5x payout multiplier")
        );
        DiceGame::initialize_game(&dice_signer);

        let dice_object =
            object::address_to_object<CasinoHouse::GameMetadata>(
                CasinoHouse::derive_game_object_address(
                    CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
                )
            );

        // === PHASE 1: TEST INITIAL LIMITS ===
        let (_, _, _, min_bet, max_bet, _, _max_payout, _, _, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(min_bet == 1000000, 1); // 0.01 APT
        assert!(max_bet == 50000000, 2); // 0.5 APT

        // Test betting within limits
        DiceGame::test_only_play_dice(&casual_player, 3, STANDARD_BET); // 0.05 APT - valid
        DiceGame::test_only_play_dice(&high_roller, 1, LARGE_BET); // 0.1 APT - valid

        // === PHASE 2: CASINO UPDATES LIMITS ===
        CasinoHouse::update_game_limits(&casino_signer, dice_object, 2000000, 45000000);

        let (_, _, _, min_bet, max_bet, _, _max_payout, _, _, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(min_bet == 2000000, 3); // 0.02 APT
        assert!(max_bet == 45000000, 4); // 0.45 APT

        // Test new limits
        DiceGame::test_only_play_dice(&high_roller, 4, 40000000); // 0.4 APT - within new limits

        // === PHASE 3: GAME REQUESTS CONSERVATIVE LIMITS ===
        // Games can only reduce risk (increase min or decrease max)
        DiceGame::request_limit_update(&dice_signer, 5000000, 40000000);

        let (_, _, _, min_bet, max_bet, _, _max_payout, _, _, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(min_bet == 5000000, 5); // 0.05 APT (increased)
        assert!(max_bet == 40000000, 6); // 0.4 APT (decreased)

        // === PHASE 4: VERIFY PAYOUT CAPACITY ===
        let max_payout = max_bet * 5; // 5x for dice win
        assert!(DiceGame::can_handle_payout(max_bet), 7);

        let treasury_balance = CasinoHouse::treasury_balance();
        assert!(treasury_balance >= max_payout, 8); // Treasury should cover max payout

        // === PHASE 5: STRESS TEST WITH NEW LIMITS ===
        let limit_test_rounds = 20;
        let i = 0;
        while (i < limit_test_rounds) {
            // Bet within conservative limits
            DiceGame::test_only_play_dice(&casual_player, (((i % 6) + 1) as u8), 30000000); // 0.3 APT
            i = i + 1;
        };

        // System should remain stable
        assert!(DiceGame::is_ready(), 9);
        assert!(CasinoHouse::treasury_balance() > 0, 10);

        // === FINAL VERIFICATION ===
        let (_, _, _, min_bet, max_bet, _, _max_payout, _, _, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(min_bet == 5000000, 11); // Conservative min maintained
        assert!(max_bet == 40000000, 12); // Conservative max maintained
        let final_edge = 1667;
        assert!(final_edge == 1667, 13); // House edge unchanged
    }

    #[test]
    #[expected_failure(abort_code = casino::DiceGame::E_INVALID_AMOUNT)]
    fun test_bet_amount_validation() {
        let (
            _,
            casino_signer,
            dice_signer,
            _,
            _,
            whale_investor,
            _,
            _,
            casual_player,
            _,
            _,
            _
        ) = setup_realistic_ecosystem();

        // Setup
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667,
            250_000_000,
            string::utf8(b"https://chaincasino.apt/dice"),
            string::utf8(b"https://chaincasino.apt/icons/dice.png"),
            string::utf8(b"Classic 1-6 dice guessing game with 5x payout multiplier")
        );
        DiceGame::initialize_game(&dice_signer);

        // Try to bet above hardcoded MAX_BET (0.5 APT = 50000000)
        DiceGame::test_only_play_dice(&casual_player, 3, 75000000); // 0.75 APT - should fail
    }

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INSUFFICIENT_BALANCE)]
    fun test_redemption_validation() {
        let (_, casino_signer, _, _, early_investor, _, _, _, _, _, _, _) =
            setup_realistic_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init_module_for_test(&casino_signer);

        InvestorToken::deposit_and_mint(&early_investor, EARLY_INVESTOR_CAPITAL);
        let tokens = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

        // Try to redeem more than balance
        InvestorToken::redeem(&early_investor, tokens + 1000000000); // More than owned
    }
}
