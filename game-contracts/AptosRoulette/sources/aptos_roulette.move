//! MIT License
//!
//! AptosRoulette Game Module
//!
//! European roulette with comprehensive betting options.

module roulette_game::AptosRoulette {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::randomness;
    use aptos_framework::event;
    use casino::CasinoHouse::{Self, GameCapability};

    //
    // Error Codes
    //

    /// Game not initialized
    const E_NOT_INITIALIZED: u64 = 0;
    /// Already initialized
    const E_ALREADY_INITIALIZED: u64 = 1;
    /// Unauthorized access
    const E_UNAUTHORIZED: u64 = 2;
    /// Game not registered with casino
    const E_GAME_NOT_REGISTERED: u64 = 3;
    /// Invalid bet amount
    const E_INVALID_AMOUNT: u64 = 4;
    /// Invalid roulette number (must be 0-36)
    const E_INVALID_NUMBER: u64 = 5;
    /// Invalid bet type
    const E_INVALID_BET_TYPE: u64 = 6;
    /// Invalid dozen (must be 1-3)
    const E_INVALID_DOZEN: u64 = 7;
    /// Invalid column (must be 1-3)
    const E_INVALID_COLUMN: u64 = 8;
    /// Mismatched bet arrays
    const E_MISMATCHED_BET_ARRAYS: u64 = 9;
    /// Too many bets in single transaction
    const E_TOO_MANY_BETS: u64 = 10;
    /// Invalid split bet
    const E_INVALID_SPLIT: u64 = 11;
    /// Invalid street bet
    const E_INVALID_STREET: u64 = 12;
    /// Invalid corner bet
    const E_INVALID_CORNER: u64 = 13;
    /// Invalid line bet
    const E_INVALID_LINE: u64 = 14;

    //
    // Constants
    //

    /// Game version
    const GAME_VERSION: vector<u8> = b"v2";
    /// Minimum bet amount (0.01 APT)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.1 APT)
    const MAX_BET: u64 = 10000000;
    /// Maximum bets per transaction
    const MAX_BETS_PER_TRANSACTION: u64 = 10;

    // Entry function bet type flags
    const ENTRY_STRAIGHT_UP: u8 = 0;
    const ENTRY_SPLIT: u8 = 1;
    const ENTRY_STREET: u8 = 2;
    const ENTRY_CORNER: u8 = 3;
    const ENTRY_RED_BLACK: u8 = 4;
    const ENTRY_EVEN_ODD: u8 = 5;
    const ENTRY_HIGH_LOW: u8 = 6;
    const ENTRY_DOZEN: u8 = 7;
    const ENTRY_COLUMN: u8 = 8;
    const ENTRY_LINE: u8 = 9;

    //
    // Move 2 Enum System
    //

    /// Comprehensive bet type enum with embedded validation data
    enum BetType has copy, drop, store {
        /// Single number bet (0-36) - Pays 35:1
        StraightUp {
            number: u8
        },
        /// Two adjacent numbers - Pays 17:1
        Split {
            num1: u8,
            num2: u8
        },
        /// Three numbers in a row - Pays 11:1
        Street {
            row: u8
        },
        /// Four numbers in a square - Pays 8:1
        Corner {
            top_left: u8
        },
        /// Red or black color bet - Pays 1:1
        RedBlack {
            is_red: bool
        },
        /// Even or odd number bet - Pays 1:1
        EvenOdd {
            is_even: bool
        },
        /// High (19-36) or low (1-18) bet - Pays 1:1
        HighLow {
            is_high: bool
        },
        /// Dozen bet (1-12, 13-24, 25-36) - Pays 2:1
        Dozen {
            dozen: u8
        },
        /// Column bet (1, 2, or 3) - Pays 2:1
        Column {
            column: u8
        },
        /// Six numbers across two rows - Pays 5:1
        Line {
            start_row: u8
        }
    }

    /// Betting result with comprehensive information
    struct BetResult has copy, drop, store {
        won: bool,
        payout: u64,
        description: String,
        winning_numbers: vector<u8>
    }

    /// Session ID for tracking game sessions
    struct SessionId has copy, drop, store {
        player: address,
        sequence: u64
    }

    /// Individual bet information
    struct BetInfo has copy, drop, store {
        bet_type: BetType,
        amount: u64,
        result: BetResult
    }

