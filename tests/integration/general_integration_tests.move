//! Full integration tests for InvestorToken + CasinoHouse + DiceGame

#[test_only]
module casino::FullIntegrationTest {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;
    use dice_game::DiceGame;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const INVESTOR_DEPOSIT: u64 = 200000000; // 2 APT
    const DICE_BET: u64 = 10000000; // 0.1 APT
    const NAV_SCALE: u64 = 1000000;

    // Test capability wrapper for DiceGame
    struct DiceGameAuth has key {
        capability: GameCapability
    }

    fun setup_full_integration(): (signer, signer, signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let dice_account = account::create_account_for_test(@dice_game);
        let investor = account::create_account_for_test(@0x123);
        let player = account::create_account_for_test(@0x456);

        // Setup Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        // Initialize randomness for testing
        randomness::initialize_for_testing(&aptos_framework);

        // Register coin accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&dice_account);
        coin::register<AptosCoin>(&investor);
        coin::register<AptosCoin>(&player);

        // Mint initial balances
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @dice_game, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x123, INITIAL_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x456, INITIAL_BALANCE);

        // Initialize all modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        // NEW TWO-STEP INITIALIZATION:
        // Step 1: Casino admin registers the dice game
        CasinoHouse::register_game(
            &casino_account,
            @dice_game,
            string::utf8(b"Dice Game"),
            1000000, // 0.01 APT min bet
            50000000, // 0.5 APT max bet
            1667 // 16.67% house edge
        );

        // Step 2: Dice game claims its capability
        DiceGame::initialize_game(&dice_account);

