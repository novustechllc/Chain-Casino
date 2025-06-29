//! MIT License
//!
//! Comprehensive Integration Tests for ChainCasino Platform (Object-Based Refactor)
//!
//! Updated for object-based game architecture with deterministic addressing

#[test_only]
module casino::ComprehensiveIntegrationTest {
    use std::string;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::InvestorToken;
    use casino::CasinoHouse;
    use dice_game::DiceGame;
    use slot_game::SlotMachine;

    // Test constants
    const LARGE_BALANCE: u64 = 50000000000; // 500 APT
    const INVESTOR_DEPOSIT: u64 = 1000000000; // 10 APT
    const PLAYER_FUNDING: u64 = 500000000; // 5 APT
    const DICE_BET: u64 = 50000000; // 0.5 APT
    const SLOT_BET: u64 = 25000000; // 0.25 APT

    // Real-world addresses
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @dice_game;
    const SLOT_ADDR: address = @slot_game;
    const INVESTOR1_ADDR: address = @0x1001;
    const INVESTOR2_ADDR: address = @0x1002;
    const PLAYER1_ADDR: address = @0x2001;
    const PLAYER2_ADDR: address = @0x2002;
    const WHALE_ADDR: address = @0x3000;

    fun setup_comprehensive_test(): (
        signer, signer, signer, signer, signer, signer, signer, signer
    ) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_signer = account::create_account_for_test(CASINO_ADDR);
        let dice_signer = account::create_account_for_test(DICE_ADDR);
        let slot_signer = account::create_account_for_test(SLOT_ADDR);
        let investor1 = account::create_account_for_test(INVESTOR1_ADDR);
        let investor2 = account::create_account_for_test(INVESTOR2_ADDR);
        let player1 = account::create_account_for_test(PLAYER1_ADDR);
        let player2 = account::create_account_for_test(PLAYER2_ADDR);

        // Initialize Aptos environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Register all accounts for APT
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        primary_fungible_store::ensure_primary_store_exists(CASINO_ADDR, aptos_metadata);
        primary_fungible_store::ensure_primary_store_exists(DICE_ADDR, aptos_metadata);
        primary_fungible_store::ensure_primary_store_exists(SLOT_ADDR, aptos_metadata);
        primary_fungible_store::ensure_primary_store_exists(
            INVESTOR1_ADDR, aptos_metadata
        );
        primary_fungible_store::ensure_primary_store_exists(
            INVESTOR2_ADDR, aptos_metadata
        );
        primary_fungible_store::ensure_primary_store_exists(
            PLAYER1_ADDR, aptos_metadata
        );
        primary_fungible_store::ensure_primary_store_exists(
            PLAYER2_ADDR, aptos_metadata
        );

        // Mint APT to all accounts
        aptos_coin::mint(&aptos_framework, CASINO_ADDR, LARGE_BALANCE);
        aptos_coin::mint(&aptos_framework, DICE_ADDR, LARGE_BALANCE);
        aptos_coin::mint(&aptos_framework, SLOT_ADDR, LARGE_BALANCE);
        aptos_coin::mint(&aptos_framework, INVESTOR1_ADDR, LARGE_BALANCE);
        aptos_coin::mint(&aptos_framework, INVESTOR2_ADDR, LARGE_BALANCE);
        aptos_coin::mint(&aptos_framework, PLAYER1_ADDR, PLAYER_FUNDING);
        aptos_coin::mint(&aptos_framework, PLAYER2_ADDR, PLAYER_FUNDING);

