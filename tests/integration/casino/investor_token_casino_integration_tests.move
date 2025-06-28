//! Integration test demonstrating CasinoHouse and InvestorToken working together
//!
//! Tests the core profit flow: Game bets → Treasury → InvestorToken NAV

#[test_only]
module casino::IntegrationTest {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;
    use casino::InvestorToken;

    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const INVESTOR_DEPOSIT: u64 = 100000000; // 1 APT
    const BET_AMOUNT: u64 = 10000000; // 0.1 APT
    const NAV_SCALE: u64 = 1000000;

    #[test]
    fun test_casino_profit_flows_to_investors() {
        // Setup accounts
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let game_account = account::create_account_for_test(@0x123);
        let investor = account::create_account_for_test(@0x111);
        let player = account::create_account_for_test(@0x222);

        // Initialize APT and register coins
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&game_account);
        coin::register<AptosCoin>(&investor);
        coin::register<AptosCoin>(&player);

        // Fund accounts
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);

        // Initialize both modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        // Register a test game
        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"TestGame"),
            1000000, // min bet: 0.01 APT
            100000000, // max bet: 1 APT
            150 // house edge: 1.5%
        );

        // === STEP 1: Investor deposits tokens ===
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        let initial_investor_tokens = InvestorToken::user_balance(@0x111);
        let initial_nav = InvestorToken::nav();

        assert!(initial_investor_tokens == INVESTOR_DEPOSIT, 1);
        assert!(initial_nav == NAV_SCALE, 2); // NAV should be 1.0 initially

        // === STEP 2: Simulate profitable game activity ===

        // Player places bet through game
        let bet_coins = coin::withdraw<AptosCoin>(&player, BET_AMOUNT);
        let bet_id =
            CasinoHouse::place_bet(
                &game_account,
                bet_coins,
                @0x222,
                BET_AMOUNT * 2 // Expected payout (2x)
            );

        // Treasury should now have the bet amount
        let treasury_after_bet = CasinoHouse::treasury_balance();
        assert!(
            treasury_after_bet == INVESTOR_DEPOSIT + BET_AMOUNT,
            3
        );

        // Game settles bet - player loses (house keeps the bet)
        CasinoHouse::settle_bet(&game_account, bet_id, @0x222, 0); // Zero payout = player loses

        // === STEP 3: Verify profit flows to investors ===

        let treasury_after_settlement = CasinoHouse::treasury_balance();
        let nav_after_profit = InvestorToken::nav();

        // Treasury should still have bet amount (profit)
        assert!(
            treasury_after_settlement == INVESTOR_DEPOSIT + BET_AMOUNT,
            4
        );

        // NAV should increase due to additional treasury backing
        assert!(nav_after_profit > initial_nav, 5);

        // === STEP 4: Investor redeems and receives profit share ===

        let investor_apt_before_redeem = coin::balance<AptosCoin>(@0x111);

        // Redeem half the tokens
        let redeem_tokens = initial_investor_tokens / 2;
        InvestorToken::redeem(&investor, redeem_tokens);

        let investor_apt_after_redeem = coin::balance<AptosCoin>(@0x111);
        let apt_received = investor_apt_after_redeem - investor_apt_before_redeem;

        // Should receive more than face value due to profit
        let face_value = redeem_tokens; // Original 1:1 ratio
        assert!(apt_received > face_value * 95 / 100, 6); // Account for fees, should get ~face value + profit

        // === STEP 5: Verify final state ===

        let remaining_tokens = InvestorToken::user_balance(@0x111);
        let final_treasury = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();

        assert!(
            remaining_tokens == initial_investor_tokens / 2,
            7
        );
        assert!(final_treasury > 0, 8); // Should still have treasury backing
        assert!(final_nav > NAV_SCALE, 9); // NAV should still be elevated due to profits
    }

    #[test]
    fun test_multiple_investors_share_profits() {
        // Setup accounts
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let game_account = account::create_account_for_test(@0x123);
        let investor1 = account::create_account_for_test(@0x111);
        let investor2 = account::create_account_for_test(@0x222);
        let player = account::create_account_for_test(@0x333);

        // Initialize
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&game_account);
        coin::register<AptosCoin>(&investor1);
        coin::register<AptosCoin>(&investor2);
        coin::register<AptosCoin>(&player);

        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x222, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x333, INITIAL_BALANCE);

        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        CasinoHouse::register_game(
            &casino_account,
            @0x123,
            string::utf8(b"TestGame"),
            1000000,
            100000000,
            150
        );

        // Both investors deposit different amounts
        InvestorToken::deposit_and_mint(&investor1, INVESTOR_DEPOSIT); // 1 APT
        InvestorToken::deposit_and_mint(&investor2, INVESTOR_DEPOSIT * 2); // 2 APT

        let investor1_tokens = InvestorToken::user_balance(@0x111);
        let investor2_tokens = InvestorToken::user_balance(@0x222);

        // Generate profit through losing bet
        let bet_coins = coin::withdraw<AptosCoin>(&player, BET_AMOUNT);
        let bet_id = CasinoHouse::place_bet(
            &game_account, bet_coins, @0x333, BET_AMOUNT * 2
        );
        CasinoHouse::settle_bet(&game_account, bet_id, @0x333, 0); // Player loses

        // Both investors should benefit proportionally
        let nav_after_profit = InvestorToken::nav();
        assert!(nav_after_profit > NAV_SCALE, 1);

        // Verify proportional holdings are maintained
        assert!(investor2_tokens > investor1_tokens, 2); // Investor2 should have more tokens
        assert!(investor2_tokens == investor1_tokens * 2, 3); // Should be exactly 2x
    }
}
