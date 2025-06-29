//! Integration tests for InvestorToken and CasinoHouse modules

#[test_only]
module casino::InvestorTokenCasinoIntegrationTest {
    use std::string;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const INVESTOR_DEPOSIT: u64 = 100000000; // 1 APT
    const GAME_PROFIT: u64 = 50000000; // 0.5 APT
    const NAV_SCALE: u64 = 1000000;

    // Test capability wrapper
    struct TestGameAuth has key {
        capability: GameCapability
    }

    fun setup_integration_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let investor = account::create_account_for_test(@0x123);

        // Setup Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        // Register coin accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&investor);

        // Mint initial balances
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);

        // Initialize both modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        (aptos_framework, casino_account, investor)
    }

    #[test]
    fun test_full_integration_flow() {
        let (_, casino_account, investor) = setup_integration_test();

        // 1. Verify initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(InvestorToken::treasury_balance() == 0, 2);
        assert!(InvestorToken::total_supply() == 0, 3);
        assert!(InvestorToken::nav() == NAV_SCALE, 4); // NAV = 1.0

        // 2. Investor deposits APT and mints tokens
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        // Verify treasury integration
        assert!(CasinoHouse::treasury_balance() == INVESTOR_DEPOSIT, 5);
        assert!(InvestorToken::treasury_balance() == INVESTOR_DEPOSIT, 6);
        assert!(InvestorToken::total_supply() == INVESTOR_DEPOSIT, 7);
        assert!(InvestorToken::user_balance(@0x123) == INVESTOR_DEPOSIT, 8);

        // 3. Register a test game and simulate profit
        CasinoHouse::register_game(
            &casino_account,
            @0xD1CE,
            string::utf8(b"Test Game"),
            1000000, // min bet
            100000000, // max bet
            150 // house edge
        );
        let game_account = account::create_account_for_test(@0xD1CE);
        let capability = CasinoHouse::get_game_capability(&game_account);
        move_to(&game_account, TestGameAuth { capability });

        // Simulate game profit by direct treasury injection
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, GAME_PROFIT);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // 4. Verify NAV increased due to profit
        let new_treasury = CasinoHouse::treasury_balance();
        let expected_treasury = INVESTOR_DEPOSIT + GAME_PROFIT;
        assert!(new_treasury == expected_treasury, 9);

        let new_nav = InvestorToken::nav();
        let expected_nav = (expected_treasury * NAV_SCALE) / INVESTOR_DEPOSIT;
        assert!(new_nav == expected_nav, 10);
        assert!(new_nav > NAV_SCALE, 11); // NAV should be > 1.0

        // 5. Investor redeems half their tokens at profit
        let redeem_tokens = INVESTOR_DEPOSIT / 2;
        let investor_apt_before = coin::balance<AptosCoin>(@0x123);

        InvestorToken::redeem(&investor, redeem_tokens);

        let investor_apt_after = coin::balance<AptosCoin>(@0x123);
        let received_apt = investor_apt_after - investor_apt_before;

        // Should receive more than face value due to increased NAV
        let expected_gross = (redeem_tokens * new_nav) / NAV_SCALE;
        assert!(received_apt > 0, 12);
        assert!(received_apt < expected_gross, 13); // Less due to fees

        // 6. Verify final state consistency
        let final_token_supply = InvestorToken::total_supply();
        let final_treasury = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();

        assert!(
            final_token_supply == INVESTOR_DEPOSIT - redeem_tokens,
            14
        );
        assert!(final_treasury > 0, 15);
        assert!(final_nav > 0, 16);

        // User should still have remaining tokens
        let remaining_tokens = InvestorToken::user_balance(@0x123);
        assert!(remaining_tokens == final_token_supply, 17);
    }

    #[test]
    fun test_multi_investor_profit_distribution() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let investor1 = account::create_account_for_test(@0x111);
        let investor2 = account::create_account_for_test(@0x222);

        // Setup
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&investor1);
        coin::register<AptosCoin>(&investor2);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        // Both investors deposit
        let deposit1 = 60000000; // 0.6 APT
        let deposit2 = 40000000; // 0.4 APT

        InvestorToken::deposit_and_mint(&investor1, deposit1);
        InvestorToken::deposit_and_mint(&investor2, deposit2);

        let total_deposits = deposit1 + deposit2;
        assert!(CasinoHouse::treasury_balance() == total_deposits, 1);

        // Inject profit
        let profit = 20000000; // 0.2 APT
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, profit);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // Both should benefit proportionally from increased NAV
        let nav_with_profit = InvestorToken::nav();
        assert!(nav_with_profit > NAV_SCALE, 2);

        let balance1 = InvestorToken::user_balance(@0x111);
        let balance2 = InvestorToken::user_balance(@0x222);

        // Proportional ownership should be maintained
        assert!(balance1 > balance2, 3); // investor1 deposited more
        assert!(
            balance1 + balance2 == InvestorToken::total_supply(),
            4
        );
    }

    #[test]
    fun test_treasury_synchronization() {
        let (_, casino_account, investor) = setup_integration_test();

        // Both modules should report same treasury balance
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 1);

        // After deposit
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 2);

        // After direct treasury operation
        let extra_coins = coin::withdraw<AptosCoin>(&casino_account, 1000000);
        CasinoHouse::deposit_to_treasury(extra_coins);
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 3);

        // After redemption
        let redeem_amount = INVESTOR_DEPOSIT / 3;
        InvestorToken::redeem(&investor, redeem_amount);
        assert!(CasinoHouse::treasury_balance() == InvestorToken::treasury_balance(), 4);
    }

    #[test]
    fun test_nav_precision_with_profits() {
        let (_, casino_account, investor) = setup_integration_test();

        // Deposit initial amount
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        // Add small profit increment
        let small_profit = 1000; // 0.000001 APT
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, small_profit);
        CasinoHouse::deposit_to_treasury(profit_coins);

        let nav_after_profit = InvestorToken::nav();
        let expected_nav = ((INVESTOR_DEPOSIT + small_profit) * NAV_SCALE)
            / INVESTOR_DEPOSIT;

        assert!(nav_after_profit == expected_nav, 1);
        assert!(nav_after_profit > NAV_SCALE, 2);
    }

    #[test]
    fun test_zero_treasury_edge_case() {
        let (_, _, investor) = setup_integration_test();

        // NAV should be 1.0 when treasury and supply are both zero
        assert!(InvestorToken::nav() == NAV_SCALE, 1);
        assert!(InvestorToken::treasury_balance() == 0, 2);
        assert!(InvestorToken::total_supply() == 0, 3);

        // After first deposit, NAV should remain close to 1.0
        InvestorToken::deposit_and_mint(&investor, 1000);
        let nav_after_first = InvestorToken::nav();
        assert!(nav_after_first >= NAV_SCALE, 4);
    }
}
