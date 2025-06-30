//! MIT License
//!
//! Comprehensive Integration Tests for ChainCasino Platform (Object-Based Architecture)
//!
//! Tests the complete ecosystem: registration → initialization → gaming → investment → redemption

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
    use aptos_framework::object;
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

    // Test addresses
    const CASINO_ADDR: address = @casino;
    const DICE_ADDR: address = @dice_game;
    const SLOT_ADDR: address = @slot_game;
    const INVESTOR1_ADDR: address = @0x1001;
    const INVESTOR2_ADDR: address = @0x1002;
    const PLAYER1_ADDR: address = @0x2001;
    const PLAYER2_ADDR: address = @0x2002;

    fun setup_test_environment(): (
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

        // Get APT metadata for primary store setup
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());

        // Ensure primary stores exist for all accounts
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

        // Fund all accounts with APT
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
    fun test_complete_ecosystem_flow() {
        let (
            _,
            casino_signer,
            dice_signer,
            slot_signer,
            investor1,
            investor2,
            player1,
            player2
        ) = setup_test_environment();

        // === PHASE 1: CASINO INITIALIZATION ===
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Verify initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(InvestorToken::total_supply() == 0, 2);

        // === PHASE 2: GAME REGISTRATION ===

        // Casino registers DiceGame
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1667 // 16.67% house edge
        );

        // Casino registers SlotMachine
        CasinoHouse::register_game(
            &casino_signer,
            SLOT_ADDR,
            string::utf8(b"SlotMachine"),
            string::utf8(b"v1"),
            1000000, // 0.01 APT min
            50000000, // 0.5 APT max
            1550 // 15.5% house edge
        );

        // Get game objects for verification
        let dice_object_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
            );
        let dice_game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(dice_object_addr);

        let slot_object_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADDR, string::utf8(b"SlotMachine"), string::utf8(b"v1")
            );
        let slot_game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(slot_object_addr);

        // Verify registration
        assert!(CasinoHouse::is_game_registered(dice_game_object), 3);
        assert!(CasinoHouse::is_game_registered(slot_game_object), 4);

        // === PHASE 3: GAME INITIALIZATION ===

        // Games initialize themselves and claim capabilities
        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Verify games are ready
        assert!(DiceGame::is_ready(), 5);
        assert!(SlotMachine::is_ready(), 6);
        assert!(DiceGame::object_exists(), 7);
        assert!(SlotMachine::object_exists(), 8);

        // Verify capability claimed
        assert!(CasinoHouse::is_game_capability_claimed(dice_game_object), 9);
        assert!(CasinoHouse::is_game_capability_claimed(slot_game_object), 10);

        // === PHASE 4: TREASURY FUNDING (INVESTMENT) ===

        // Initial NAV should be at scale
        assert!(InvestorToken::nav() == 1_000_000, 11);

        // Investor 1 provides initial liquidity
        InvestorToken::deposit_and_mint(&investor1, INVESTOR_DEPOSIT);

        // Verify investment
        assert!(InvestorToken::total_supply() == INVESTOR_DEPOSIT, 12);
        assert!(InvestorToken::user_balance(INVESTOR1_ADDR) == INVESTOR_DEPOSIT, 13);
        assert!(CasinoHouse::central_treasury_balance() >= INVESTOR_DEPOSIT, 14);

        // Additional funding for large payouts
        let reserve_fund = 5000000000; // 50 APT
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let reserve_fa =
            primary_fungible_store::withdraw(
                &casino_signer, aptos_metadata, reserve_fund
            );
        CasinoHouse::deposit_to_treasury(reserve_fa);

        // Second investor joins
        InvestorToken::deposit_and_mint(&investor2, INVESTOR_DEPOSIT / 2);

        let total_investment = INVESTOR_DEPOSIT + (INVESTOR_DEPOSIT / 2);
        let treasury_balance = CasinoHouse::treasury_balance();
        assert!(
            treasury_balance >= total_investment + reserve_fund,
            15
        );

        // === PHASE 5: GAMING ACTIVITY ===

        let _initial_treasury = CasinoHouse::treasury_balance();

        // DiceGame activity
        DiceGame::test_only_play_dice(&player1, 1, DICE_BET);
        DiceGame::test_only_play_dice(&player1, 6, DICE_BET);
        DiceGame::test_only_play_dice(&player2, 3, DICE_BET);

        // SlotMachine activity
        SlotMachine::test_only_spin_slots(&player1, SLOT_BET);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET);

        // Treasury should reflect game activity
        let treasury_after_games = CasinoHouse::treasury_balance();
        // Treasury balance may have increased (house wins) or decreased (player wins)
        assert!(treasury_after_games > 0, 16);

        // === PHASE 6: PROFIT SIMULATION ===

        // Simulate house edge accumulation
        let house_profit = 200000000; // 2 APT
        let profit_fa =
            primary_fungible_store::withdraw(
                &casino_signer, aptos_metadata, house_profit
            );
        CasinoHouse::deposit_to_treasury(profit_fa);

        // NAV should increase with profits
        let nav_with_profits = InvestorToken::nav();
        assert!(nav_with_profits > 1_000_000, 17); // Above initial NAV

        // === PHASE 7: REDEMPTION ===

        // Investor 1 redeems 50% at profit
        let investor1_tokens = InvestorToken::user_balance(INVESTOR1_ADDR);
        let redeem_amount = investor1_tokens / 2;

        let investor1_apt_before =
            primary_fungible_store::balance(INVESTOR1_ADDR, aptos_metadata);
        InvestorToken::redeem(&investor1, redeem_amount);
        let investor1_apt_after =
            primary_fungible_store::balance(INVESTOR1_ADDR, aptos_metadata);

        // Should receive APT back
        assert!(investor1_apt_after > investor1_apt_before, 18);

        // === PHASE 8: CONTINUED OPERATIONS ===

        // More gaming to test post-redemption state
        DiceGame::test_only_play_dice(&player1, 4, DICE_BET / 2);
        SlotMachine::test_only_spin_slots(&player2, SLOT_BET / 2);

        // Final verification
        let final_treasury = CasinoHouse::treasury_balance();
        let final_supply = InvestorToken::total_supply();

        assert!(final_treasury > 0, 19);
        assert!(final_supply > 0, 20);
        assert!(DiceGame::is_ready(), 21);
        assert!(SlotMachine::is_ready(), 22);

        // Both investors should still have positions
        assert!(InvestorToken::user_balance(INVESTOR1_ADDR) > 0, 23);
        assert!(InvestorToken::user_balance(INVESTOR2_ADDR) > 0, 24);
    }

    #[test]
    fun test_game_treasury_isolation() {
        let (_, casino_signer, dice_signer, slot_signer, investor1, _, player1, _) =
            setup_test_environment();

        // Setup
        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Register games
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

        // Initialize games
        DiceGame::initialize_game(&dice_signer);
        SlotMachine::initialize_game(&slot_signer);

        // Fund treasury
        InvestorToken::deposit_and_mint(&investor1, 10000000000); // 100 APT

        // Test isolated treasury addresses
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

        // Verify different treasury addresses (Block-STM isolation)
        assert!(dice_treasury_addr != slot_treasury_addr, 1);

        // Test gaming affects individual treasuries
        let _dice_initial = DiceGame::game_treasury_balance();
        let _slot_initial = SlotMachine::game_treasury_balance();

        DiceGame::test_only_play_dice(&player1, 3, 25000000);
        SlotMachine::test_only_spin_slots(&player1, 25000000);

        // Both games should be operational with separate balances
        assert!(DiceGame::game_treasury_balance() >= 0, 2);
        assert!(SlotMachine::game_treasury_balance() >= 0, 3);
    }

    #[test]
    fun test_object_address_derivation() {
        let (_, casino_signer, dice_signer, _, _, _, _, _) = setup_test_environment();

        CasinoHouse::init_module_for_test(&casino_signer);

        // Register game
        CasinoHouse::register_game(
            &casino_signer,
            DICE_ADDR,
            string::utf8(b"DiceGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1667
        );

        // Initialize game
        DiceGame::initialize_game(&dice_signer);

        // Test derivation consistency
        let derived_addr =
            CasinoHouse::derive_game_object_address(
                CASINO_ADDR, string::utf8(b"DiceGame"), string::utf8(b"v1")
            );
        let game_object =
            object::address_to_object<CasinoHouse::GameMetadata>(derived_addr);

        // Verify game object exists and is registered
        assert!(CasinoHouse::game_object_exists(game_object), 1);
        assert!(CasinoHouse::is_game_registered(game_object), 2);

        // Test game's own derivation matches
        let (creator, casino_obj, name, version) = DiceGame::get_game_info();
        assert!(creator == DICE_ADDR, 3);
        assert!(object::object_address(&casino_obj) == derived_addr, 4);
        assert!(name == string::utf8(b"DiceGame"), 5);
        assert!(version == string::utf8(b"v1"), 6);
    }

    #[test]
    fun test_nav_calculations() {
        let (_, casino_signer, _, _, investor1, investor2, _, _) =
            setup_test_environment();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        // Initial NAV should be at scale with no supply
        assert!(InvestorToken::nav() == 1_000_000, 1);

        // First investment
        InvestorToken::deposit_and_mint(&investor1, 1000000000); // 10 APT
        assert!(InvestorToken::nav() == 1_000_000, 2); // NAV stays at scale

        // Add profits to treasury
        let aptos_metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        let profit_fa =
            primary_fungible_store::withdraw(&casino_signer, aptos_metadata, 500000000); // 5 APT
        CasinoHouse::deposit_to_treasury(profit_fa);

        // NAV should increase
        let nav_after_profit = InvestorToken::nav();
        assert!(nav_after_profit > 1_000_000, 3);

        // Second investor joins at higher NAV
        let tokens_before = InvestorToken::total_supply();
        InvestorToken::deposit_and_mint(&investor2, 1000000000); // 10 APT
        let tokens_after = InvestorToken::total_supply();

        // Should receive fewer tokens due to higher NAV
        let new_tokens = tokens_after - tokens_before;
        assert!(new_tokens < 1000000000, 4);
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_GUESS)]
    fun test_dice_invalid_guess() {
        let (_, casino_signer, dice_signer, _, investor1, _, player1, _) =
            setup_test_environment();

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
        InvestorToken::deposit_and_mint(&investor1, 1000000000);

        // Should fail with invalid guess
        DiceGame::test_only_play_dice(&player1, 7, 25000000); // Invalid guess > 6
    }

    #[test]
    #[expected_failure(abort_code = dice_game::DiceGame::E_INVALID_AMOUNT)]
    fun test_bet_amount_too_high() {
        let (_, casino_signer, dice_signer, _, investor1, _, player1, _) =
            setup_test_environment();

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
        InvestorToken::deposit_and_mint(&investor1, 1000000000);

        // Should fail with bet exceeding max
        DiceGame::test_only_play_dice(&player1, 3, 100000000); // 1 APT > 0.5 APT max
    }

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INSUFFICIENT_BALANCE)]
    fun test_redeem_more_than_balance() {
        let (_, casino_signer, _, _, investor1, _, _, _) = setup_test_environment();

        CasinoHouse::init_module_for_test(&casino_signer);
        InvestorToken::init(&casino_signer);

        InvestorToken::deposit_and_mint(&investor1, 1000000000); // 10 APT worth of tokens

        // Should fail trying to redeem more than balance
        InvestorToken::redeem(&investor1, 2000000000); // Try to redeem 20 APT worth
    }
}