    /// Complete spin result
    struct SpinResult has key {
        winning_number: u8,
        winning_color: String,
        is_even: bool,
        is_high: bool,
        dozen: u8,
        column: u8,
        all_bets: vector<BetInfo>,
        total_wagered: u64,
        total_payout: u64,
        winning_bets: u8,
        session_id: SessionId,
        net_result: bool
    }

    /// Game registry and authentication
    struct GameRegistry has key {
        creator: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    /// Game authentication capability
    struct GameAuth has key {
        capability: GameCapability,
        extend_ref: ExtendRef
    }

    //
    // Events
    //

    #[event]
    /// Emitted for individual bet within a spin
    struct BetPlacedEvent has drop, store {
        player: address,
        bet_description: String,
        amount: u64,
        payout: u64,
        won: bool,
        sequence: u64
    }

    #[event]
    /// Emitted for complete roulette spin
    struct RouletteSpinEvent has drop, store {
        player: address,
        winning_number: u8,
        winning_color: String,
        total_wagered: u64,
        total_payout: u64,
        winning_bets: u8,
        total_bets: u8,
        treasury_used: address,
        sequence: u64
    }

    //
    // Enum Construction & Validation
    //

    /// Create and validate StraightUp bet
    public fun create_straight_up_bet(number: u8): BetType {
        assert!(number <= 36, E_INVALID_NUMBER);
        BetType::StraightUp { number }
    }

    /// Create and validate Split bet
    public fun create_split_bet(num1: u8, num2: u8): BetType {
        assert!(num1 <= 36 && num2 <= 36, E_INVALID_NUMBER);
        assert!(is_valid_split(num1, num2), E_INVALID_SPLIT);
        BetType::Split { num1, num2 }
    }

    /// Create and validate Street bet
    public fun create_street_bet(row: u8): BetType {
        assert!(row >= 1 && row <= 12, E_INVALID_STREET);
        BetType::Street { row }
    }

    /// Create and validate Corner bet
    public fun create_corner_bet(top_left: u8): BetType {
        assert!(is_valid_corner(top_left), E_INVALID_CORNER);
        BetType::Corner { top_left }
    }

    /// Create RedBlack bet
    public fun create_red_black_bet(is_red: bool): BetType {
        BetType::RedBlack { is_red }
    }

    /// Create EvenOdd bet
    public fun create_even_odd_bet(is_even: bool): BetType {
        BetType::EvenOdd { is_even }
    }

    /// Create HighLow bet
    public fun create_high_low_bet(is_high: bool): BetType {
        BetType::HighLow { is_high }
    }

    /// Create and validate Dozen bet
    public fun create_dozen_bet(dozen: u8): BetType {
        assert!(dozen >= 1 && dozen <= 3, E_INVALID_DOZEN);
        BetType::Dozen { dozen }
    }

    /// Create and validate Column bet
    public fun create_column_bet(column: u8): BetType {
        assert!(column >= 1 && column <= 3, E_INVALID_COLUMN);
        BetType::Column { column }
    }

    /// Create and validate Line bet
    public fun create_line_bet(start_row: u8): BetType {
        assert!(start_row >= 1 && start_row <= 11, E_INVALID_LINE);
        BetType::Line { start_row }
    }

    /// Convert entry function parameters to validated BetType enum
    fun decode_bet_type(
        bet_flag: u8, bet_value: u8, bet_numbers: vector<u8>
    ): BetType {
        if (bet_flag == ENTRY_STRAIGHT_UP) {
            create_straight_up_bet(bet_value)
        } else if (bet_flag == ENTRY_SPLIT) {
            assert!(vector::length(&bet_numbers) == 2, E_INVALID_SPLIT);
            let num1 = *vector::borrow(&bet_numbers, 0);
            let num2 = *vector::borrow(&bet_numbers, 1);
            create_split_bet(num1, num2)
        } else if (bet_flag == ENTRY_STREET) {
            create_street_bet(bet_value)
        } else if (bet_flag == ENTRY_CORNER) {
            create_corner_bet(bet_value)
        } else if (bet_flag == ENTRY_RED_BLACK) {
            create_red_black_bet(bet_value == 1)
        } else if (bet_flag == ENTRY_EVEN_ODD) {
            create_even_odd_bet(bet_value == 1)
        } else if (bet_flag == ENTRY_HIGH_LOW) {
            create_high_low_bet(bet_value == 1)
        } else if (bet_flag == ENTRY_DOZEN) {
            create_dozen_bet(bet_value)
        } else if (bet_flag == ENTRY_COLUMN) {
            create_column_bet(bet_value)
        } else if (bet_flag == ENTRY_LINE) {
            create_line_bet(bet_value)
        } else {
            abort E_INVALID_BET_TYPE
        }
    }