        (
            aptos_framework,
            casino_signer,
            dice_signer,
            slot_signer,
            investor1,
            investor2,
            player1,
            player2
        )
    }

    #[test]
    fun test_full_casino_ecosystem_lifecycle() {
        let (
            _,
            casino_signer,
            dice_signer,
            slot_signer,
            investor1,
            investor2,
            player1,
            player2
        ) = setup_comprehensive_test();

        // === PHASE 1: INITIALIZATION ===

        // Initialize casino modules
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Register games with casino (by module address)
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1667 // 16.67% house edge
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1550 // 15.5% house edge
        );

        // Games initialize themselves (creates objects and claims capabilities)
        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Verify ecosystem state
        assert!(CasinoHouse::is_game_registered(DICE_ADDR), 1);
        assert!(CasinoHouse::is_game_registered(SLOT_ADDR), 2);
        assert!(DiceGame::is_ready(), 3);
        assert!(SlotMachine::is_ready(), 4);

        // Verify objects exist
        assert!(DiceGame::object_exists(), 5);
        assert!(SlotMachine::object_exists(), 6);

        assert!(CasinoHouse::treasury_balance() == 0, 7);
        assert!(InvestorToken::total_supply() == 0, 8);

        // === PHASE 2: INVESTMENT PHASE ===

        // Multiple investors enter at different times
        InvestorToken::deposit_and_mint(&investor1, INVESTOR_DEPOSIT);
        let nav_after_first = InvestorToken::nav();

        // Massive treasury reserve for slot machine max payout (100x)
        let massive_reserve = 10000000000; // 100 APT reserve
        let reserve_fa =
            primary_fungible_store::withdraw(
                &casino_signer,
                option::extract(&mut coin::paired_metadata<AptosCoin>()),
                massive_reserve
            );
        CasinoHouse::deposit_to_treasury(reserve_fa);

        InvestorToken::deposit_and_mint(&investor2, INVESTOR_DEPOSIT / 2); // 5 APT
        let total_investment = INVESTOR_DEPOSIT + (INVESTOR_DEPOSIT / 2);

        // Treasury should have substantial funds
        assert!(CasinoHouse::treasury_balance() > total_investment, 9);
        assert!(InvestorToken::total_supply() > 0, 10);

        // === PHASE 3: GAMING ACTIVITY ===

        let initial_treasury = CasinoHouse::treasury_balance();

        // Dice game activity
        DiceGame::test_only_play_dice(&player1, 1, DICE_BET);
        DiceGame::test_only_play_dice(&player1, 6, DICE_BET);
        DiceGame::test_only_play_dice(&player2, 3, DICE_BET);

        // Slot machine activity
        SlotMachine::test_only_spin_slots(&player1, SLOT_BET);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET);

        let treasury_after_games = CasinoHouse::treasury_balance();

        // Treasury should still have funds
        assert!(treasury_after_games > 0, 11);

        // === PHASE 4: HOUSE EDGE SIMULATION ===

        // Simulate accumulated house profits
        let house_profit = 150000000; // 1.5 APT profit
        let profit_fa =
            primary_fungible_store::withdraw(
                &casino_signer,
                option::extract(&mut coin::paired_metadata<AptosCoin>()),
                house_profit
            );
        CasinoHouse::deposit_to_treasury(profit_fa);

        let nav_with_profits = InvestorToken::nav();
        assert!(nav_with_profits > nav_after_first, 12);

        // === PHASE 5: REDEMPTION & PROFIT TAKING ===

        // Investor 1 redeems 50% at profit
        let investor1_tokens = InvestorToken::user_balance(INVESTOR1_ADDR);
        let redeem_amount = investor1_tokens / 2;

        let investor1_apt_before =
            primary_fungible_store::balance(
                INVESTOR1_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::redeem(&investor1, redeem_amount);

        let investor1_apt_after =
            primary_fungible_store::balance(
                INVESTOR1_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let profit_received = investor1_apt_after - investor1_apt_before;
        assert!(profit_received > 0, 13);

        // === PHASE 6: CONTINUED OPERATIONS ===

        // More gaming activity
        DiceGame::test_only_play_dice(&player1, 4, DICE_BET / 2);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET / 2);

        // Investor 2 also redeems partially
        let investor2_tokens = InvestorToken::user_balance(INVESTOR2_ADDR);
        InvestorToken::redeem(&investor2, investor2_tokens / 3);

        // === FINAL VERIFICATION ===

        let final_treasury = CasinoHouse::treasury_balance();
        let final_supply = InvestorToken::total_supply();
        let final_nav = InvestorToken::nav();

        // System consistency checks
        assert!(final_treasury > 0, 14);
        assert!(final_supply > 0, 15);
        assert!(final_nav > 0, 16);

        // Both games still operational
        assert!(DiceGame::is_ready(), 17);
        assert!(SlotMachine::is_ready(), 18);

        // Investors still have remaining positions
        assert!(InvestorToken::user_balance(INVESTOR1_ADDR) > 0, 19);
        assert!(InvestorToken::user_balance(INVESTOR2_ADDR) > 0, 20);

        // Object verification
        assert!(DiceGame::object_exists(), 21);
        assert!(SlotMachine::object_exists(), 22);
    }

    #[test]
    fun test_object_address_derivation() {
        let (_, casino_signer, dice_signer, slot_signer, _, _, _, _) =
            setup_comprehensive_test();

        // Initialize ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            1000000,
            50000000,
            1667
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            1000000,
            50000000,
            1550
        );

        // Initialize games (creates objects)
        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Test derivation matches actual addresses
        let dice_derived =
            CasinoHouse::derive_game_object_address(
                DICE_ADDR,
                string::utf8(b"DiceGame"),
                string::utf8(b"v1")
            );

        let slot_derived =
            CasinoHouse::derive_game_object_address(
                SLOT_ADDR,
                string::utf8(b"SlotMachine"),
                string::utf8(b"v1")
            );

        let dice_actual = DiceGame::get_game_object_address();
        let slot_actual = SlotMachine::get_game_object_address();

        assert!(dice_derived == dice_actual, 1);
        assert!(slot_derived == slot_actual, 2);

        // Test game info retrieval
        let (dice_creator, dice_obj_addr, dice_name, dice_version) =
            DiceGame::get_game_info();
        assert!(dice_creator == DICE_ADDR, 3);
        assert!(dice_obj_addr == dice_actual, 4);
        assert!(dice_name == string::utf8(b"DiceGame"), 5);
        assert!(dice_version == string::utf8(b"v1"), 6);
    }

    #[test]
    fun test_high_volume_whale_scenario() {
        let (_, casino_signer, dice_signer, slot_signer, investor1, _, _, _) =
            setup_comprehensive_test();

        // Setup ecosystem
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            1000000,
            50000000,
            1667
        );

        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            1000000,
            50000000,
            1550
        );

        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Large investor provides liquidity
        let large_investment = 5000000000; // 50 APT
        InvestorToken::deposit_and_mint(&investor1, large_investment);

        // Treasury reserve
        let massive_reserve = 10000000000; // 100 APT reserve
        let reserve_fa =
            primary_fungible_store::withdraw(
                &casino_signer,
                option::extract(&mut coin::paired_metadata<AptosCoin>()),
                massive_reserve
            );
        CasinoHouse::deposit_to_treasury(reserve_fa);

        // Create whale player
        let whale = account::create_account_for_test(WHALE_ADDR);
        primary_fungible_store::ensure_primary_store_exists(
            WHALE_ADDR,
            option::extract(&mut coin::paired_metadata<AptosCoin>())
        );
        aptos_coin::mint(
            &account::create_account_for_test(@aptos_framework),
            WHALE_ADDR,
            2000000000 // 20 APT
        );

        let initial_treasury = CasinoHouse::treasury_balance();
        let initial_nav = InvestorToken::nav();

        // High-volume whale activity
        let (_, dice_max_bet, _, _) = DiceGame::get_game_config();
        let (_, slot_max_bet, _) = SlotMachine::get_game_config();
        let large_bet = dice_max_bet;

        // Multiple large bets
        DiceGame::test_only_play_dice(&whale, 1, large_bet);
        DiceGame::test_only_play_dice(&whale, 2, large_bet);
        DiceGame::test_only_play_dice(&whale, 3, large_bet);
        SlotMachine::test_only_spin_slots(&whale, large_bet);
        SlotMachine::test_only_spin_slots(&whale, large_bet);

        let treasury_after_whale = CasinoHouse::treasury_balance();
        assert!(treasury_after_whale > initial_treasury, 1);

        // Simulate house edge accumulation
        let accumulated_edge = 200000000; // 2 APT house profit
        let edge_fa =
            primary_fungible_store::withdraw(
                &casino_signer,
                option::extract(&mut coin::paired_metadata<AptosCoin>()),
                accumulated_edge
            );
        CasinoHouse::deposit_to_treasury(edge_fa);

        let final_nav = InvestorToken::nav();
        assert!(final_nav > initial_nav, 2);

        // Investor can redeem at profit
        let investor_tokens = InvestorToken::user_balance(INVESTOR1_ADDR);
        let redemption = investor_tokens / 4;

        let apt_before =
            primary_fungible_store::balance(
                INVESTOR1_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        InvestorToken::redeem(&investor1, redemption);

        let apt_after =
            primary_fungible_store::balance(
                INVESTOR1_ADDR,
                option::extract(&mut coin::paired_metadata<AptosCoin>())
            );

        let whale_profit_captured = apt_after - apt_before;
        assert!(whale_profit_captured > redemption, 3);

        // System remains stable
        assert!(CasinoHouse::treasury_balance() > 0, 4);
        assert!(InvestorToken::total_supply() > 0, 5);
        assert!(DiceGame::is_ready(), 6);
        assert!(SlotMachine::is_ready(), 7);
        assert!(DiceGame::object_exists(), 8);
        assert!(SlotMachine::object_exists(), 9);
    }
}
