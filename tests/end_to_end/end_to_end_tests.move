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
    use dice_game::DiceGame;
    use slot_game::SlotMachine;

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
    const DICE_ADDR: address = @dice_game;
    const SLOT_ADDR: address = @slot_game;

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
    fun test_complete_ecosystem_lifecycle() {
        let (
            _,
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
        ) = setup_realistic_ecosystem();

        // === PHASE 1: ECOSYSTEM BOOTSTRAP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Verify clean initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(InvestorToken::total_supply() == 0, 2);
        assert!(InvestorToken::nav() == 1_000_000, 3); // NAV at scale

        // === PHASE 2: GAME ECOSYSTEM SETUP ===

        // Casino registers games with realistic limits (respecting hardcoded MAX_BET = 0.5 APT)
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min (matches hardcoded MIN_BET)
            50000000, // 0.5 APT max (matches hardcoded MAX_BET)
            1667 // 16.67% house edge
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1550 // 15.5% house edge
        );

        // Games initialize and claim capabilities (proper initialization flow)
        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Verify games are operational
        assert!(DiceGame::is_ready(), 4);
        assert!(SlotMachine::is_ready(), 5);

        // Verify Block-STM treasury isolation
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

        let dice_treasury_addr = CasinoHouse::get_game_treasury_address(dice_object);
        let slot_treasury_addr = CasinoHouse::get_game_treasury_address(slot_object);
        assert!(dice_treasury_addr != slot_treasury_addr, 6); // Separate addresses = parallel execution

        // === PHASE 3: TREASURY FUNDING (EARLY INVESTOR ADVANTAGE) ===

        // Early investor gets in at NAV = 1.0 (best price)
        let initial_nav = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&early_investor, EARLY_INVESTOR_CAPITAL);

        let early_tokens = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        assert!(early_tokens == EARLY_INVESTOR_CAPITAL, 7); // 1:1 ratio initially

        // Treasury should reflect investment
        let treasury_after_early = CasinoHouse::treasury_balance();
        assert!(treasury_after_early >= EARLY_INVESTOR_CAPITAL, 8);

        // === PHASE 4: WHALE PROVIDES MASSIVE LIQUIDITY ===

        // Whale investor provides major liquidity for high-stakes gaming
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        let whale_tokens = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
        let total_supply_after_whale = InvestorToken::total_supply();
        let treasury_after_whale = CasinoHouse::treasury_balance();

        assert!(
            treasury_after_whale >= EARLY_INVESTOR_CAPITAL + WHALE_INVESTOR_CAPITAL,
            9
        );
        assert!(
            total_supply_after_whale == early_tokens + whale_tokens,
            10
        );

        // === PHASE 5: HIGH-VOLUME GAMING CREATES HOUSE EDGE ===
        // Multiple players create sustained gaming activity
        // This simulates real casino activity where house edge accumulates over time
        let gaming_rounds = 15; // Sustainable rounds
        let planned_bets = gaming_rounds * LARGE_BET; // Max bet per player per round
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        // Bankroll checks for all players
        assert!(
            primary_fungible_store::balance(CASUAL_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(HIGH_ROLLER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(STRATEGY_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(VOLUME_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        let i = 0;
        while (i < gaming_rounds) {
            // Casual player: small consistent bets
            if (i % 4 == 0) {
                DiceGame::test_only_play_dice(
                    &casual_player,
                    (((i % 6) + 1) as u8),
                    CONSERVATIVE_BET
                );
            };
            // High roller: larger bets, more variance
            if (i % 3 == 0) {
                DiceGame::test_only_play_dice(
                    &high_roller, (((i % 6) + 1) as u8), LARGE_BET
                );
            };
            // Strategy player: alternates between games
            if (i % 2 == 0) {
                SlotMachine::test_only_spin_slots(&strategy_player, STANDARD_BET);
            } else {
                DiceGame::test_only_play_dice(
                    &strategy_player,
                    (((i % 6) + 1) as u8),
                    STANDARD_BET
                );
            };
            // Volume player: consistent slot activity
            SlotMachine::test_only_spin_slots(&volume_player, CONSERVATIVE_BET);
            i = i + 1;
        };

        // === PHASE 6: NAV GROWTH FROM HOUSE EDGE ===

        let nav_after_gaming = InvestorToken::nav();
        let treasury_after_gaming = CasinoHouse::treasury_balance();

        // House edge should accumulate (NAV may increase, treasury balance may change)
        // Note: Due to randomness, we can't guarantee profit, but system should be stable
        assert!(treasury_after_gaming > 0, 11);
        assert!(nav_after_gaming > 0, 12);

        // === PHASE 7: INSTITUTIONAL INVESTOR ENTERS AT CURRENT NAV ===

        // Institutional investor enters after house edge accumulation
        let nav_before_institutional = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&institutional, INSTITUTIONAL_CAPITAL);

        let institutional_tokens =
            InvestorToken::user_balance(INSTITUTIONAL_INVESTOR_ADDR);

        // If NAV increased, institutional should get fewer tokens per APT
        if (nav_before_institutional > initial_nav) {
            assert!(institutional_tokens < INSTITUTIONAL_CAPITAL, 13);
        };

        // === PHASE 8: LATE INVESTOR TIMING STUDY ===
        // Additional gaming to further change NAV
        let additional_rounds = 10;
        let j = 0;
        while (j < additional_rounds) {
            DiceGame::test_only_play_dice(&high_roller, (((j % 6) + 1) as u8), LARGE_BET);
            SlotMachine::test_only_spin_slots(&casual_player, STANDARD_BET);
            j = j + 1;
        };

        let nav_before_late = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&late_investor, INSTITUTIONAL_CAPITAL);
        let late_tokens = InvestorToken::user_balance(LATE_INVESTOR_ADDR);

        // === PHASE 9: PROFIT REALIZATION (EARLY INVESTOR ADVANTAGE) ===

        // Early investor redeems 50% of position to realize profits
        let early_apt_before =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let early_redeem_tokens = early_tokens / 2;
        InvestorToken::redeem(&early_investor, early_redeem_tokens);

        let early_apt_after =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let early_apt_received = early_apt_after - early_apt_before;
        // Early investor should receive APT (potentially at profit if NAV increased)
        assert!(early_apt_received > 0, 14);

        // === PHASE 10: CONTINUED OPERATIONS STRESS TEST ===
        // System should remain stable and operational after redemptions
        let stress_rounds = 10;
        let k = 0;
        while (k < stress_rounds) {
            // Multi-player concurrent activity (simulates Block-STM benefits)
            DiceGame::test_only_play_dice(
                &casual_player,
                (((k % 6) + 1) as u8),
                CONSERVATIVE_BET
            );
            SlotMachine::test_only_spin_slots(&high_roller, STANDARD_BET);
            if (k % 2 == 0) {
                DiceGame::test_only_play_dice(
                    &strategy_player, (((k % 6) + 1) as u8), LARGE_BET
                );
            };
            k = k + 1;
        };

        // === PHASE 11: FINAL SYSTEM VALIDATION ===

        let final_treasury = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();
        let final_supply = InvestorToken::total_supply();

        // System should be stable and operational
        assert!(final_treasury > 0, 15);
        assert!(final_nav > 0, 16);
        assert!(final_supply > 0, 17);

        // All investors should still have positions
        assert!(InvestorToken::user_balance(EARLY_INVESTOR_ADDR) > 0, 18); // 50% remaining
        assert!(InvestorToken::user_balance(WHALE_INVESTOR_ADDR) > 0, 19);
        assert!(InvestorToken::user_balance(INSTITUTIONAL_INVESTOR_ADDR) > 0, 20);
        assert!(InvestorToken::user_balance(LATE_INVESTOR_ADDR) > 0, 21);

        // Games should remain operational
        assert!(DiceGame::is_ready(), 22);
        assert!(SlotMachine::is_ready(), 23);

        // Treasury should support ongoing operations
        assert!(DiceGame::can_handle_payout(LARGE_BET * 5), 24); // 5x max dice payout
        assert!(SlotMachine::can_handle_payout(LARGE_BET * 100), 25); // 100x max slot payout

        // === FINAL VERIFICATION: TREASURY COMPOSITION ===
        let (central_balance, game_balance, total_balance) =
            InvestorToken::treasury_composition();
        assert!(
            total_balance == central_balance + game_balance,
            26
        );
        assert!(total_balance == final_treasury, 27);
    }

    #[test]
    fun test_block_stm_parallel_execution_simulation() {
        let (
            _,
            casino_signer,
            dice_signer,
            slot_signer,
            _,
            whale_investor,
            _,
            _,
            casual_player,
            high_roller,
            strategy_player,
            volume_player
        ) = setup_realistic_ecosystem();

        // Setup ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667
        );
        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1550
        );

        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Fund treasury adequately
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        // Get treasury addresses to verify isolation
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

        let dice_treasury_addr = CasinoHouse::get_game_treasury_address(dice_object);
        let slot_treasury_addr = CasinoHouse::get_game_treasury_address(slot_object);

        // Critical: Different treasury addresses enable Block-STM parallelization
        assert!(dice_treasury_addr != slot_treasury_addr, 1);

        // === SIMULATE HIGH-VOLUME CONCURRENT GAMING ===
        // In real Block-STM, these operations would execute in parallel
        // because they access different resource addresses
        let parallel_rounds = 20;
        let planned_bets = parallel_rounds * LARGE_BET;
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        assert!(
            primary_fungible_store::balance(CASUAL_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(HIGH_ROLLER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(STRATEGY_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(VOLUME_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        let i = 0;
        while (i < parallel_rounds) {
            // Pattern 1: Different games, different players (TRUE PARALLELIZATION)
            DiceGame::test_only_play_dice(
                &casual_player, (((i % 6) + 1) as u8), STANDARD_BET
            );
            SlotMachine::test_only_spin_slots(&high_roller, STANDARD_BET);
            // Pattern 2: Multiple dice players (sequential on same treasury, but isolated from slots)
            if (i % 2 == 0) {
                DiceGame::test_only_play_dice(
                    &strategy_player, (((i % 6) + 1) as u8), LARGE_BET
                );
            };
            // Pattern 3: Multiple slot players (sequential on same treasury, but isolated from dice)
            if (i % 3 == 0) {
                SlotMachine::test_only_spin_slots(&volume_player, LARGE_BET);
            };
            i = i + 1;
        };

        // === VERIFY SYSTEM STABILITY UNDER HIGH LOAD ===

        let dice_balance_after = CasinoHouse::game_treasury_balance(dice_object);
        let slot_balance_after = CasinoHouse::game_treasury_balance(slot_object);
        let total_balance_after = CasinoHouse::treasury_balance();

        // System should remain stable
        assert!(dice_balance_after >= 0, 2);
        assert!(slot_balance_after >= 0, 3);
        assert!(total_balance_after > 0, 4);

        // Games should remain operational
        assert!(DiceGame::is_ready(), 5);
        assert!(SlotMachine::is_ready(), 6);

        // Treasury should handle additional load
        assert!(DiceGame::can_handle_payout(LARGE_BET * 5), 7);
        assert!(SlotMachine::can_handle_payout(LARGE_BET * 100), 8);

        // === STRESS TEST: ADDITIONAL CONCURRENT LOAD ===
        let stress_rounds = 10;
        let j = 0;
        while (j < stress_rounds) {
            // Simulate maximum parallel load
            DiceGame::test_only_play_dice(
                &casual_player, (((j % 6) + 1) as u8), LARGE_BET
            );
            SlotMachine::test_only_spin_slots(&strategy_player, LARGE_BET);
            if (j % 2 == 0) {
                DiceGame::test_only_play_dice(
                    &volume_player, (((j % 6) + 1) as u8), STANDARD_BET
                );
                SlotMachine::test_only_spin_slots(&high_roller, STANDARD_BET);
            };
            j = j + 1;
        };

        // Final verification: system remains robust
        assert!(DiceGame::is_ready(), 9);
        assert!(SlotMachine::is_ready(), 10);
        assert!(CasinoHouse::treasury_balance() > 0, 11);
    }

    #[test]
    fun test_realistic_investor_nav_dynamics() {
        let (
            _,
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
        ) = setup_realistic_ecosystem();

        // Setup
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667
        );
        DiceGame::initialize_game(&dice_signer);

        // === PHASE 1: EARLY INVESTOR AT OPTIMAL NAV ===
        let initial_nav = InvestorToken::nav();
        assert!(initial_nav == 1_000_000, 1); // NAV scale = 1.0

        InvestorToken::deposit_and_mint(&early_investor, EARLY_INVESTOR_CAPITAL);
        let early_tokens = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        assert!(early_tokens == EARLY_INVESTOR_CAPITAL, 2); // 1:1 conversion at NAV 1.0

        // === PHASE 2: GAMING CREATES HOUSE EDGE ACCUMULATION ===
        // Sustained gaming activity creates house edge profits
        let house_edge_rounds = 20; // Lowered for sustainability
        let planned_bets = house_edge_rounds * LARGE_BET;
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        assert!(
            primary_fungible_store::balance(CASUAL_PLAYER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        assert!(
            primary_fungible_store::balance(HIGH_ROLLER_ADDR, aptos_metadata)
                >= planned_bets * 2,
            999
        );
        let i = 0;
        while (i < house_edge_rounds) {
            // Players naturally lose more than they win due to house edge
            DiceGame::test_only_play_dice(
                &casual_player, (((i % 6) + 1) as u8), STANDARD_BET
            );
            DiceGame::test_only_play_dice(&high_roller, (((i % 6) + 1) as u8), LARGE_BET);
            i = i + 1;
        };
        let nav_after_gaming = InvestorToken::nav();
        let treasury_after_gaming = CasinoHouse::treasury_balance();
        // House edge should accumulate over time (though randomness affects exact amounts)
        assert!(
            treasury_after_gaming >= EARLY_INVESTOR_CAPITAL / 2,
            3
        ); // Treasury should be substantial
        // === PHASE 3: WHALE ENTERS AT CURRENT NAV ===
        let nav_when_whale_enters = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);
        let whale_tokens = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
        // Whale's tokens/APT ratio depends on NAV when they entered
        let whale_token_per_apt = (whale_tokens * 1_000_000) / WHALE_INVESTOR_CAPITAL;
        let expected_ratio = (1_000_000 * 1_000_000) / nav_when_whale_enters;
        // Allow for small rounding differences in calculation
        assert!(whale_token_per_apt <= expected_ratio + 1000, 4);
        assert!(whale_token_per_apt >= expected_ratio - 1000, 5);
        // === PHASE 4: MORE GAMING AFFECTS NAV ===
        let additional_rounds = 10;
        let j = 0;
        while (j < additional_rounds) {
            DiceGame::test_only_play_dice(
                &casual_player, (((j % 6) + 1) as u8), STANDARD_BET
            );
            DiceGame::test_only_play_dice(&high_roller, (((j % 6) + 1) as u8), LARGE_BET);
            j = j + 1;
        };
        // === PHASE 5: INSTITUTIONAL ENTERS AT DIFFERENT NAV ===
        let nav_when_institutional_enters = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&institutional, INSTITUTIONAL_CAPITAL);
        let institutional_tokens =
            InvestorToken::user_balance(INSTITUTIONAL_INVESTOR_ADDR);
        // === PHASE 6: LATE INVESTOR DEMONSTRATES TIMING IMPACT ===
        let late_rounds = 10;
        let k = 0;
        while (k < late_rounds) {
            DiceGame::test_only_play_dice(&high_roller, (((k % 6) + 1) as u8), LARGE_BET);
            k = k + 1;
        };
        let nav_when_late_enters = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&late_investor, INSTITUTIONAL_CAPITAL);
        let late_tokens = InvestorToken::user_balance(LATE_INVESTOR_ADDR);
        // === PHASE 7: REDEMPTION BEHAVIOR AT DIFFERENT NAVs ===
        // Early investor redeems (potentially at profit)
        let early_apt_before =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        InvestorToken::redeem(&early_investor, early_tokens / 3); // Redeem 1/3
        let early_apt_after =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        let early_apt_received = early_apt_after - early_apt_before;
        // Whale investor redeems smaller percentage
        let whale_apt_before =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        InvestorToken::redeem(&whale_investor, whale_tokens / 10); // Redeem 10%
        let whale_apt_after =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );
        let whale_apt_received = whale_apt_after - whale_apt_before;
        // === VALIDATION: NAV BEHAVIOR IS CONSISTENT ===
        let final_nav = InvestorToken::nav();
        let final_treasury = CasinoHouse::treasury_balance();
        let final_supply = InvestorToken::total_supply();
        // All investors should have received APT on redemption
        assert!(early_apt_received > 0, 6);
        assert!(whale_apt_received > 0, 7);
        // System should be consistent
        assert!(final_nav > 0, 8);
        assert!(final_treasury > 0, 9);
        assert!(final_supply > 0, 10);
        // All remaining investors should have positions
        assert!(InvestorToken::user_balance(EARLY_INVESTOR_ADDR) > 0, 11); // 2/3 remaining
        assert!(InvestorToken::user_balance(WHALE_INVESTOR_ADDR) > 0, 12); // 90% remaining
        assert!(InvestorToken::user_balance(INSTITUTIONAL_INVESTOR_ADDR) > 0, 13); // 100% remaining
        assert!(InvestorToken::user_balance(LATE_INVESTOR_ADDR) > 0, 14); // 100% remaining
        // NAV calculation should be consistent with treasury and supply
        let calculated_nav =
            if (final_supply == 0) {
                1_000_000
            } else {
                (final_treasury * 1_000_000) / final_supply
            };
        // Allow for small rounding differences
        assert!(final_nav <= calculated_nav + 1000, 15);
        assert!(final_nav >= calculated_nav - 1000, 16);
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
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        // Register game with initial limits
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min (matches hardcoded)
            50000000, // 0.5 APT max (matches hardcoded)
            1667
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
        DiceGame::test_only_play_dice(&casual_player, 3, STANDARD_BET); // 0.05 APT - valid
        DiceGame::test_only_play_dice(&high_roller, 1, LARGE_BET); // 0.1 APT - valid

        // === PHASE 2: CASINO UPDATES LIMITS ===
        CasinoHouse::update_game_limits(&casino_signer, dice_object, 2000000, 45000000);

        let (_, _, _, new_min, new_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(new_min == 2000000, 3); // 0.02 APT
        assert!(new_max == 45000000, 4); // 0.45 APT

        // Test new limits
        DiceGame::test_only_play_dice(&high_roller, 4, 40000000); // 0.4 APT - within new limits

        // === PHASE 3: GAME REQUESTS CONSERVATIVE LIMITS ===
        // Games can only reduce risk (increase min or decrease max)
        DiceGame::request_limit_update(&dice_signer, 5000000, 40000000);

        let (_, _, _, conservative_min, conservative_max, _, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(conservative_min == 5000000, 5); // 0.05 APT (increased)
        assert!(conservative_max == 40000000, 6); // 0.4 APT (decreased)

        // === PHASE 4: VERIFY PAYOUT CAPACITY ===
        let max_payout = conservative_max * 5; // 5x for dice win
        assert!(DiceGame::can_handle_payout(conservative_max), 7);

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
        let (_, _, _, final_min, final_max, final_edge, _) =
            CasinoHouse::get_game_metadata(dice_object);
        assert!(final_min == 5000000, 11); // Conservative min maintained
        assert!(final_max == 40000000, 12); // Conservative max maintained
        assert!(final_edge == 1667, 13); // House edge unchanged
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
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
        InvestorToken::init(&casino_signer);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_INVESTOR_CAPITAL);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667
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
        InvestorToken::init(&casino_signer);

        InvestorToken::deposit_and_mint(&early_investor, EARLY_INVESTOR_CAPITAL);
        let tokens = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

        // Try to redeem more than balance
        InvestorToken::redeem(&early_investor, tokens + 1000000000); // More than owned
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_unauthorized_game_registration() {
        let (_, _, dice_signer, _, _, _, _, _, _, _, _, _) = setup_realistic_ecosystem();

        // Non-casino admin tries to register game - should fail
        CasinoHouse::register_game(
            &dice_signer, // Not casino admin
            DICE_ADDR,
            string::utf8(b"UnauthorizedGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
    }
}
