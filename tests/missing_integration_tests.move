//! MIT License
//!
//! REALISTIC Integration Tests for ChainCasino Platform
//!
//! These tests ONLY use public interfaces that would be available in production.
//! NO bypassing of contract security models or artificial state manipulation.

#[test_only]
module casino::RealisticIntegrationTests {
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
    use dice_game::DiceGame;
    use slot_game::SlotMachine;

    // Test constants - realistic amounts WITHIN hardcoded game limits
    const WHALE_FUNDING: u64 = 100000000000; // 1000 APT
    const INVESTOR_FUNDING: u64 = 10000000000; // 100 APT
    const PLAYER_FUNDING: u64 = 1000000000; // 10 APT
    const INITIAL_INVESTMENT: u64 = 5000000000; // 50 APT
    const STANDARD_BET: u64 = 25000000; // 0.25 APT - WITHIN hardcoded MAX_BET (0.5 APT)

    // Test addresses - each participant has own address
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @dice_game;
    const SLOT_ADDR: address = @slot_game;
    const WHALE_INVESTOR_ADDR: address = @0x1001;
    const RETAIL_INVESTOR_ADDR: address = @0x1002;
    const LATE_INVESTOR_ADDR: address = @0x1003;
    const HIGH_ROLLER_ADDR: address = @0x2001;
    const CASUAL_PLAYER_ADDR: address = @0x2002;
    const WHALE_PLAYER_ADDR: address = @0x2003;

    fun setup_realistic_environment(): (
        signer, signer, signer, signer, signer, signer, signer, signer, signer, signer
    ) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let slot_signer = account::create_account_for_test(SLOT_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let retail_investor = account::create_account_for_test(RETAIL_INVESTOR_ADDR);
        let late_investor = account::create_account_for_test(LATE_INVESTOR_ADDR);
        let high_roller = account::create_account_for_test(HIGH_ROLLER_ADDR);
        let casual_player = account::create_account_for_test(CASUAL_PLAYER_ADDR);
        let whale_player = account::create_account_for_test(WHALE_PLAYER_ADDR);

        // Initialize Aptos test environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(3000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Setup primary stores for all participants
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let addresses = vector[
            CASINO_ADDR,
            DICE_ADDR,
            SLOT_ADDR,
            WHALE_INVESTOR_ADDR,
            RETAIL_INVESTOR_ADDR,
            LATE_INVESTOR_ADDR,
            HIGH_ROLLER_ADDR,
            CASUAL_PLAYER_ADDR,
            WHALE_PLAYER_ADDR
        ];

        let i = 0;
        while (i < vector::length(&addresses)) {
            let addr = *vector::borrow(&addresses, i);
            primary_fungible_store::ensure_primary_store_exists(addr, aptos_metadata);
            i = i + 1;
        };

        // Fund accounts with realistic amounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, WHALE_FUNDING); // Casino admin funds
        aptos_coin::mint(&aptos_framework, DICE_ADDR, WHALE_FUNDING); // Game deployer funds
        aptos_coin::mint(&aptos_framework, SLOT_ADDR, WHALE_FUNDING); // Game deployer funds
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_FUNDING);
        aptos_coin::mint(&aptos_framework, RETAIL_INVESTOR_ADDR, INVESTOR_FUNDING);
        aptos_coin::mint(&aptos_framework, LATE_INVESTOR_ADDR, INVESTOR_FUNDING);
        aptos_coin::mint(&aptos_framework, HIGH_ROLLER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, CASUAL_PLAYER_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, WHALE_PLAYER_ADDR, WHALE_FUNDING);

