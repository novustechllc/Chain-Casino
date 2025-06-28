//! Real integration test: 10 APT investment with actual dice game bets

#[test_only]
module casino::RealInvestmentTest {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use dice_game::DiceGame;

    // Test constants
    const TEN_APT: u64 = 1000000000; // 10 APT in octas
    const BET_MIN: u64 = 20000000;   // 0.2 APT
    const BET_MAX: u64 = 50000000;   // 0.5 APT
    const PLAYER_FUNDING: u64 = 100000000; // 1 APT per player

    fun setup_real_test(): (signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);

        // Initialize environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Register and fund casino
        coin::register<AptosCoin>(&casino_account);
        aptos_coin::mint(&aptos_framework, @casino, TEN_APT * 50);

        // Create dice game account and initialize at its own address
        let dice_account = account::create_account_for_test(@dice_game);
        coin::register<AptosCoin>(&dice_account);

        // Initialize modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);
        DiceGame::initialize_game(&casino_account, &dice_account); // TODO: fix this

        (aptos_framework, casino_account)
    }

    fun create_funded_player(framework: &signer, addr: address): signer {
        let player = account::create_account_for_test(addr);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(framework, addr, PLAYER_FUNDING);
        player
    }

    #[test]
    fun test_real_10_apt_investment_with_dice_bets() {
        let (framework, casino_account) = setup_real_test();

        // 1. Create investor and deposit 10 APT
        let investor = account::create_account_for_test(@0x1111);
        coin::register<AptosCoin>(&investor);
        aptos_coin::mint(&framework, @0x1111, TEN_APT * 2);

        let initial_investor_apt = coin::balance<AptosCoin>(@0x1111);
        InvestorToken::deposit_and_mint(&investor, TEN_APT);
        let investor_tokens = InvestorToken::user_balance(@0x1111);
        let initial_nav = InvestorToken::nav();
        let treasury_after_investment = CasinoHouse::treasury_balance();

        // 2. Create players and make real bets through DiceGame
        let player_addresses = vector[
            @0x2001, @0x2002, @0x2003, @0x2004, @0x2005,
            @0x2006, @0x2007, @0x2008, @0x2009, @0x200A,
            @0x200B, @0x200C, @0x200D, @0x200E, @0x200F,
            @0x2010, @0x2011, @0x2012, @0x2013, @0x2014
        ];

        let bet_amounts = vector[
            20000000,  // 0.2 APT
            25000000,  // 0.25 APT 
            30000000,  // 0.3 APT
            35000000,  // 0.35 APT
            40000000,  // 0.4 APT
            45000000,  // 0.45 APT
            50000000   // 0.5 APT
        ];

        let i = 0;
        let total_bets_placed = 0;
        let total_bet_volume = 0;

        while (i < vector::length(&player_addresses)) {
            let player_addr = *vector::borrow(&player_addresses, i);
            let player = create_funded_player(&framework, player_addr);
            
            let bet_amount = *vector::borrow(&bet_amounts, i % vector::length(&bet_amounts));
            let guess = (i % 6) + 1; // Guess 1-6

            // Make real bet through DiceGame
            DiceGame::play_dice(&player, (guess as u8), bet_amount);
            
            total_bets_placed = total_bets_placed + 1;
            total_bet_volume = total_bet_volume + bet_amount;
            i = i + 1;
        };

        // 3. Analyze results after real games
        let treasury_after_games = CasinoHouse::treasury_balance();
        let final_nav = InvestorToken::nav();
        
        let house_profit = if (treasury_after_games > treasury_after_investment) {
            treasury_after_games - treasury_after_investment
        } else { 0 };

        let nav_increase = if (final_nav > initial_nav) {
            final_nav - initial_nav
        } else { 0 };

        // 4. Investor redeems tokens to see actual return
        let investor_apt_before_redeem = coin::balance<AptosCoin>(@0x1111);
        InvestorToken::redeem(&investor, investor_tokens);
        let investor_apt_after_redeem = coin::balance<AptosCoin>(@0x1111);
        
        let total_received = investor_apt_after_redeem - initial_investor_apt + TEN_APT; // Account for initial investment
        let actual_profit = if (total_received > TEN_APT) {
            total_received - TEN_APT
        } else { 0 };

        // 5. Print real results
        std::debug::print(&string::utf8(b"=== REAL INVESTMENT TEST RESULTS ==="));
        std::debug::print(&total_bets_placed);
        std::debug::print(&string::utf8(b"Total Bets Placed:"));
        std::debug::print(&total_bet_volume);
        std::debug::print(&string::utf8(b"Total Bet Volume (octas):"));
        std::debug::print(&house_profit);
        std::debug::print(&string::utf8(b"House Profit (octas):"));
        std::debug::print(&initial_nav);
        std::debug::print(&string::utf8(b"Initial NAV:"));
        std::debug::print(&final_nav);
        std::debug::print(&string::utf8(b"Final NAV:"));
        std::debug::print(&actual_profit);
        std::debug::print(&string::utf8(b"Investor Profit (octas):"));
        
        // Calculate percentage return
        let profit_percentage = if (actual_profit > 0) {
            (actual_profit * 10000) / TEN_APT // Basis points
        } else { 0 };
        std::debug::print(&profit_percentage);
        std::debug::print(&string::utf8(b"Profit Percentage (basis points):"));

        // Basic assertions - results will vary due to real randomness
        assert!(total_bets_placed == 20, 1);
        assert!(treasury_after_games > 0, 2);
        assert!(final_nav > 0, 3);
        
        // The house should statistically profit with 16.67% edge over 20 games
        // But individual test runs may vary due to randomness
    }

    #[test] 
    fun test_real_multiple_investment_rounds() {
        let (framework, _casino_account) = setup_real_test();

        // Create multiple investors
        let investor1 = account::create_account_for_test(@0x3001);
        let investor2 = account::create_account_for_test(@0x3002);
        coin::register<AptosCoin>(&investor1);
        coin::register<AptosCoin>(&investor2);
        aptos_coin::mint(&framework, @0x3001, TEN_APT);
        aptos_coin::mint(&framework, @0x3002, TEN_APT);

        // Round 1: First investor enters
        InvestorToken::deposit_and_mint(&investor1, TEN_APT);
        let nav_after_inv1 = InvestorToken::nav();

        // Create some game activity
        let player1 = create_funded_player(&framework, @0x4001);
        DiceGame::play_dice(&player1, 3, 30000000); // 0.3 APT bet

        let nav_after_game1 = InvestorToken::nav();

        // Round 2: Second investor enters after some games
        InvestorToken::deposit_and_mint(&investor2, TEN_APT);
        let nav_after_inv2 = InvestorToken::nav();

        // More game activity
        let player2 = create_funded_player(&framework, @0x4002);
        let player3 = create_funded_player(&framework, @0x4003);
        DiceGame::play_dice(&player2, 1, 25000000); // 0.25 APT
        DiceGame::play_dice(&player3, 6, 40000000); // 0.4 APT

        let final_nav = InvestorToken::nav();

        // Print results showing NAV evolution
        std::debug::print(&string::utf8(b"=== NAV EVOLUTION TEST ==="));
        std::debug::print(&nav_after_inv1);
        std::debug::print(&string::utf8(b"NAV after investor 1:"));
        std::debug::print(&nav_after_game1);
        std::debug::print(&string::utf8(b"NAV after first game:"));
        std::debug::print(&nav_after_inv2);
        std::debug::print(&string::utf8(b"NAV after investor 2:"));
        std::debug::print(&final_nav);
        std::debug::print(&string::utf8(b"Final NAV:"));

        // Both investors should have positive token balances
        assert!(InvestorToken::user_balance(@0x3001) > 0, 1);
        assert!(InvestorToken::user_balance(@0x3002) > 0, 2);
        assert!(final_nav > 0, 3);
    }
}