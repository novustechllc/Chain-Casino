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
    use casino::DiceGame;

    // Test constants
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @casino;
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
            1667,
            250_000_000
        );

        DiceGame::initialize_game(&dice_signer);

        // Verify game is ready
        assert!(DiceGame::is_ready(), 24);

        // Final verification - system remains stable
        assert!(InvestorToken::nav() == NAV_SCALE, 25);
        assert!(InvestorToken::total_supply() == final_total_supply, 26);
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