    //
    // Pattern Matching Logic (Clean & Comprehensive)
    //

    /// Calculate bet result using comprehensive pattern matching
    fun calculate_bet_result(
        bet_type: BetType, winning_number: u8, amount: u64
    ): BetResult {
        match(bet_type) {
            BetType::StraightUp { number } => {
                if (number == winning_number) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 35),
                        description: string::utf8(b"Straight Up Win"),
                        winning_numbers: vector[number]
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Straight Up Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Split { num1, num2 } => {
                if (winning_number == num1 || winning_number == num2) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 17),
                        description: string::utf8(b"Split Win"),
                        winning_numbers: vector[num1, num2]
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Split Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Street { row } => {
                let street_numbers = get_street_numbers(row);
                let won = vector::contains(&street_numbers, &winning_number);
                if (won) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 11),
                        description: string::utf8(b"Street Win"),
                        winning_numbers: street_numbers
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Street Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Corner { top_left } => {
                let corner_numbers = get_corner_numbers(top_left);
                let won = vector::contains(&corner_numbers, &winning_number);
                if (won) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 8),
                        description: string::utf8(b"Corner Win"),
                        winning_numbers: corner_numbers
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Corner Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::RedBlack { is_red } => {
                let is_winning_red = is_red_number(winning_number);
                if (winning_number != 0 && is_red == is_winning_red) {
                    BetResult {
                        won: true,
                        payout: amount + amount,
                        description: if (is_red) { string::utf8(b"Red Win") }
                        else { string::utf8(b"Black Win") },
                        winning_numbers: get_color_numbers(is_red)
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Color Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::EvenOdd { is_even } => {
                let is_winning_even = (winning_number != 0 && winning_number % 2 == 0);
                if (winning_number != 0 && is_even == is_winning_even) {
                    BetResult {
                        won: true,
                        payout: amount + amount,
                        description: if (is_even) { string::utf8(b"Even Win") }
                        else { string::utf8(b"Odd Win") },
                        winning_numbers: get_even_odd_numbers(is_even)
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Even/Odd Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::HighLow { is_high } => {
                let is_winning_high = (winning_number >= 19 && winning_number <= 36);
                let is_winning_low = (winning_number >= 1 && winning_number <= 18);
                if ((is_high && is_winning_high) || (!is_high && is_winning_low)) {
                    BetResult {
                        won: true,
                        payout: amount + amount,
                        description: if (is_high) { string::utf8(b"High Win") }
                        else { string::utf8(b"Low Win") },
                        winning_numbers: get_high_low_numbers(is_high)
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"High/Low Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Dozen { dozen } => {
                let winning_dozen = get_dozen_for_number(winning_number);
                if (dozen == winning_dozen && winning_dozen != 0) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 2),
                        description: string::utf8(b"Dozen Win"),
                        winning_numbers: get_dozen_numbers(dozen)
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Dozen Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Column { column } => {
                let winning_column = get_column_for_number(winning_number);
                if (column == winning_column && winning_column != 0) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 2),
                        description: string::utf8(b"Column Win"),
                        winning_numbers: get_column_numbers(column)
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Column Loss"),
                        winning_numbers: vector[]
                    }
                }
            },
            BetType::Line { start_row } => {
                let line_numbers = get_line_numbers(start_row);
                let won = vector::contains(&line_numbers, &winning_number);
                if (won) {
                    BetResult {
                        won: true,
                        payout: amount + (amount * 5),
                        description: string::utf8(b"Line Win"),
                        winning_numbers: line_numbers
                    }
                } else {
                    BetResult {
                        won: false,
                        payout: 0,
                        description: string::utf8(b"Line Loss"),
                        winning_numbers: vector[]
                    }
                }
            }
        }
    }

    //
    // Entry Functions - Modern Clean Interface
    //

    #[randomness]
    /// Primary betting entry point with enum-powered validation
    entry fun place_bet(
        player: &signer,
        bet_flag: u8,
        bet_value: u8,
        bet_numbers: vector<u8>,
        amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        // Decode to validated enum
        let bet_type = decode_bet_type(bet_flag, bet_value, bet_numbers);

        // Execute single bet
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// Multiple bets in single transaction
    entry fun place_multi_bet(
        player: &signer,
        bet_flags: vector<u8>,
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult, GameRegistry {
        let num_bets = vector::length(&bet_flags);
        assert!(
            num_bets > 0 && num_bets <= MAX_BETS_PER_TRANSACTION,
            E_TOO_MANY_BETS
        );
        assert!(vector::length(&bet_values) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&bet_numbers_list) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&amounts) == num_bets, E_MISMATCHED_BET_ARRAYS);

        // Convert all to enums
        let bet_types = vector::empty<BetType>();
        let i = 0;
        while (i < num_bets) {
            let bet_flag = *vector::borrow(&bet_flags, i);
            let bet_value = *vector::borrow(&bet_values, i);
            let bet_numbers = *vector::borrow(&bet_numbers_list, i);
            let bet_type = decode_bet_type(bet_flag, bet_value, bet_numbers);
            vector::push_back(&mut bet_types, bet_type);
            i = i + 1;
        };

        execute_multi_bet_internal(player, bet_types, amounts);
    }

    //
    // Convenience Entry Functions (Type-Safe)
    //

    #[randomness]
    /// Straight up number bet
    entry fun bet_number(
        player: &signer, number: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_straight_up_bet(number);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// Red or black color bet
    entry fun bet_red_black(
        player: &signer, is_red: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_red_black_bet(is_red);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// Even or odd bet
    entry fun bet_even_odd(
        player: &signer, is_even: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_even_odd_bet(is_even);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// High or low bet
    entry fun bet_high_low(
        player: &signer, is_high: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_high_low_bet(is_high);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// Dozen bet
    entry fun bet_dozen(
        player: &signer, dozen: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_dozen_bet(dozen);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    #[randomness]
    /// Column bet
    entry fun bet_column(
        player: &signer, column: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_type = create_column_bet(column);
        let bets = vector[bet_type];
        let amounts = vector[amount];
        execute_multi_bet_internal(player, bets, amounts);
    }

    //
    // Core Logic - Enum-Powered Execution
    //

    /// Internal multi-bet execution using enum system
    fun execute_multi_bet_internal(
        player: &signer, bet_types: vector<BetType>, amounts: vector<u64>
    ) acquires GameAuth, SpinResult, GameRegistry {
        let num_bets = vector::length(&bet_types);
        assert!(num_bets == vector::length(&amounts), E_MISMATCHED_BET_ARRAYS);

        // Validate all amounts and calculate total
        let total_amount = 0u64;
        let i = 0;
        while (i < num_bets) {
            let amount = *vector::borrow(&amounts, i);
            assert!(
                amount >= MIN_BET && amount <= MAX_BET,
                E_INVALID_AMOUNT
            );
            total_amount = total_amount + amount;
            i = i + 1;
        };

        let player_addr = signer::address_of(player);

        // Auto-cleanup previous result
        if (exists<SpinResult>(player_addr)) {
            let old_result = move_from<SpinResult>(player_addr);
            let SpinResult {
                winning_number: _,
                winning_color: _,
                is_even: _,
                is_high: _,
                dozen: _,
                column: _,
                all_bets: _,
                total_wagered: _,
                total_payout: _,
                winning_bets: _,
                session_id: _,
                net_result: _
            } = old_result;
        };

        // Get fungible asset metadata and withdraw bet amount
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(
            player, aptos_metadata, total_amount
        );

        // Get game capability and place bet with casino
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;
        let (treasury_source, bet_id) =
            CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Spin the roulette wheel with secure randomness
        let winning_number = randomness::u8_range(0, 37); // 0-36

        // Calculate all bet results using pattern matching
        let bet_infos = vector::empty<BetInfo>();
        let total_payout = 0u64;
        let winning_bets = 0u8;

        i = 0;
        while (i < num_bets) {
            let bet_type = *vector::borrow(&bet_types, i);
            let amount = *vector::borrow(&amounts, i);
            let bet_result = calculate_bet_result(bet_type, winning_number, amount);

            if (bet_result.won) {
                total_payout = total_payout + bet_result.payout;
                winning_bets = winning_bets + 1;
            };

            let bet_info = BetInfo { bet_type, amount, result: bet_result };
            vector::push_back(&mut bet_infos, bet_info);

            // Emit individual bet event
            event::emit(
                BetPlacedEvent {
                    player: player_addr,
                    bet_description: bet_result.description,
                    amount,
                    payout: bet_result.payout,
                    won: bet_result.won,
                    sequence: account::get_sequence_number(player_addr)
                }
            );

            i = i + 1;
        };

        // Determine winning properties
        let winning_color =
            if (winning_number == 0) {
                string::utf8(b"green")
            } else if (is_red_number(winning_number)) {
                string::utf8(b"red")
            } else {
                string::utf8(b"black")
            };

        let is_even_win = winning_number != 0 && winning_number % 2 == 0;
        let is_high_win = winning_number >= 19 && winning_number <= 36;
        let dozen_win = get_dozen_for_number(winning_number);
        let column_win = get_column_for_number(winning_number);

        // Process casino payout
        if (total_payout > 0) {
            CasinoHouse::settle_bet(
                capability,
                bet_id,
                player_addr,
                total_payout,
                treasury_source
            );
        } else {
            CasinoHouse::settle_bet(
                capability,
                bet_id,
                player_addr,
                0,
                treasury_source
            );
        };

        // Generate session ID
        let session_id = SessionId {
            player: player_addr,
            sequence: account::get_sequence_number(player_addr)
        };

        // Store comprehensive result
        let spin_result = SpinResult {
            winning_number,
            winning_color,
            is_even: is_even_win,
            is_high: is_high_win,
            dozen: dozen_win,
            column: column_win,
            all_bets: bet_infos,
            total_wagered: total_amount,
            total_payout,
            winning_bets,
            session_id,
            net_result: total_payout > total_amount
        };

        move_to(player, spin_result);

        // Emit complete spin event
        event::emit(
            RouletteSpinEvent {
                player: player_addr,
                winning_number,
                winning_color,
                total_wagered: total_amount,
                total_payout,
                winning_bets,
                total_bets: (num_bets as u8),
                treasury_used: treasury_source,
                sequence: account::get_sequence_number(player_addr)
            }
        );
    }

    //
    // Helper Functions - Number Classification
    //

    /// Check if number is red
    fun is_red_number(num: u8): bool {
        if (num == 0) { false }
        else if (num <= 10) {
            num % 2 == 1
        } else if (num <= 18) {
            num % 2 == 0
        } else if (num <= 28) {
            num % 2 == 1
        } else {
            num % 2 == 0
        }
    }

    /// Get dozen for number (1-3, 0 for zero)
    fun get_dozen_for_number(num: u8): u8 {
        if (num == 0) { 0 }
        else if (num <= 12) { 1 }
        else if (num <= 24) { 2 }
        else { 3 }
    }

    /// Get column for number (1-3, 0 for zero)
    fun get_column_for_number(num: u8): u8 {
        if (num == 0) { 0 }
        else {
            ((num - 1) % 3) + 1
        }
    }

    /// Validate split bet (adjacent numbers)
    fun is_valid_split(num1: u8, num2: u8): bool {
        if (num1 > 36 || num2 > 36) {
            return false
        };
        if (num1 == num2) {
            return false
        };

        // 0 can split with 1, 2, 3
        if (num1 == 0) {
            return num2 == 1 || num2 == 2 || num2 == 3
        };
        if (num2 == 0) {
            return num1 == 1 || num1 == 2 || num1 == 3
        };

        let diff = if (num1 > num2) {
            num1 - num2
        } else {
            num2 - num1
        };

        // Horizontal split (adjacent in same row)
        if (diff == 1) {
            let row1 = (num1 - 1) / 3;
            let row2 = (num2 - 1) / 3;
            return row1 == row2;
        };

        // Vertical split (adjacent in same column)
        diff == 3
    }

    /// Validate corner bet
    fun is_valid_corner(top_left: u8): bool {
        if (top_left == 0 || top_left > 32) {
            return false
        };

        let row = (top_left - 1) / 3;
        let col = (top_left - 1) % 3;

        // Can't place corner on rightmost column
        col < 2 && row < 11
    }

    //
    // Number Group Generators
    //

    /// Get numbers in a street (row of 3)
    fun get_street_numbers(row: u8): vector<u8> {
        let base = (row - 1) * 3 + 1;
        vector[base, base + 1, base + 2]
    }

    /// Get numbers in a corner (2x2 square)
    fun get_corner_numbers(top_left: u8): vector<u8> {
        vector[top_left, top_left + 1, top_left + 3, top_left + 4]
    }

    /// Get all red or black numbers
    fun get_color_numbers(is_red: bool): vector<u8> {
        let numbers = vector::empty<u8>();
        let i = 1u8;
        while (i <= 36) {
            if (is_red_number(i) == is_red) {
                vector::push_back(&mut numbers, i);
            };
            i = i + 1;
        };
        numbers
    }

    /// Get all even or odd numbers
    fun get_even_odd_numbers(is_even: bool): vector<u8> {
        let numbers = vector::empty<u8>();
        let i = 1u8;
        while (i <= 36) {
            if ((i % 2 == 0) == is_even) {
                vector::push_back(&mut numbers, i);
            };
            i = i + 1;
        };
        numbers
    }

    /// Get all high or low numbers
    fun get_high_low_numbers(is_high: bool): vector<u8> {
        if (is_high) {
            // High: 19-36
            let numbers = vector::empty<u8>();
            let i = 19u8;
            while (i <= 36) {
                vector::push_back(&mut numbers, i);
                i = i + 1;
            };
            numbers
        } else {
            // Low: 1-18
            let numbers = vector::empty<u8>();
            let i = 1u8;
            while (i <= 18) {
                vector::push_back(&mut numbers, i);
                i = i + 1;
            };
            numbers
        }
    }

    /// Get all numbers in a dozen
    fun get_dozen_numbers(dozen: u8): vector<u8> {
        let start = (dozen - 1) * 12 + 1;
        let end = dozen * 12;
        let numbers = vector::empty<u8>();
        let i = start;
        while (i <= end) {
            vector::push_back(&mut numbers, i);
            i = i + 1;
        };
        numbers
    }

    /// Get all numbers in a column
    fun get_column_numbers(column: u8): vector<u8> {
        let numbers = vector::empty<u8>();
        let i = column;
        while (i <= 36) {
            vector::push_back(&mut numbers, i);
            i = i + 3;
        };
        numbers
    }

    /// Get numbers in a line (two adjacent rows)
    fun get_line_numbers(start_row: u8): vector<u8> {
        let street1 = get_street_numbers(start_row);
        let street2 = get_street_numbers(start_row + 1);
        vector::append(&mut street1, street2);
        street1
    }

    //
    // Initialization Functions
    //

    /// Initialize roulette game with casino registration
    public entry fun initialize_game(deployer: &signer) {
        let deployer_addr = signer::address_of(deployer);
        assert!(deployer_addr == @roulette_game, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(deployer_addr), E_ALREADY_INITIALIZED);

        // Get game object from casino registration
        let game_name = string::utf8(b"AptosRoulette");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr =
            CasinoHouse::derive_game_object_address(@casino, game_name, version);
        let game_object: Object<CasinoHouse::GameMetadata> =
            object::address_to_object(game_object_addr);

        assert!(CasinoHouse::is_game_registered(game_object), E_GAME_NOT_REGISTERED);

        // Create named object for game instance
        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(deployer, seed);
        let game_signer = object::generate_signer(&constructor_ref);

        // Configure as non-transferable
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        // Generate extend ref for future operations
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Get capability from casino using game object
        let capability = CasinoHouse::get_game_capability(deployer, game_object);

        // Store GameAuth in the object with extend_ref
        move_to(&game_signer, GameAuth { capability, extend_ref });

        // Store complete registry info at module address (like SevenOut)
        move_to(
            deployer,
            GameRegistry {
                creator: signer::address_of(deployer),
                game_object,
                game_name,
                version
            }
        );
    }

    /// Get game object address
    fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let seed = build_seed(registry.game_name, registry.version);
        object::create_object_address(&registry.creator, seed)
    }

    /// Build Seed
    fun build_seed(name: String, version: String): vector<u8> {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"game_metadata_");
        vector::append(&mut seed, *string::bytes(&name));
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *string::bytes(&version));
        seed
    }

    //
    // View Functions
    //

    #[view]
    /// Get latest spin result for player
    public fun get_latest_result(
        player_addr: address
    ): (u8, String, bool, bool, u8, u8, u64, u64, u8, bool) acquires SpinResult {
        assert!(exists<SpinResult>(player_addr), E_NOT_INITIALIZED);
        let result = borrow_global<SpinResult>(player_addr);
        (
            result.winning_number,
            result.winning_color,
            result.is_even,
            result.is_high,
            result.dozen,
            result.column,
            result.total_wagered,
            result.total_payout,
            result.winning_bets,
            result.net_result
        )
    }

    #[view]
    /// Check if number is red
    public fun is_red(num: u8): bool {
        is_red_number(num)
    }

    #[view]
    /// Check if number is black
    public fun is_black(num: u8): bool {
        num != 0 && !is_red_number(num)
    }

    #[view]
    /// Check if number is even (excluding 0)
    public fun is_even(num: u8): bool {
        num != 0 && num % 2 == 0
    }

    #[view]
    /// Check if number is odd
    public fun is_odd(num: u8): bool {
        num != 0 && num % 2 == 1
    }

    #[view]
    /// Get dozen for number
    public fun get_dozen(num: u8): u8 {
        get_dozen_for_number(num)
    }

    #[view]
    /// Get column for number
    public fun get_column(num: u8): u8 {
        get_column_for_number(num)
    }

    #[view]
    /// Get color as string
    public fun get_color_string(num: u8): String {
        if (num == 0) {
            string::utf8(b"green")
        } else if (is_red_number(num)) {
            string::utf8(b"red")
        } else {
            string::utf8(b"black")
        }
    }

    #[view]
    /// Get payout table
    public fun get_payout_table(): (u8, u8, u8, u8, u8, u8, u8) {
        (35, 1, 2, 17, 11, 8, 5) // single, even_money, dozen_column, split, street, corner, line
    }

    #[view]
    /// Check if game is initialized
    public fun is_initialized(): bool {
        exists<GameRegistry>(@roulette_game)
    }

    #[view]
    /// Check if game is registered with casino
    public fun is_registered(): bool acquires GameRegistry {
        if (!exists<GameRegistry>(@roulette_game)) { false }
        else {
            let registry = borrow_global<GameRegistry>(@roulette_game);
            CasinoHouse::is_game_registered(registry.game_object)
        }
    }

    #[view]
    /// Check if game is ready to play
    public fun is_ready(): bool acquires GameRegistry {
        is_registered() && is_initialized()
    }

    #[view]
    /// Check if game object exists
    public fun object_exists(): bool acquires GameRegistry {
        if (!is_initialized()) { false }
        else {
            let object_addr = get_game_object_address();
            exists<GameAuth>(object_addr)
        }
    }

    /// Clear game result (for testing)
    public entry fun clear_game_result(player: &signer) acquires SpinResult {
        let player_addr = signer::address_of(player);
        if (exists<SpinResult>(player_addr)) {
            let old_result = move_from<SpinResult>(player_addr);
            let SpinResult {
                winning_number: _,
                winning_color: _,
                is_even: _,
                is_high: _,
                dozen: _,
                column: _,
                all_bets: _,
                total_wagered: _,
                total_payout: _,
                winning_bets: _,
                session_id: _,
                net_result: _
            } = old_result;
        };
    }

    //
    // Test-only Functions
    //

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_number(
        player: &signer, number: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_number(player, number, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_red_black(
        player: &signer, is_red: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_red_black(player, is_red, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_place_bet(
        player: &signer,
        bet_flag: u8,
        bet_value: u8,
        bet_numbers: vector<u8>,
        amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        place_bet(
            player,
            bet_flag,
            bet_value,
            bet_numbers,
            amount
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_place_multi_bet(
        player: &signer,
        bet_flags: vector<u8>,
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult, GameRegistry {
        place_multi_bet(
            player,
            bet_flags,
            bet_values,
            bet_numbers_list,
            amounts
        );
    }
}