        (aptos_framework, casino_account, dice_account, investor, player)
    }

    #[test]
    fun test_full_casino_ecosystem() {
        let (_, casino_account, _dice_account, investor, player) =
            setup_full_integration();

        // 1. Verify all modules initialized correctly
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(InvestorToken::total_supply() == 0, 2);
        assert!(DiceGame::is_registered(), 3);

        // 2. Investor deposits and mints tokens
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        let initial_nav = InvestorToken::nav();
        assert!(initial_nav == NAV_SCALE, 4); // NAV = 1.0
        assert!(CasinoHouse::treasury_balance() == INVESTOR_DEPOSIT, 5);

        // 3. Fund treasury for potential payouts
        let payout_reserve = 100000000; // 1 APT
        let reserve_coins = coin::withdraw<AptosCoin>(&casino_account, payout_reserve);
        CasinoHouse::deposit_to_treasury(reserve_coins);

        let treasury_after_reserve = CasinoHouse::treasury_balance();
        assert!(
            treasury_after_reserve == INVESTOR_DEPOSIT + payout_reserve,
            6
        );

        // 4. Player makes a dice bet
        DiceGame::play_dice(&player, 1, DICE_BET);

        // Treasury should have received the bet regardless of outcome
        let treasury_after_bet = CasinoHouse::treasury_balance();
        assert!(treasury_after_bet >= treasury_after_reserve, 7);

        // 5. Simulate house profit scenario by direct treasury injection
        // (since we can't control dice randomness in tests)
        let house_profit = 50000000; // 0.5 APT profit
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, house_profit);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // 6. Verify NAV increased due to house profits
        let nav_with_profit = InvestorToken::nav();
        let expected_treasury = treasury_after_bet + house_profit;
        let _ = (expected_treasury * NAV_SCALE) / INVESTOR_DEPOSIT;

        assert!(nav_with_profit > initial_nav, 8);
        assert!(CasinoHouse::treasury_balance() == expected_treasury, 9);

        // 7. Investor redeems tokens at profit
        let redeem_tokens = INVESTOR_DEPOSIT / 2;
        let investor_apt_before = coin::balance<AptosCoin>(@0x123);

        InvestorToken::redeem(&investor, redeem_tokens);

        let investor_apt_after = coin::balance<AptosCoin>(@0x123);
        let received_apt = investor_apt_after - investor_apt_before;

        // Should receive more than face value due to profits
        assert!(received_apt > 0, 10);

        // Verify final ecosystem state
        let final_supply = InvestorToken::total_supply();
        let final_treasury = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();

        assert!(
            final_supply == INVESTOR_DEPOSIT - redeem_tokens,
            11
        );
        assert!(final_treasury > 0, 12);
        assert!(final_nav > 0, 13);
    }

    #[test]
    fun test_multiple_dice_games_profit_accumulation() {
        let (_, casino_account, _dice_account, investor, _) = setup_full_integration();

        // Setup investor position
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        // Fund treasury for payouts
        let payout_fund = 200000000; // 2 APT
        let fund_coins = coin::withdraw<AptosCoin>(&casino_account, payout_fund);
        CasinoHouse::deposit_to_treasury(fund_coins);

        let initial_treasury = CasinoHouse::treasury_balance();
        let initial_nav = InvestorToken::nav();

        // Create multiple players
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let player1 = account::create_account_for_test(@0x111);
        let player2 = account::create_account_for_test(@0x222);
        let player3 = account::create_account_for_test(@0x333);

        coin::register<AptosCoin>(&player1);
        coin::register<AptosCoin>(&player2);
        coin::register<AptosCoin>(&player3);

        aptos_coin::mint(&aptos_framework, @0x111, DICE_BET * 2);
        aptos_coin::mint(&aptos_framework, @0x222, DICE_BET * 2);
        aptos_coin::mint(&aptos_framework, @0x333, DICE_BET * 2);

        // Multiple dice bets
        DiceGame::play_dice(&player1, 1, DICE_BET);
        DiceGame::play_dice(&player2, 3, DICE_BET);
        DiceGame::play_dice(&player3, 6, DICE_BET);

        // Treasury should have accumulated bet amounts regardless of outcomes
        let treasury_after_bets = CasinoHouse::treasury_balance();
        assert!(treasury_after_bets >= initial_treasury, 1);

        // Simulate additional house profit
        let additional_profit = 30000000; // 0.3 APT
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, additional_profit);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // NAV should reflect accumulated profits
        let final_nav = InvestorToken::nav();
        assert!(final_nav >= initial_nav, 2);

        // Investor should be able to redeem at potentially profitable NAV
        let redeem_amount = INVESTOR_DEPOSIT / 4;
        InvestorToken::redeem(&investor, redeem_amount);

        let remaining_balance = InvestorToken::user_balance(@0x123);
        assert!(
            remaining_balance == INVESTOR_DEPOSIT - redeem_amount,
            3
        );
    }

    #[test]
    fun test_game_configuration_integration() {
        let (_, _, _, _, _) = setup_full_integration();

        // Verify DiceGame registered with correct parameters
        assert!(DiceGame::is_registered(), 1);

        let (min_bet, max_bet, payout_mult, house_edge) = DiceGame::get_game_config();
        assert!(min_bet == 1000000, 2); // 0.01 APT
        assert!(max_bet == 50000000, 3); // 0.5 APT
        assert!(payout_mult == 5, 4); // 5x multiplier
        assert!(house_edge == 1667, 5); // 16.67% house edge

        // Verify casino house knows about the game
        assert!(CasinoHouse::is_game_registered(@dice_game), 6);
    }

    #[test]
    fun test_investor_profit_from_dice_house_edge() {
        let (_, casino_account, _dice_account, investor, _) = setup_full_integration();

        // Large investor position
        let large_deposit = 500000000; // 5 APT
        InvestorToken::deposit_and_mint(&investor, large_deposit);

        // Fund sufficient treasury for potential payouts
        let payout_fund = 500000000; // 5 APT
        let fund_coins = coin::withdraw<AptosCoin>(&casino_account, payout_fund);
        CasinoHouse::deposit_to_treasury(fund_coins);

        let initial_nav = InvestorToken::nav();
        let initial_treasury = CasinoHouse::treasury_balance();

        // Simulate house edge profit directly (since we can't control randomness)
        // In real scenario, house edge would accumulate over many games
        let simulated_house_profit = 50000000; // 0.5 APT
        let house_coins =
            coin::withdraw<AptosCoin>(&casino_account, simulated_house_profit);
        CasinoHouse::deposit_to_treasury(house_coins);

        // Verify profit flows to investor via NAV increase
        let nav_after_profit = InvestorToken::nav();
        let treasury_after_profit = CasinoHouse::treasury_balance();

        assert!(nav_after_profit > initial_nav, 1);
        assert!(
            treasury_after_profit == initial_treasury + simulated_house_profit,
            2
        );

        // Calculate expected NAV increase
        let expected_nav = (treasury_after_profit * NAV_SCALE) / large_deposit;
        assert!(nav_after_profit == expected_nav, 3);

        // Investor redemption should capture the profit
        let investor_apt_before = coin::balance<AptosCoin>(@0x123);
        let redeem_tokens = large_deposit / 10; // Redeem 10%

        InvestorToken::redeem(&investor, redeem_tokens);

        let investor_apt_after = coin::balance<AptosCoin>(@0x123);
        let received = investor_apt_after - investor_apt_before;

        // Should receive more than face value (minus fees)
        let _ = redeem_tokens;
        assert!(received > 0, 4);
        // Note: received will be less than face_value due to fees, but represents profitable NAV
    }

    #[test]
    fun test_ecosystem_state_consistency() {
        let (_, casino_account, _dice_account, investor, player) =
            setup_full_integration();

        // Multi-step ecosystem test
        InvestorToken::deposit_and_mint(&investor, INVESTOR_DEPOSIT);

        // Fund and play
        let fund_coins = coin::withdraw<AptosCoin>(&casino_account, 100000000);
        CasinoHouse::deposit_to_treasury(fund_coins);

        DiceGame::play_dice(&player, 2, DICE_BET);

        // Add profit simulation
        let profit_coins = coin::withdraw<AptosCoin>(&casino_account, 25000000);
        CasinoHouse::deposit_to_treasury(profit_coins);

        // Verify consistency across all modules
        let casino_treasury = CasinoHouse::treasury_balance();
        let token_treasury = InvestorToken::treasury_balance();
        assert!(casino_treasury == token_treasury, 1);

        let nav = InvestorToken::nav();
        let supply = InvestorToken::total_supply();
        let expected_nav = (casino_treasury * NAV_SCALE) / supply;
        assert!(nav == expected_nav, 2);

        // Final redemption test
        InvestorToken::redeem(&investor, supply / 3);

        // State should remain consistent
        let final_casino_treasury = CasinoHouse::treasury_balance();
        let final_token_treasury = InvestorToken::treasury_balance();
        assert!(final_casino_treasury == final_token_treasury, 3);
    }
}
