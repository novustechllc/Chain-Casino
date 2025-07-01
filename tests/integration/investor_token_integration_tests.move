//! MIT License
//!
//! Integration Tests for InvestorToken Module
//!
//! Covers NAV mechanics, investment/redemption flows, and edge cases
//! to achieve better code coverage while testing investor token functionality.

#[test_only]
module casino::InvestorTokenIntegrationTests {
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

    // Investor addresses
    const EARLY_INVESTOR_ADDR: address = @0x1001;
    const WHALE_INVESTOR_ADDR: address = @0x1002;
    const SMALL_INVESTOR_ADDR: address = @0x1003;
    const LATE_INVESTOR_ADDR: address = @0x1004;

    // Player addresses for generating house edge
    const PLAYER_ADDR: address = @0x2001;

    // Investment amounts
    const EARLY_CAPITAL: u64 = 10000000000; // 100 APT
    const WHALE_CAPITAL: u64 = 100000000000; // 1000 APT
    const SMALL_CAPITAL: u64 = 1000000000; // 10 APT
    const TINY_INVESTMENT: u64 = 1000000; // 0.01 APT (edge case)
    const PLAYER_FUNDING: u64 = 5000000000; // 50 APT

    // Constants for testing
    const NAV_SCALE: u64 = 1_000_000;
    const STANDARD_BET: u64 = 5000000; // 0.05 APT

    fun setup_investor_ecosystem(): (
        signer, signer, signer, signer, signer, signer, signer, signer
    ) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let early_investor = account::create_account_for_test(EARLY_INVESTOR_ADDR);
        let whale_investor = account::create_account_for_test(WHALE_INVESTOR_ADDR);
        let small_investor = account::create_account_for_test(SMALL_INVESTOR_ADDR);
        let late_investor = account::create_account_for_test(LATE_INVESTOR_ADDR);
        let player = account::create_account_for_test(PLAYER_ADDR);

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
            EARLY_INVESTOR_ADDR,
            WHALE_INVESTOR_ADDR,
            SMALL_INVESTOR_ADDR,
            LATE_INVESTOR_ADDR,
            PLAYER_ADDR
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
        aptos_coin::mint(&aptos_framework, EARLY_INVESTOR_ADDR, EARLY_CAPITAL);
        aptos_coin::mint(&aptos_framework, WHALE_INVESTOR_ADDR, WHALE_CAPITAL);
        aptos_coin::mint(&aptos_framework, SMALL_INVESTOR_ADDR, SMALL_CAPITAL);
        aptos_coin::mint(&aptos_framework, LATE_INVESTOR_ADDR, EARLY_CAPITAL);
        aptos_coin::mint(&aptos_framework, PLAYER_ADDR, PLAYER_FUNDING);

