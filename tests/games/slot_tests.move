//! MIT License
//!
//! Comprehensive test suite for SlotMachine module

#[test_only]
module slot_game::SlotMachineTest {
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use casino::CasinoHouse;
    use slot_game::SlotMachine;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000000; // 10 APT
    const MIN_BET: u64 = 1000000; // 0.01 APT
    const MAX_BET: u64 = 50000000; // 0.5 APT
    const TEST_BET: u64 = 10000000; // 0.1 APT

    // Error constants from SlotMachine module
    const E_INVALID_AMOUNT: u64 = 0x01;
    const E_UNAUTHORIZED: u64 = 0x02;
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    const E_ALREADY_INITIALIZED: u64 = 0x04;

    // Symbol constants
    const SYMBOL_CHERRY: u8 = 1;
    const SYMBOL_BELL: u8 = 2;
    const SYMBOL_COIN: u8 = 3;
    const SYMBOL_CHAIN: u8 = 4;
    const SYMBOL_SEVEN: u8 = 5;

    fun setup_basic_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let slot_account = account::create_account_for_test(@slot_game);

        // Initialize environment
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);
        randomness::initialize_for_testing(&aptos_framework);

        // Register coin accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&slot_account);

        // Mint initial balances
        aptos_coin::mint(&aptos_framework, @casino, INITIAL_BALANCE * 10);
        aptos_coin::mint(&aptos_framework, @slot_game, INITIAL_BALANCE);

        (aptos_framework, casino_account, slot_account)
    }

    // Helper to setup casino
    fun setup_with_casino(): (signer, signer, signer) {
        let (aptos_framework, casino_account, slot_account) = setup_basic_test();

        // Initialize casino
        CasinoHouse::init_module_for_test(&casino_account);

        (aptos_framework, casino_account, slot_account)
    }

    fun create_funded_player(
        framework: &signer, addr: address, balance: u64
    ): signer {
        let player = account::create_account_for_test(addr);
        coin::register<AptosCoin>(&player);
        aptos_coin::mint(framework, addr, balance);
        player
    }

    //
    // View Function Tests (No dependency on casino state)
    //

    #[test]
    fun test_get_game_config() {
        let (min_bet, max_bet, house_edge) = SlotMachine::get_game_config();
        assert!(min_bet == MIN_BET, 1);
        assert!(max_bet == MAX_BET, 2);
        assert!(house_edge == 1550, 3); // 15.5% house edge
    }

    #[test]
    fun test_get_symbol_weights() {
        let (cherry, bell, coin, chain, seven) = SlotMachine::get_symbol_weights();
        assert!(cherry == 40, 1);
        assert!(bell == 30, 2);
        assert!(coin == 20, 3);
        assert!(chain == 8, 4);
        assert!(seven == 2, 5);

        // Verify weights sum to 100
        assert!(cherry + bell + coin + chain + seven == 100, 6);
    }

    #[test]
    fun test_get_payout_multipliers() {
        let (cherry, bell, coin, chain, seven) = SlotMachine::get_payout_multipliers();
        assert!(cherry == 5, 1);
        assert!(bell == 10, 2);
        assert!(coin == 25, 3);
        assert!(chain == 100, 4);
        assert!(seven == 500, 5);
    }

    #[test]
    fun test_calculate_symbol_payout() {
        let bet = 10000000; // 0.1 APT

        assert!(
            SlotMachine::calculate_symbol_payout(bet, SYMBOL_CHERRY) == bet * 5,
            1
        );
        assert!(
            SlotMachine::calculate_symbol_payout(bet, SYMBOL_BELL) == bet * 10,
            2
        );
        assert!(
            SlotMachine::calculate_symbol_payout(bet, SYMBOL_COIN) == bet * 25,
            3
        );
        assert!(
            SlotMachine::calculate_symbol_payout(bet, SYMBOL_CHAIN) == bet * 100,
            4
        );
        assert!(
            SlotMachine::calculate_symbol_payout(bet, SYMBOL_SEVEN) == bet * 500,
            5
        );
        assert!(SlotMachine::calculate_symbol_payout(bet, 99) == 0, 6); // Invalid symbol
    }

    #[test]
    fun test_get_symbol_name() {
        assert!(SlotMachine::get_symbol_name(SYMBOL_CHERRY) == b"Cherry", 1);
        assert!(SlotMachine::get_symbol_name(SYMBOL_BELL) == b"Bell", 2);
        assert!(SlotMachine::get_symbol_name(SYMBOL_COIN) == b"Coin", 3);
        assert!(SlotMachine::get_symbol_name(SYMBOL_CHAIN) == b"Chain", 4);
        assert!(SlotMachine::get_symbol_name(SYMBOL_SEVEN) == b"Seven", 5);
        assert!(SlotMachine::get_symbol_name(99) == b"Unknown", 6);
    }

    #[test]
    fun test_status_functions_before_setup() {
        let (_, _, _) = setup_with_casino();

        // Before any setup
        assert!(!SlotMachine::is_registered(), 1);
        assert!(!SlotMachine::is_initialized(), 2);
        assert!(!SlotMachine::is_ready(), 3);
    }

    //
    // Initialization Error Tests
    //

    #[test]
    #[expected_failure(abort_code = E_UNAUTHORIZED, location = slot_game::SlotMachine)]
    fun test_initialize_unauthorized_signer() {
        let (_, casino_account, _) = setup_basic_test();

        // Try to initialize with casino signer instead of slot_game signer
        SlotMachine::initialize_game(&casino_account);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_GAME_NOT_REGISTERED, location = slot_game::SlotMachine
        )
    ]
    fun test_initialize_not_registered() {
        let (_, _, slot_account) = setup_with_casino();

        // Try to initialize without casino registration
        SlotMachine::initialize_game(&slot_account);
    }

    //
    // Input Validation Tests (Using test_only function)
    //

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = slot_game::SlotMachine)]
    fun test_spin_slots_bet_too_low() {
        let (framework, _, _) = setup_basic_test();

        let player = create_funded_player(&framework, @0x123, MIN_BET);

        // This will fail at bet amount validation
        SlotMachine::test_only_spin_slots(&player, MIN_BET - 1);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT, location = slot_game::SlotMachine)]
    fun test_spin_slots_bet_too_high() {
        let (framework, _, _) = setup_basic_test();

        let player = create_funded_player(&framework, @0x123, MAX_BET * 2);

        // This will fail at bet amount validation
        SlotMachine::test_only_spin_slots(&player, MAX_BET + 1);
    }

    //
    // Boundary Value Tests
    //

    #[test]
    fun test_payout_calculation_edge_cases() {
        // Test boundary values for payout calculation
        assert!(
            SlotMachine::calculate_symbol_payout(MIN_BET, SYMBOL_CHERRY) == MIN_BET * 5,
            1
        );
        assert!(
            SlotMachine::calculate_symbol_payout(MAX_BET, SYMBOL_SEVEN) == MAX_BET
                * 500,
            2
        );

        // Test mid-range values
        let mid_bet = (MIN_BET + MAX_BET) / 2;
        assert!(
            SlotMachine::calculate_symbol_payout(mid_bet, SYMBOL_COIN) == mid_bet * 25,
            3
        );

        // Test specific values
        assert!(
            SlotMachine::calculate_symbol_payout(10000000, SYMBOL_BELL) == 100000000, // 0.1 APT -> 1 APT
            4
        );
    }

    #[test]
    fun test_config_constants_consistency() {
        let (min_bet, max_bet, house_edge) = SlotMachine::get_game_config();

        // Verify constants match expected values
        assert!(min_bet < max_bet, 1);
        assert!(house_edge == 1550, 2); // 15.5% house edge

        // Verify min bet is reasonable (0.01 APT)
        assert!(min_bet == 1000000, 3);

        // Verify max bet is reasonable (0.5 APT)
        assert!(max_bet == 50000000, 4);
    }

    #[test]
    fun test_mathematical_house_edge() {
        // Verify the mathematical house edge calculation
        // Expected return calculation based on symbol weights and payouts
        let (cherry_w, _, _, _, seven_w) =
            SlotMachine::get_symbol_weights();
        let (cherry_p, bell_p, coin_p, chain_p, seven_p) =
            SlotMachine::get_payout_multipliers();

        // Calculate probability of winning each symbol (weight/100)^3
        // Cherry: (40/100)^3 = 0.064 = 6.4%
        // Bell: (30/100)^3 = 0.027 = 2.7%
        // Coin: (20/100)^3 = 0.008 = 0.8%
        // Chain: (8/100)^3 = 0.000512 = 0.0512%
        // Seven: (2/100)^3 = 0.000008 = 0.0008%

        // Verify payouts are inversely related to probability
        assert!(cherry_p < bell_p, 1); // Most common should have lowest payout
        assert!(bell_p < coin_p, 2);
        assert!(coin_p < chain_p, 3);
        assert!(chain_p < seven_p, 4); // Rarest should have highest payout

        // Verify weights are reasonable for slot machine
        assert!(cherry_w >= 30, 5); // Cherry should be common
        assert!(seven_w <= 5, 6); // Seven should be very rare
    }

    #[test]
    fun test_symbol_weight_distribution() {
        // Test that symbols have proper relative weights
        let (cherry, bell, coin, chain, seven) = SlotMachine::get_symbol_weights();

        // Cherry should be most common
        assert!(cherry > bell, 1);
        assert!(cherry > coin, 2);
        assert!(cherry > chain, 3);
        assert!(cherry > seven, 4);

        // Seven should be rarest
        assert!(seven < cherry, 5);
        assert!(seven < bell, 6);
        assert!(seven < coin, 7);
        assert!(seven < chain, 8);

        // Verify reasonable distribution
        assert!(cherry >= 30, 9); // At least 30% for common symbol
        assert!(seven <= 10, 10); // At most 10% for rare symbol
    }

    #[test]
    fun test_payout_multiplier_progression() {
        let (cherry, bell, coin, chain, seven) = SlotMachine::get_payout_multipliers();

        // Verify ascending payout order (rarer = higher payout)
        assert!(cherry < bell, 1);
        assert!(bell < coin, 2);
        assert!(coin < chain, 3);
        assert!(chain < seven, 4);

        // Verify reasonable payout ranges
        assert!(cherry >= 2, 5); // At least 2x for lowest
        assert!(seven <= 1000, 6); // At most 1000x for highest

        // Verify specific expected values
        assert!(cherry == 5, 7);
        assert!(seven == 500, 8);
    }

    #[test]
    fun test_state_before_registration() {
        let (_, _, _) = setup_with_casino();

        // Test the game state when casino hasn't registered it yet
        assert!(!SlotMachine::is_registered(), 1);
        assert!(!SlotMachine::is_initialized(), 2);
        assert!(!SlotMachine::is_ready(), 3);

        // View functions should still work
        let (min_bet, max_bet, house_edge) = SlotMachine::get_game_config();
        assert!(min_bet > 0, 4);
        assert!(max_bet > min_bet, 5);
        assert!(house_edge > 0, 6);
    }

    #[test]
    fun test_comprehensive_symbol_calculations() {
        // Test all symbols with various bet amounts
        let test_amounts = vector[
            1000000, // Min bet (0.01 APT)
            10000000, // 0.1 APT
            25000000, // 0.25 APT
            50000000 // Max bet (0.5 APT)
        ];

        let symbols = vector[
            SYMBOL_CHERRY,
            SYMBOL_BELL,
            SYMBOL_COIN,
            SYMBOL_CHAIN,
            SYMBOL_SEVEN
        ];

        let expected_multipliers = vector[5, 10, 25, 100, 500];

        let i = 0;
        while (i < vector::length(&test_amounts)) {
            let amount = *vector::borrow(&test_amounts, i);

            let j = 0;
            while (j < vector::length(&symbols)) {
                let symbol = *vector::borrow(&symbols, j);
                let multiplier = *vector::borrow(&expected_multipliers, j);
                let expected_payout = amount * multiplier;

                assert!(
                    SlotMachine::calculate_symbol_payout(amount, symbol)
                        == expected_payout,
                    (i * 10) + j
                );

                j = j + 1;
            };

            i = i + 1;
        };
    }
}