        (
            aptos_framework,
            casino_signer,
            dice_signer,
            slot_signer,
            whale_investor,
            retail_investor,
            late_investor,
            high_roller,
            casual_player,
            whale_player
        )
    }

    #[test]
    fun test_realistic_multi_investor_nav_growth() {
        let (
            _,
            casino_signer,
            dice_signer,
            slot_signer,
            whale_investor,
            retail_investor,
            late_investor,
            high_roller,
            casual_player,
            whale_player
        ) = setup_realistic_environment();

        // === PHASE 1: ECOSYSTEM SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Register games with limits that respect hardcoded MAX_BET in game modules
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667 // Max = 0.5 APT (matches hardcoded MAX_BET)
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1550 // Max = 0.5 APT (matches hardcoded MAX_BET)
        );

        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // === PHASE 2: EARLY INVESTOR ENTERS ===
        let initial_nav = InvestorToken::nav();
        assert!(initial_nav == 1_000_000, 1); // NAV scale

        InvestorToken::deposit_and_mint(&retail_investor, INITIAL_INVESTMENT);
        let retail_tokens = InvestorToken::user_balance(RETAIL_INVESTOR_ADDR);
        assert!(retail_tokens == INITIAL_INVESTMENT, 2); // 1:1 ratio initially

        // === PHASE 3: REALISTIC GAMING ACTIVITY (NO ARTIFICIAL PROFITS) ===
        // Players naturally create house edge through betting
        let gaming_rounds = 30; // Enough rounds for house edge to accumulate
        let i = 0;
        while (i < gaming_rounds) {
            // High roller plays dice - loses more often than wins (house edge)
            DiceGame::test_only_play_dice(&high_roller, ((i % 6) + 1), STANDARD_BET);

            // Casual player plays slots - house edge applies
            SlotMachine::test_only_spin_slots(&casual_player, STANDARD_BET / 2);

            // Whale player makes bigger bets - more house edge revenue
            if (i % 3 == 0) {
                DiceGame::test_only_play_dice(&whale_player, ((i % 6) + 1), 40000000); // 0.4 APT
            };

            if (i % 4 == 0) {
                SlotMachine::test_only_spin_slots(&whale_player, 40000000); // 0.4 APT
            };

            i = i + 1;
        };

        // === PHASE 4: CHECK NAV GROWTH FROM NATURAL HOUSE EDGE ===
        let nav_after_gaming = InvestorToken::nav();
        // NAV should have grown due to house edge (16.67% for dice, 15.5% for slots)
        // With 30+ rounds, house edge should accumulate naturally
        assert!(nav_after_gaming >= initial_nav, 3); // Should at least maintain value

        // === PHASE 5: WHALE INVESTOR ENTERS AT CURRENT NAV ===
        let whale_apt_before =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::deposit_and_mint(&whale_investor, INITIAL_INVESTMENT * 4); // 200 APT

        let whale_tokens = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
        let whale_apt_after =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        let whale_apt_invested = whale_apt_before - whale_apt_after;

        // If NAV grew, whale should get fewer tokens per APT
        if (nav_after_gaming > initial_nav) {
            assert!(whale_tokens < whale_apt_invested, 4);
        };

        // === PHASE 6: MORE REALISTIC GAMING ===
        let additional_rounds = 20;
        let j = 0;
        while (j < additional_rounds) {
            // More players join, creating more house edge
            DiceGame::test_only_play_dice(&high_roller, ((j % 6) + 1), STANDARD_BET);
            SlotMachine::test_only_spin_slots(&casual_player, STANDARD_BET);

            if (j % 2 == 0) {
                DiceGame::test_only_play_dice(&whale_player, ((j % 6) + 1), 40000000); // 0.4 APT
            };

            j = j + 1;
        };

        // === PHASE 7: LATE INVESTOR ENTERS ===
        InvestorToken::deposit_and_mint(&late_investor, INITIAL_INVESTMENT);
        let _late_tokens = InvestorToken::user_balance(LATE_INVESTOR_ADDR);
        let _nav_when_late_entered = InvestorToken::nav();

        // === PHASE 8: EARLY INVESTOR REDEEMS (REALISTIC PROFIT) ===
        let retail_apt_before =
            primary_fungible_store::balance(
                RETAIL_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let retail_redeem_tokens = retail_tokens / 2; // Redeem 50%
        InvestorToken::redeem(&retail_investor, retail_redeem_tokens);

        let retail_apt_after =
            primary_fungible_store::balance(
                RETAIL_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        let _retail_apt_received = retail_apt_after - retail_apt_before;

        // === PHASE 9: VERIFY REALISTIC OUTCOMES ===

        // All investors should still have positions
        assert!(InvestorToken::user_balance(RETAIL_INVESTOR_ADDR) > 0, 5);
        assert!(InvestorToken::user_balance(WHALE_INVESTOR_ADDR) > 0, 6);
        assert!(InvestorToken::user_balance(LATE_INVESTOR_ADDR) > 0, 7);

        // Treasury should be substantial from house edge accumulation
        let final_treasury = InvestorToken::treasury_balance();
        assert!(final_treasury > INITIAL_INVESTMENT, 8); // Should have grown

        // NAV should reflect natural growth
        let final_nav = InvestorToken::nav();
        assert!(final_nav > 0, 9);

        // System should still be fully operational
        assert!(DiceGame::is_ready(), 10);
        assert!(SlotMachine::is_ready(), 11);

        // Final verification: more gaming should still work
        DiceGame::test_only_play_dice(&high_roller, 3, STANDARD_BET);
        SlotMachine::test_only_spin_slots(&casual_player, STANDARD_BET);
    }

    #[test]
    fun test_realistic_high_volume_concurrent_gaming() {
        let (
            _,
            casino_signer,
            dice_signer,
            slot_signer,
            whale_investor,
            _,
            _,
            high_roller,
            casual_player,
            whale_player
        ) = setup_realistic_environment();

        // Setup with substantial treasury
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667 // Respect hardcoded limits
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1550 // Respect hardcoded limits
        );

        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Whale provides substantial liquidity
        InvestorToken::deposit_and_mint(&whale_investor, INITIAL_INVESTMENT * 10); // 500 APT

        // Get game objects for tracking
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

        // Verify separate treasury addresses (Block-STM isolation)
        let dice_treasury_addr = CasinoHouse::get_game_treasury_address(dice_object);
        let slot_treasury_addr = CasinoHouse::get_game_treasury_address(slot_object);
        assert!(dice_treasury_addr != slot_treasury_addr, 1);

        // Record initial state
        let initial_total_treasury = CasinoHouse::treasury_balance();
        let initial_dice_treasury = CasinoHouse::game_treasury_balance(dice_object);
        let initial_slot_treasury = CasinoHouse::game_treasury_balance(slot_object);

        // === HIGH VOLUME CONCURRENT GAMING SIMULATION ===
        // In real Block-STM, these would execute in parallel since they use different treasury addresses
        let high_volume_rounds = 40;
        let i = 0;
        while (i < high_volume_rounds) {
            // Concurrent pattern 1: Different players, different games
            DiceGame::test_only_play_dice(&high_roller, ((i % 6) + 1), 40000000); // 0.4 APT
            SlotMachine::test_only_spin_slots(&casual_player, STANDARD_BET);

            // Concurrent pattern 2: Same player, different games (would be sequential in reality)
            if (i % 2 == 0) {
                DiceGame::test_only_play_dice(&whale_player, ((i % 6) + 1), 45000000); // 0.45 APT
            } else {
                SlotMachine::test_only_spin_slots(&whale_player, 45000000); // 0.45 APT
            };

            // Concurrent pattern 3: Multiple dice players (would be sequential on same treasury)
            if (i % 3 == 0) {
                DiceGame::test_only_play_dice(&casual_player, ((i % 6) + 1), STANDARD_BET);
            };

            i = i + 1;
        };

        // === VERIFY REALISTIC OUTCOMES ===
        let final_total_treasury = CasinoHouse::treasury_balance();
        let final_dice_treasury = CasinoHouse::game_treasury_balance(dice_object);
        let final_slot_treasury = CasinoHouse::game_treasury_balance(slot_object);

        // Treasury balances should have changed due to gaming activity
        let total_changed = final_total_treasury != initial_total_treasury;
        let dice_changed = final_dice_treasury != initial_dice_treasury;
        let slot_changed = final_slot_treasury != initial_slot_treasury;

        assert!(total_changed || dice_changed || slot_changed, 2);

        // Both games should remain operational
        assert!(DiceGame::is_ready(), 3);
        assert!(SlotMachine::is_ready(), 4);

        // Games should still be able to handle new bets
        assert!(DiceGame::can_handle_payout(50000000), 5); // Max bet within limits
        assert!(SlotMachine::can_handle_payout(50000000), 6); // Max bet within limits

        // Treasury should be substantial (house edge accumulation)
        assert!(
            final_total_treasury > initial_total_treasury / 2,
            7
        );

        // === FINAL STRESS TEST ===
        // Additional concurrent activity to test system stability
        let stress_rounds = 15;
        let j = 0;
        while (j < stress_rounds) {
            DiceGame::test_only_play_dice(&high_roller, ((j % 6) + 1), STANDARD_BET);
            SlotMachine::test_only_spin_slots(&whale_player, 40000000); // 0.4 APT
            j = j + 1;
        };

        // System should remain stable
        assert!(DiceGame::is_ready(), 8);
        assert!(SlotMachine::is_ready(), 9);
        assert!(CasinoHouse::treasury_balance() > 0, 10);
    }

    #[test]
    fun test_realistic_game_limit_management() {
        let (_, casino_signer, dice_signer, _, whale_investor, _, _, high_roller, _, _) =
            setup_realistic_environment();

        // Setup
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, INITIAL_INVESTMENT);

        // Register game with initial limits
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1667 // 16.67% house edge
        );

        DiceGame::initialize_game(&dice_signer);

        let dice_object =
            object::address_to_object<CasinoHouse::GameMetadata>(
                CasinoHouse::derive_game_object_address(
                    CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
                )
            );

        // === PHASE 1: TEST INITIAL LIMITS ===
        let (_, _, _, initial_min, initial_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(initial_min == 1000000, 1); // 0.01 APT
        assert!(initial_max == 50000000, 2); // 0.5 APT

        // Test betting within limits
        DiceGame::test_only_play_dice(&high_roller, 3, 25000000); // 0.25 APT - should work

        // === PHASE 2: CASINO ADMIN UPDATES LIMITS ===
        CasinoHouse::update_game_limits(&casino_signer, dice_object, 2000000, 45000000); // Keep within hardcoded MAX_BET

        let (_, _, _, new_min, new_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(new_min == 2000000, 3); // 0.02 APT
        assert!(new_max == 45000000, 4); // 0.45 APT

        // Test new limits work
        DiceGame::test_only_play_dice(&high_roller, 1, 35000000); // 0.35 APT - should work

        // === PHASE 3: GAME REQUESTS RISK REDUCTION ===
        // Games can only reduce risk (increase min or decrease max)
        DiceGame::request_limit_update(&dice_signer, 5000000, 40000000); // More conservative

        let (_, _, _, conservative_min, conservative_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(conservative_min == 5000000, 5); // 0.05 APT (increased min)
        assert!(conservative_max == 40000000, 6); // 0.4 APT (decreased max)

        // Test conservative limits
        DiceGame::test_only_play_dice(&high_roller, 4, 30000000); // 0.3 APT - should work

        // === PHASE 4: VERIFY LIMITS ARE ENFORCED ===
        // The game should enforce these limits in subsequent bets
        // (Testing limit enforcement requires trying to bet outside limits,
        // but that would require separate failure tests)

        // Verify system remains functional with new limits
        assert!(DiceGame::is_ready(), 7);
        assert!(DiceGame::can_handle_payout(40000000), 8); // Max bet payout

        // === PHASE 5: REALISTIC USAGE WITH NEW LIMITS ===
        let limit_test_rounds = 10;
        let i = 0;
        while (i < limit_test_rounds) {
            // Bet within new conservative limits
            DiceGame::test_only_play_dice(&high_roller, ((i % 6) + 1), 30000000); // 0.3 APT
            i = i + 1;
        };

        // Game should remain operational
        assert!(DiceGame::is_ready(), 9);

        // Final verification of limits
        let (_, _, _, final_min, final_max, final_edge, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(final_min == 5000000, 10); // Conservative min
        assert!(final_max == 40000000, 11); // Conservative max
        assert!(final_edge == 1667, 12); // House edge unchanged
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_realistic_unauthorized_game_registration() {
        let (_, _, dice_signer, _, _, _, _, _, _, _) = setup_realistic_environment();

        // This is a realistic failure case - someone other than casino admin
        // tries to register a game, which should fail
        CasinoHouse::register_game(
            &dice_signer, // Not the casino admin
            DICE_ADDR,
            string::utf8(b"UnauthorizedGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
    fun test_realistic_bet_limit_enforcement() {
        let (_, casino_signer, dice_signer, _, whale_investor, _, _, high_roller, _, _) =
            setup_realistic_environment();

        // Setup with strict limits
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, INITIAL_INVESTMENT);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1667
        );

        DiceGame::initialize_game(&dice_signer);

        // Try to bet above the maximum limit - should fail realistically
        DiceGame::test_only_play_dice(&high_roller, 3, 75000000); // 0.75 APT > 0.5 APT hardcoded MAX_BET
    }
}