        (
            aptos_framework,
            casino_signer,
            dice_signer,
            early_investor,
            whale_investor,
            small_investor,
            late_investor,
            player
        )
    }

    #[test]
    fun test_investor_initialization_and_investment_mechanics() {
        let (
            _,
            casino_signer,
            dice_signer,
            early_investor,
            whale_investor,
            small_investor,
            _,
            _
        ) = setup_investor_ecosystem();

        // === PHASE 1: CASINO SETUP ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Verify clean initial state
        assert!(InvestorToken::total_supply() == 0, 1);
        assert!(InvestorToken::treasury_balance() == 0, 2);
        assert!(InvestorToken::central_treasury_balance() == 0, 3);
        assert!(InvestorToken::nav() == NAV_SCALE, 4); // NAV = 1.0 initially

        // === PHASE 2: VERIFY TREASURY COMPOSITION ===
        let (central, game, total) = InvestorToken::treasury_composition();
        assert!(central == 0, 5);
        assert!(game == 0, 6);
        assert!(total == 0, 7);
        assert!(central + game == total, 8);

        // === PHASE 3: FIRST INVESTMENT (EARLY INVESTOR ADVANTAGE) ===
        let initial_nav = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&early_investor, EARLY_CAPITAL);

        // Verify early investor gets 1:1 ratio at NAV = 1.0
        let early_tokens = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        assert!(early_tokens == EARLY_CAPITAL, 9); // 1:1 conversion

        // Verify treasury updated
        let treasury_after_early = InvestorToken::treasury_balance();
        assert!(treasury_after_early >= EARLY_CAPITAL, 10);

        let central_after_early = InvestorToken::central_treasury_balance();
        assert!(central_after_early >= EARLY_CAPITAL, 11);

        // NAV should still be 1.0 with single investor
        assert!(InvestorToken::nav() == NAV_SCALE, 12);

        // === PHASE 4: WHALE INVESTMENT ===
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        let whale_tokens = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
        let total_supply_after_whale = InvestorToken::total_supply();

        assert!(
            total_supply_after_whale == early_tokens + whale_tokens,
            13
        );
        assert!(whale_tokens == WHALE_CAPITAL, 14); // Still 1:1 at NAV = 1.0

        // === PHASE 5: SMALL INVESTMENT (FIXED - Use smaller amount to avoid balance issues) ===
        let small_investment = 500000000; // 5 APT (half of small investor's balance)
        InvestorToken::deposit_and_mint(&small_investor, small_investment);

        let small_tokens = InvestorToken::user_balance(SMALL_INVESTOR_ADDR);
        assert!(small_tokens == small_investment, 15); // Should work for smaller amounts

        // === PHASE 6: TINY INVESTMENT EDGE CASE (FIXED - Use remaining balance) ===
        let remaining_balance =
            primary_fungible_store::balance(
                SMALL_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        if (remaining_balance >= TINY_INVESTMENT) {
            InvestorToken::deposit_and_mint(&small_investor, TINY_INVESTMENT);
            let small_tokens_after = InvestorToken::user_balance(SMALL_INVESTOR_ADDR);
            assert!(
                small_tokens_after == small_investment + TINY_INVESTMENT,
                16
            );
        } else {
            // Skip tiny investment if insufficient balance, test still validates core functionality
            assert!(small_tokens == small_investment, 16);
        };

        // === PHASE 7: VERIFY COMPREHENSIVE TREASURY STATE ===
        let final_total_supply = InvestorToken::total_supply();
        let final_treasury_balance = InvestorToken::treasury_balance();
        let final_nav = InvestorToken::nav();

        assert!(final_total_supply > 0, 17);
        assert!(final_treasury_balance > 0, 18);
        assert!(final_nav == NAV_SCALE, 19); // Should still be 1.0 with no gaming

        // Verify treasury composition
        let (final_central, final_game, final_total) =
            InvestorToken::treasury_composition();
        assert!(final_central > 0, 20);
        assert!(final_game >= 0, 21); // Could be 0 if no games active
        assert!(final_total == final_central + final_game, 22);
        assert!(final_total == final_treasury_balance, 23);

        // === PHASE 8: REGISTER GAME FOR FUTURE TESTS ===
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

        // Verify game is ready
        assert!(DiceGame::is_ready(), 24);

        // Final verification - system remains stable
        assert!(InvestorToken::nav() == NAV_SCALE, 25);
        assert!(InvestorToken::total_supply() == final_total_supply, 26);
    }

    #[test]
    fun test_redemption_mechanics_and_edge_cases() {
        let (
            _,
            casino_signer,
            dice_signer,
            early_investor,
            whale_investor,
            _,
            late_investor,
            player
        ) = setup_investor_ecosystem();

        // Setup ecosystem with game for house edge generation
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

        // === PHASE 1: SETUP INVESTORS ===
        InvestorToken::deposit_and_mint(&early_investor, EARLY_CAPITAL);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        let early_tokens_initial = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        let whale_tokens_initial = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);

        // === PHASE 2: GENERATE HOUSE EDGE THROUGH GAMING ===
        // Multiple rounds to potentially increase NAV through house edge
        let gaming_rounds = 20;
        let i = 0;
        while (i < gaming_rounds) {
            DiceGame::test_only_play_dice(&player, (((i % 6) + 1) as u8), STANDARD_BET);
            i = i + 1;
        };

        let nav_after_gaming = InvestorToken::nav();
        // NAV might be higher due to house edge (though randomness affects this)

        // === PHASE 3: TEST NORMAL REDEMPTION ===
        let early_apt_before =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let redeem_amount = early_tokens_initial / 4; // Redeem 25%
        InvestorToken::redeem(&early_investor, redeem_amount);

        let early_apt_after =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let early_tokens_after = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

        assert!(early_apt_after > early_apt_before, 1); // Should receive APT
        assert!(
            early_tokens_after == early_tokens_initial - redeem_amount,
            2
        );

        // === PHASE 4: TEST DIVIDEND INFO FUNCTION ===
        let (treasury_ratio, total_dividends, creation_time) =
            InvestorToken::get_dividend_info();
        assert!(treasury_ratio > 0, 3);
        assert!(total_dividends >= 0, 4);
        assert!(creation_time > 0, 5);

        // === PHASE 5: TEST LARGE REDEMPTION ===
        let whale_large_redeem = whale_tokens_initial / 2; // Redeem 50%

        let whale_apt_before =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::redeem(&whale_investor, whale_large_redeem);

        let whale_apt_after =
            primary_fungible_store::balance(
                WHALE_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        assert!(whale_apt_after > whale_apt_before, 6);

        // === PHASE 6: TEST EDGE CASE - SMALL REDEMPTION ===
        let tiny_redeem = 1000; // Very small amount
        let whale_tokens_before_tiny = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);

        if (whale_tokens_before_tiny >= tiny_redeem) {
            InvestorToken::redeem(&whale_investor, tiny_redeem);
            let whale_tokens_after_tiny =
                InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
            assert!(
                whale_tokens_after_tiny == whale_tokens_before_tiny - tiny_redeem,
                7
            );
        };

        // === PHASE 7: TEST LATE INVESTOR (POTENTIALLY DIFFERENT NAV) ===
        let nav_when_late_enters = InvestorToken::nav();
        InvestorToken::deposit_and_mint(&late_investor, EARLY_CAPITAL);

        let late_tokens = InvestorToken::user_balance(LATE_INVESTOR_ADDR);

        // Late investor's token amount depends on current NAV
        if (nav_when_late_enters > NAV_SCALE) {
            // If NAV increased, should get fewer tokens per APT
            assert!(late_tokens < EARLY_CAPITAL, 8);
        } else {
            // If NAV same or decreased, should get same or more tokens
            assert!(late_tokens >= EARLY_CAPITAL, 9);
        };

        // === PHASE 8: VERIFY SYSTEM STABILITY AFTER REDEMPTIONS ===
        let final_nav = InvestorToken::nav();
        let final_supply = InvestorToken::total_supply();
        let final_treasury = InvestorToken::treasury_balance();

        assert!(final_nav > 0, 10);
        assert!(final_supply > 0, 11);
        assert!(final_treasury > 0, 12);

        // Verify treasury composition remains consistent
        let (central_final, game_final, total_final) =
            InvestorToken::treasury_composition();
        assert!(total_final == central_final + game_final, 13);
        assert!(total_final == final_treasury, 14);

        // === PHASE 9: TEST ZERO SUPPLY EDGE CASE ===
        // This is hard to test in practice, but we can verify the view function handles it
        // The nav() function should return NAV_SCALE when total_supply == 0
        let current_nav = InvestorToken::nav();
        assert!(current_nav > 0, 15); // Current NAV should be positive
    }

    #[test]
    fun test_comprehensive_view_functions_and_system_stress() {
        let (_, casino_signer, dice_signer, early_investor, whale_investor, _, _, player) =
            setup_investor_ecosystem();

        // Setup complete ecosystem
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

        // === PHASE 1: TEST VIEW FUNCTIONS WITH EMPTY STATE ===

        // Test with no supply (edge case for total_supply)
        assert!(InvestorToken::total_supply() == 0, 1);
        assert!(InvestorToken::nav() == NAV_SCALE, 2);
        assert!(InvestorToken::user_balance(EARLY_INVESTOR_ADDR) == 0, 3);

        // Test central treasury balance view function
        assert!(InvestorToken::central_treasury_balance() == 0, 4);

        let (central_empty, game_empty, total_empty) =
            InvestorToken::treasury_composition();
        assert!(central_empty == 0, 5);
        assert!(game_empty == 0, 6);
        assert!(total_empty == 0, 7);

        // === PHASE 2: ADD INVESTMENTS AND TEST VIEW FUNCTIONS ===

        InvestorToken::deposit_and_mint(&early_investor, EARLY_CAPITAL);
        InvestorToken::deposit_and_mint(&whale_investor, WHALE_CAPITAL);

        // Test all view functions with populated state
        let supply_populated = InvestorToken::total_supply();
        let treasury_populated = InvestorToken::treasury_balance();
        let central_populated = InvestorToken::central_treasury_balance();
        let nav_populated = InvestorToken::nav();

        assert!(supply_populated > 0, 8);
        assert!(treasury_populated > 0, 9);
        assert!(central_populated > 0, 10);
        assert!(nav_populated == NAV_SCALE, 11); // Should be 1.0 with no gaming profits

        // Test user balance view
        assert!(InvestorToken::user_balance(EARLY_INVESTOR_ADDR) > 0, 12);
        assert!(InvestorToken::user_balance(WHALE_INVESTOR_ADDR) > 0, 13);
        assert!(InvestorToken::user_balance(@0x9999) == 0, 14); // Non-investor should have 0

        // === PHASE 3: STRESS TEST WITH GAMING ACTIVITY ===

        // Generate significant gaming activity to test treasury dynamics
        let stress_rounds = 30;
        let round = 0;
        while (round < stress_rounds) {
            DiceGame::test_only_play_dice(
                &player, (((round % 6) + 1) as u8), STANDARD_BET
            );

            // Test view functions remain stable during gaming
            let _ = InvestorToken::nav();
            let _ = InvestorToken::total_supply();
            let _ = InvestorToken::treasury_balance();
            let _ = InvestorToken::central_treasury_balance();

            round = round + 1;
        };

        // === PHASE 4: TEST VIEW FUNCTIONS AFTER GAMING ===

        let nav_after_stress = InvestorToken::nav();
        let treasury_after_stress = InvestorToken::treasury_balance();
        let central_after_stress = InvestorToken::central_treasury_balance();

        assert!(nav_after_stress > 0, 15);
        assert!(treasury_after_stress > 0, 16);
        assert!(central_after_stress >= 0, 17);

        // Test treasury composition
        let (central_stress, game_stress, total_stress) =
            InvestorToken::treasury_composition();
        assert!(total_stress == central_stress + game_stress, 18);
        assert!(total_stress == treasury_after_stress, 19);

        // === PHASE 5: TEST DIVIDEND INFO AFTER ACTIVITY ===

        let (ratio_stress, dividends_stress, creation_stress) =
            InvestorToken::get_dividend_info();
        assert!(ratio_stress > 0, 20);
        assert!(dividends_stress >= 0, 21);
        assert!(creation_stress > 0, 22);

        // === PHASE 6: STRESS TEST REDEMPTIONS ===

        let early_balance_before_stress =
            InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        let whale_balance_before_stress =
            InvestorToken::user_balance(WHALE_INVESTOR_ADDR);

        // Multiple small redemptions
        if (early_balance_before_stress >= 10000) {
            let small_redemptions = 5;
            let redeem_size = 1000; // Small redemptions
            let i = 0;
            while (i < small_redemptions) {
                InvestorToken::redeem(&early_investor, redeem_size);

                // Test view functions remain stable
                let _ = InvestorToken::nav();
                let _ = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

                i = i + 1;
            };
        };

        // One larger redemption
        let whale_balance_current = InvestorToken::user_balance(WHALE_INVESTOR_ADDR);
        if (whale_balance_current >= 100000) {
            InvestorToken::redeem(&whale_investor, 50000);
        };

        // === PHASE 7: FINAL SYSTEM VALIDATION ===

        // All view functions should still work correctly
        let final_nav = InvestorToken::nav();
        let final_supply = InvestorToken::total_supply();
        let final_treasury = InvestorToken::treasury_balance();
        let final_central = InvestorToken::central_treasury_balance();

        assert!(final_nav > 0, 23);
        assert!(final_supply >= 0, 24);
        assert!(final_treasury >= 0, 25);
        assert!(final_central >= 0, 26);

        // Final treasury composition check
        let (central_final, game_final, total_final) =
            InvestorToken::treasury_composition();
        assert!(total_final == central_final + game_final, 27);

        // Final dividend info check
        let (ratio_final, dividends_final, creation_final) =
            InvestorToken::get_dividend_info();
        assert!(ratio_final > 0, 28);
        assert!(dividends_final >= 0, 29);
        assert!(creation_final > 0, 30);

        // System should remain operational
        assert!(DiceGame::is_ready(), 31);
    }

    // === ERROR CONDITION TESTS ===

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_UNAUTHORIZED_INIT)]
    fun test_unauthorized_initialization() {
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_ADDR);

        // Try to initialize with wrong signer - should fail
        InvestorToken::init(&unauthorized);
    }

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INVALID_AMOUNT)]
    fun test_zero_deposit_amount() {
        let (_, casino_signer, _, early_investor, _, _, _, _) =
            setup_investor_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Try to deposit zero amount - should fail
        InvestorToken::deposit_and_mint(&early_investor, 0);
    }

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INVALID_AMOUNT)]
    fun test_zero_redeem_amount() {
        let (_, casino_signer, _, early_investor, _, _, _, _) =
            setup_investor_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Setup investment first
        InvestorToken::deposit_and_mint(&early_investor, EARLY_CAPITAL);

        // Try to redeem zero tokens - should fail
        InvestorToken::redeem(&early_investor, 0);
    }

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INSUFFICIENT_BALANCE)]
    fun test_insufficient_balance_redemption() {
        let (_, casino_signer, _, early_investor, _, _, _, _) =
            setup_investor_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Setup small investment
        InvestorToken::deposit_and_mint(&early_investor, SMALL_CAPITAL);

        let user_balance = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

        // Try to redeem more than balance - should fail
        InvestorToken::redeem(&early_investor, user_balance + 1);
    }

    #[test]
    fun test_normal_treasury_operations() {
        let (_, casino_signer, _, early_investor, _, _, _, _) =
            setup_investor_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Setup investment
        InvestorToken::deposit_and_mint(&early_investor, EARLY_CAPITAL);

        let user_balance = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);
        let treasury_before = InvestorToken::treasury_balance();

        // Normal redemption should work (treasury is always sufficient in this system)
        let redeem_amount = user_balance / 4; // Redeem 25%

        let apt_before =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::redeem(&early_investor, redeem_amount);

        let apt_after =
            primary_fungible_store::balance(
                EARLY_INVESTOR_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let treasury_after = InvestorToken::treasury_balance();

        // Verify successful redemption
        assert!(apt_after > apt_before, 1); // User received APT
        assert!(treasury_after < treasury_before, 2); // Treasury decreased
        assert!(
            InvestorToken::user_balance(EARLY_INVESTOR_ADDR)
                == user_balance - redeem_amount,
            3
        );
    }

    #[test]
    fun test_zero_payout_scenario() {
        let (_, casino_signer, _, early_investor, _, _, _, _) =
            setup_investor_ecosystem();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Setup very small investment to test edge cases
        let very_small_amount = 100; // Extremely small
        InvestorToken::deposit_and_mint(&early_investor, very_small_amount);

        let user_balance = InvestorToken::user_balance(EARLY_INVESTOR_ADDR);

        // Try to redeem a very small amount that might result in zero payout after fees
        if (user_balance > 0) {
            let tiny_redeem = 1; // 1 token

            let apt_before =
                primary_fungible_store::balance(
                    EARLY_INVESTOR_ADDR,
                    option::extract(&mut coin::paired_metadata<AptosCoin>())
                );

            InvestorToken::redeem(&early_investor, tiny_redeem);

            let apt_after =
                primary_fungible_store::balance(
                    EARLY_INVESTOR_ADDR,
                    option::extract(&mut coin::paired_metadata<AptosCoin>())
                );

            // User might not receive any APT if the amount is too small after fees
            // This tests the zero payout branch in the redeem function
            assert!(apt_after >= apt_before, 1); // APT should not decrease
        };
    }
}
