//! MIT License
//!
//! European Roulette Game for ChainCasino Platform
//!
//! Complete European roulette with all standard bet types using
//! multi-bet support, and advanced betting functionality.

module roulette_game::AptosRoulette {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::timestamp;
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;
    use aptos_framework::account;

    //
    // Error Codes
    //

    /// Invalid number (must be 0-36 for European roulette)
    const E_INVALID_NUMBER: u64 = 0x01;
    /// Invalid bet amount
    const E_INVALID_AMOUNT: u64 = 0x02;
    /// Unauthorized initialization
    const E_UNAUTHORIZED: u64 = 0x03;
    /// Game not registered by casino yet
    const E_GAME_NOT_REGISTERED: u64 = 0x04;
    /// Game already initialized
    const E_ALREADY_INITIALIZED: u64 = 0x05;
    /// Invalid bet type
    const E_INVALID_BET_TYPE: u64 = 0x06;
    /// Invalid dozen (must be 1, 2, or 3)
    const E_INVALID_DOZEN: u64 = 0x07;
    /// Invalid column (must be 1, 2, or 3)
    const E_INVALID_COLUMN: u64 = 0x08;
    /// Mismatched bet arrays length
    const E_MISMATCHED_BET_ARRAYS: u64 = 0x09;
    /// Too many bets in single transaction
    const E_TOO_MANY_BETS: u64 = 0x0A;
    /// Invalid split bet combination
    const E_INVALID_SPLIT: u64 = 0x0B;
    /// Invalid street bet
    const E_INVALID_STREET: u64 = 0x0C;
    /// Invalid corner bet
    const E_INVALID_CORNER: u64 = 0x0D;
    /// Invalid line bet
    const E_INVALID_LINE: u64 = 0x0E;

    //
    // Constants
    //

    /// European roulette numbers (0-36)
    const MAX_ROULETTE_NUMBER: u8 = 36;
    /// Maximum bets per transaction
    const MAX_BETS_PER_TRANSACTION: u64 = 10;
    
    // Payout Multipliers
    /// Single number payout multiplier (35:1)
    const SINGLE_NUMBER_PAYOUT: u64 = 35;
    /// Red/Black, Even/Odd, High/Low payout (1:1)
    const EVEN_MONEY_PAYOUT: u64 = 1;
    /// Dozens and Columns payout (2:1)
    const DOZEN_COLUMN_PAYOUT: u64 = 2;
    /// Split bet payout (17:1)
    const SPLIT_PAYOUT: u64 = 17;
    /// Street bet payout (11:1)
    const STREET_PAYOUT: u64 = 11;
    /// Corner bet payout (8:1)
    const CORNER_PAYOUT: u64 = 8;
    /// Line bet payout (5:1)
    const LINE_PAYOUT: u64 = 5;

    /// Minimum bet amount (0.01 APT in octas)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.3 APT in octas) - conservative for 35:1 payout
    const MAX_BET: u64 = 30000000;
    /// House edge in basis points (270 = 2.70% for European roulette)
    const HOUSE_EDGE_BPS: u64 = 270;
    /// Game version for object naming
    const GAME_VERSION: vector<u8> = b"v1";

    // Red Numbers in European Roulette
    /// Red numbers: 1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36
    const RED_NUMBERS: vector<u8> = vector[
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
    ];

    //
    // Enums (Type-Safe Bet Types)
    //

    /// All possible bet types in European roulette
    public enum BetType has copy, drop, store {
        /// Single number bet (0-36), 35:1 payout
        SingleNumber { number: u8 },
        /// Bet on red numbers, 1:1 payout
        Red,
        /// Bet on black numbers, 1:1 payout
        Black,
        /// Bet on even numbers, 1:1 payout
        Even,
        /// Bet on odd numbers, 1:1 payout
        Odd,
        /// Bet on high numbers (19-36), 1:1 payout
        High,
        /// Bet on low numbers (1-18), 1:1 payout
        Low,
        /// Bet on first dozen (1-12), 2:1 payout
        FirstDozen,
        /// Bet on second dozen (13-24), 2:1 payout
        SecondDozen,
        /// Bet on third dozen (25-36), 2:1 payout
        ThirdDozen,
        /// Bet on first column, 2:1 payout
        FirstColumn,
        /// Bet on second column, 2:1 payout
        SecondColumn,
        /// Bet on third column, 2:1 payout
        ThirdColumn,
        /// Split bet on two adjacent numbers, 17:1 payout
        Split { num1: u8, num2: u8 },
        /// Street bet on three numbers in a row, 11:1 payout
        Street { start_num: u8 },
        /// Corner bet on four numbers in a square, 8:1 payout
        Corner { top_left: u8 },
        /// Line bet on six numbers in two rows, 5:1 payout
        Line { start_num: u8 }
    }

    //
    // Resources
    //

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Stores the game's authorization capability in named object
    struct GameAuth has key {
        capability: GameCapability,
        extend_ref: ExtendRef
    }

    /// Registry tracking the creator and object address for this game
    struct GameRegistry has key {
        creator: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    /// Individual bet details for tracking multiple bets
    struct BetDetails has drop, store {
        bet_type: BetType,
        amount: u64,
        payout: u64,
        won: bool
    }

    /// Enhanced user's latest spin result with comprehensive bet tracking
    struct SpinResult has key {
        /// The number that won (0-36)
        winning_number: u8,
        /// Color of winning number
        winning_color: String,  // "red", "black", "green"
        /// Properties of winning number
        is_even: bool,
        is_high: bool,         // 19-36 vs 1-18
        dozen: u8,             // 1, 2, or 3 (0 for number 0)
        column: u8,            // 1, 2, or 3 (0 for number 0)
        /// All bets placed in this spin
        all_bets: vector<BetDetails>,
        /// Total amount wagered across all bets
        total_wagered: u64,
        /// Total payout received across all bets
        total_payout: u64,
        /// Number of winning bets
        winning_bets: u8,
        /// When the spin occurred
        timestamp: u64,
        /// Session identifier for frontend
        session_id: u64,
        /// Overall win/loss for this spin
        net_result: bool  // true if total_payout > total_wagered
    }

    //
    // Events
    //

    #[event]
    /// Event emitted when roulette is spun with multiple bets
    struct RouletteSpinEvent has drop, store {
        player: address,
        winning_number: u8,
        winning_color: String,
        total_wagered: u64,
        total_payout: u64,
        winning_bets: u8,
        total_bets: u8,
        treasury_used: address,  // Changed from u8 to address
        session_id: u64
    }

    #[event]
    /// Event for individual bet results (for analytics)
    struct BetResultEvent has drop, store {
        player: address,
        bet_type_description: String,
        amount: u64,
        payout: u64,
        won: bool,
        session_id: u64
    }

    //
    // Enum Helper Functions
    //

    /// Convert primitive u8 to BetType enum (internal conversion from entry functions)
    fun u8_to_bet_type(bet_type_u8: u8, bet_value: u8, bet_numbers: &vector<u8>): BetType {
        if (bet_type_u8 == 0) {
            BetType::SingleNumber { number: bet_value }
        } else if (bet_type_u8 == 1) {
            BetType::Red
        } else if (bet_type_u8 == 2) {
            BetType::Black
        } else if (bet_type_u8 == 3) {
            BetType::Even
        } else if (bet_type_u8 == 4) {
            BetType::Odd
        } else if (bet_type_u8 == 5) {
            BetType::High
        } else if (bet_type_u8 == 6) {
            BetType::Low
        } else if (bet_type_u8 == 7) {
            BetType::FirstDozen
        } else if (bet_type_u8 == 8) {
            BetType::SecondDozen
        } else if (bet_type_u8 == 9) {
            BetType::ThirdDozen
        } else if (bet_type_u8 == 10) {
            BetType::FirstColumn
        } else if (bet_type_u8 == 11) {
            BetType::SecondColumn
        } else if (bet_type_u8 == 12) {
            BetType::ThirdColumn
        } else if (bet_type_u8 == 13) {
            let num1 = *vector::borrow(bet_numbers, 0);
            let num2 = *vector::borrow(bet_numbers, 1);
            BetType::Split { num1, num2 }
        } else if (bet_type_u8 == 14) {
            BetType::Street { start_num: bet_value }
        } else if (bet_type_u8 == 15) {
            BetType::Corner { top_left: bet_value }
        } else if (bet_type_u8 == 16) {
            BetType::Line { start_num: bet_value }
        } else {
            abort E_INVALID_BET_TYPE
        }
    }

    /// Get descriptive string for bet type (for events and frontend)
    fun bet_type_to_string(bet_type: &BetType): String {
        match (bet_type) {
            BetType::SingleNumber { number } => {
                if (*number == 0) {
                    string::utf8(b"Single Number: 0")
                } else if (*number < 10) {
                    string::utf8(b"Single Number: 1-9")  // Simplified for now
                } else {
                    string::utf8(b"Single Number: 10+")  // Simplified for now
                }
            },
            BetType::Red => string::utf8(b"Red"),
            BetType::Black => string::utf8(b"Black"),
            BetType::Even => string::utf8(b"Even"),
            BetType::Odd => string::utf8(b"Odd"),
            BetType::High => string::utf8(b"High (19-36)"),
            BetType::Low => string::utf8(b"Low (1-18)"),
            BetType::FirstDozen => string::utf8(b"First Dozen (1-12)"),
            BetType::SecondDozen => string::utf8(b"Second Dozen (13-24)"),
            BetType::ThirdDozen => string::utf8(b"Third Dozen (25-36)"),
            BetType::FirstColumn => string::utf8(b"First Column"),
            BetType::SecondColumn => string::utf8(b"Second Column"),
            BetType::ThirdColumn => string::utf8(b"Third Column"),
            BetType::Split { num1: _, num2: _ } => {
                string::utf8(b"Split Bet")  // Simplified
            },
            BetType::Street { start_num: _ } => {
                string::utf8(b"Street Bet")  // Simplified
            },
            BetType::Corner { top_left: _ } => {
                string::utf8(b"Corner Bet")  // Simplified
            },
            BetType::Line { start_num: _ } => {
                string::utf8(b"Line Bet")  // Simplified
            }
        }
    }

    //
    // Helper Functions
    //

    /// Check if a number is red
    public fun is_red(number: u8): bool {
        if (number == 0) return false;
        vector::contains(&RED_NUMBERS, &number)
    }

    /// Check if a number is black
    public fun is_black(number: u8): bool {
        if (number == 0) return false;
        !is_red(number)
    }

    /// Check if a number is even (0 is neither even nor odd for betting)
    public fun is_even(number: u8): bool {
        if (number == 0) return false;
        number % 2 == 0
    }

    /// Check if a number is odd
    public fun is_odd(number: u8): bool {
        if (number == 0) return false;
        number % 2 == 1
    }

    /// Check if a number is high (19-36)
    public fun is_high(number: u8): bool {
        number >= 19 && number <= 36
    }

    /// Check if a number is low (1-18)
    public fun is_low(number: u8): bool {
        number >= 1 && number <= 18
    }

    /// Get dozen for a number (1-12 = 1, 13-24 = 2, 25-36 = 3, 0 = 0)
    public fun get_dozen(number: u8): u8 {
        if (number == 0) return 0;
        if (number <= 12) return 1;
        if (number <= 24) return 2;
        3
    }

    /// Get column for a number (1,4,7... = 1, 2,5,8... = 2, 3,6,9... = 3, 0 = 0)
    public fun get_column(number: u8): u8 {
        if (number == 0) return 0;
        ((number - 1) % 3) + 1
    }

    /// Get color string for a number
    public fun get_color_string(number: u8): String {
        if (number == 0) return string::utf8(b"green");
        if (is_red(number)) return string::utf8(b"red");
        string::utf8(b"black")
    }

    /// Validate split bet (two adjacent numbers)
    fun is_valid_split(num1: u8, num2: u8): bool {
        if (num1 > MAX_ROULETTE_NUMBER || num2 > MAX_ROULETTE_NUMBER) return false;
        if (num1 == num2) return false;
        
        // Horizontal adjacency (same row)
        if ((num1 != 0 && num2 != 0) && (num1 / 3 == num2 / 3) && 
            ((num1 + 1 == num2) || (num2 + 1 == num1))) return true;
        
        // Vertical adjacency (same column)
        if ((num1 != 0 && num2 != 0) && ((num1 + 3 == num2) || (num2 + 3 == num1))) return true;
        
        // Special case: 0 can split with 1, 2, 3
        if ((num1 == 0 && (num2 == 1 || num2 == 2 || num2 == 3)) || 
            (num2 == 0 && (num1 == 1 || num1 == 2 || num1 == 3))) return true;
        
        false
    }

    /// Validate street bet (three numbers in a row)
    fun is_valid_street(start_num: u8): bool {
        if (start_num == 0 || start_num > 34) return false;
        (start_num - 1) % 3 == 0  // Must be 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34
    }

    /// Validate corner bet (four numbers in a square)
    fun is_valid_corner(top_left: u8): bool {
        if (top_left == 0 || top_left > 32) return false;
        let _row = (top_left - 1) / 3;
        let col = (top_left - 1) % 3;
        col < 2  // Can't be rightmost column
    }

    /// Validate line bet (six numbers in two rows)
    fun is_valid_line(start_num: u8): bool {
        if (start_num == 0 || start_num > 31) return false;
        (start_num - 1) % 3 == 0  // Must be 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31
    }

    /// Calculate payout for a specific bet type and amount using enums
    fun calculate_bet_payout(bet_type: &BetType, amount: u64, winning_number: u8): u64 {
        let won = is_winning_bet(bet_type, winning_number);
        if (!won) return 0;

        match (bet_type) {
            BetType::SingleNumber { number: _ } => amount * SINGLE_NUMBER_PAYOUT,
            BetType::Red => amount * EVEN_MONEY_PAYOUT,
            BetType::Black => amount * EVEN_MONEY_PAYOUT,
            BetType::Even => amount * EVEN_MONEY_PAYOUT,
            BetType::Odd => amount * EVEN_MONEY_PAYOUT,
            BetType::High => amount * EVEN_MONEY_PAYOUT,
            BetType::Low => amount * EVEN_MONEY_PAYOUT,
            BetType::FirstDozen => amount * DOZEN_COLUMN_PAYOUT,
            BetType::SecondDozen => amount * DOZEN_COLUMN_PAYOUT,
            BetType::ThirdDozen => amount * DOZEN_COLUMN_PAYOUT,
            BetType::FirstColumn => amount * DOZEN_COLUMN_PAYOUT,
            BetType::SecondColumn => amount * DOZEN_COLUMN_PAYOUT,
            BetType::ThirdColumn => amount * DOZEN_COLUMN_PAYOUT,
            BetType::Split { num1: _, num2: _ } => amount * SPLIT_PAYOUT,
            BetType::Street { start_num: _ } => amount * STREET_PAYOUT,
            BetType::Corner { top_left: _ } => amount * CORNER_PAYOUT,
            BetType::Line { start_num: _ } => amount * LINE_PAYOUT
        }
    }

    /// Check if a bet wins for the given winning number using enums
    fun is_winning_bet(bet_type: &BetType, winning_number: u8): bool {
        match (bet_type) {
            BetType::SingleNumber { number } => winning_number == *number,
            BetType::Red => is_red(winning_number),
            BetType::Black => is_black(winning_number),
            BetType::Even => is_even(winning_number),
            BetType::Odd => is_odd(winning_number),
            BetType::High => is_high(winning_number),
            BetType::Low => is_low(winning_number),
            BetType::FirstDozen => get_dozen(winning_number) == 1,
            BetType::SecondDozen => get_dozen(winning_number) == 2,
            BetType::ThirdDozen => get_dozen(winning_number) == 3,
            BetType::FirstColumn => get_column(winning_number) == 1,
            BetType::SecondColumn => get_column(winning_number) == 2,
            BetType::ThirdColumn => get_column(winning_number) == 3,
            BetType::Split { num1, num2 } => winning_number == *num1 || winning_number == *num2,
            BetType::Street { start_num } => {
                winning_number >= *start_num && winning_number <= *start_num + 2
            },
            BetType::Corner { top_left } => {
                let tl = *top_left;
                winning_number == tl || winning_number == tl + 1 || 
                winning_number == tl + 3 || winning_number == tl + 4
            },
            BetType::Line { start_num } => {
                winning_number >= *start_num && winning_number <= *start_num + 5
            }
        }
    }

    //
    // Game Initialization
    //

    /// Initialize game after registration with casino
    public entry fun initialize_game(deployer: &signer) {
        let deployer_addr = signer::address_of(deployer);
        assert!(deployer_addr == @roulette_game, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(deployer_addr), E_ALREADY_INITIALIZED);

        // Get game object from casino registration - CASINO is always the creator
        let game_name = string::utf8(b"AptosRoulette");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr = CasinoHouse::derive_game_object_address(
            @casino,      // ✅ Casino creates the object, not @roulette_game
            game_name, 
            version
        );
        let game_object: Object<CasinoHouse::GameMetadata> = 
            object::address_to_object(game_object_addr);
        assert!(CasinoHouse::is_game_registered(game_object), E_GAME_NOT_REGISTERED);

        // Create named object for storing capability
        let seed = build_game_seed();
        let constructor_ref = object::create_named_object(deployer, seed);
        let _object_addr = object::address_from_constructor_ref(&constructor_ref);

        // Get extend ref before moving constructor_ref
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Disable transfer for security
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        // Get capability from casino
        let capability = CasinoHouse::get_game_capability(deployer, game_object);

        // Store capability in object
        let game_auth = GameAuth {
            capability,
            extend_ref
        };
        move_to(&object::generate_signer(&constructor_ref), game_auth);

        // Store registry information
        let registry = GameRegistry {
            creator: deployer_addr,
            game_object,
            game_name: string::utf8(b"AptosRoulette"),
            version: string::utf8(GAME_VERSION)
        };
        move_to(deployer, registry);
    }

    #[randomness]
    entry fun place_multi_bet(
        player: &signer,
        bet_types_u8: vector<u8>,           // Primitives for entry function
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult {
        let num_bets = vector::length(&bet_types_u8);
        assert!(num_bets > 0, E_INVALID_AMOUNT);
        assert!(num_bets <= MAX_BETS_PER_TRANSACTION, E_TOO_MANY_BETS);
        assert!(vector::length(&bet_values) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&bet_numbers_list) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&amounts) == num_bets, E_MISMATCHED_BET_ARRAYS);

        let player_addr = signer::address_of(player);

        // Convert primitives to enum bet types and validate
        let bet_types = vector::empty<BetType>();
        let total_amount = 0;
        let i = 0;
        while (i < num_bets) {
            let bet_type_u8 = *vector::borrow(&bet_types_u8, i);
            let bet_value = *vector::borrow(&bet_values, i);
            let bet_numbers = vector::borrow(&bet_numbers_list, i);
            let amount = *vector::borrow(&amounts, i);

            // Convert to enum (internal type safety)
            let bet_type = u8_to_bet_type(bet_type_u8, bet_value, bet_numbers);
            validate_bet(&bet_type, amount);
            vector::push_back(&mut bet_types, bet_type);
            
            total_amount = total_amount + amount;
            i = i + 1;
        };

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
                timestamp: _,
                session_id: _,
                net_result: _
            } = old_result;
        };

        // Withdraw total bet amount
        let aptos_metadata_option = coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let total_bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, total_amount);

        // Get capability
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Place consolidated bet with casino
        let (treasury_source, bet_id) = CasinoHouse::place_bet(
            capability, 
            total_bet_fa, 
            player_addr
        );

        // Spin the wheel
        let winning_number = randomness::u8_range(0, 37); // 0 to 36 inclusive

        // Calculate properties of winning number
        let winning_color = get_color_string(winning_number);
        let is_even_win = is_even(winning_number);
        let is_high_win = is_high(winning_number);
        let dozen_win = get_dozen(winning_number);
        let column_win = get_column(winning_number);

        // Process all bets and calculate payouts
        let all_bets = vector::empty<BetDetails>();
        let total_payout = 0;
        let winning_bets_count = 0;

        i = 0;
        while (i < num_bets) {
            let bet_type = vector::borrow(&bet_types, i);
            let amount = *vector::borrow(&amounts, i);

            let payout = calculate_bet_payout(bet_type, amount, winning_number);
            let won = payout > 0;
            if (won) winning_bets_count = winning_bets_count + 1;
            total_payout = total_payout + payout;

            let bet_detail = BetDetails {
                bet_type: *bet_type,
                amount,
                payout,
                won
            };
            vector::push_back(&mut all_bets, bet_detail);

            // Emit individual bet result event
            event::emit(BetResultEvent {
                player: player_addr,
                bet_type_description: bet_type_to_string(bet_type),
                amount,
                payout,
                won,
                session_id: account::get_sequence_number(player_addr)
            });

            i = i + 1;
        };

        // Settle with casino
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            total_payout,
            treasury_source
        );

        // Store comprehensive result
        let current_time = timestamp::now_seconds();
        let session_id = account::get_sequence_number(player_addr);
        let net_result = total_payout > total_amount;

        let spin_result = SpinResult {
            winning_number,
            winning_color,
            is_even: is_even_win,
            is_high: is_high_win,
            dozen: dozen_win,
            column: column_win,
            all_bets,
            total_wagered: total_amount,
            total_payout,
            winning_bets: winning_bets_count,
            timestamp: current_time,
            session_id,
            net_result
        };
        move_to(player, spin_result);

        // Emit comprehensive spin event
        event::emit(RouletteSpinEvent {
            player: player_addr,
            winning_number,
            winning_color,
            total_wagered: total_amount,
            total_payout,
            winning_bets: winning_bets_count,
            total_bets: (num_bets as u8),
            treasury_used: treasury_source,  // Now correctly using address type
            session_id
        });
    }

    //
    // Convenience Entry Functions (Backward Compatible - SECURE: Not callable from other contracts)
    //

    #[randomness]
    entry fun spin_roulette(player: &signer, bet_number: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        place_multi_bet(
            player,
            vector[0], // SingleNumber bet type
            vector[bet_number],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_red_black(player: &signer, is_red: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        let bet_type_u8 = if (is_red) 1 else 2; // Red = 1, Black = 2
        place_multi_bet(
            player,
            vector[bet_type_u8],
            vector[0], // Value not used for red/black
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_even_odd(player: &signer, is_even: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        let bet_type_u8 = if (is_even) 3 else 4; // Even = 3, Odd = 4
        place_multi_bet(
            player,
            vector[bet_type_u8],
            vector[0],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_high_low(player: &signer, is_high: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        let bet_type_u8 = if (is_high) 5 else 6; // High = 5, Low = 6
        place_multi_bet(
            player,
            vector[bet_type_u8],
            vector[0],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_dozen(player: &signer, dozen: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(dozen >= 1 && dozen <= 3, E_INVALID_DOZEN);
        let bet_type_u8 = 6 + dozen; // FirstDozen = 7, SecondDozen = 8, ThirdDozen = 9
        place_multi_bet(
            player,
            vector[bet_type_u8],
            vector[dozen],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_column(player: &signer, column: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(column >= 1 && column <= 3, E_INVALID_COLUMN);
        let bet_type_u8 = 9 + column; // FirstColumn = 10, SecondColumn = 11, ThirdColumn = 12
        place_multi_bet(
            player,
            vector[bet_type_u8],
            vector[column],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_split(player: &signer, num1: u8, num2: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(is_valid_split(num1, num2), E_INVALID_SPLIT);
        place_multi_bet(
            player,
            vector[13], // Split bet type
            vector[num1],
            vector[vector[num1, num2]],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_street(player: &signer, start_num: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(is_valid_street(start_num), E_INVALID_STREET);
        place_multi_bet(
            player,
            vector[14], // Street bet type
            vector[start_num],
            vector[vector[start_num, start_num + 1, start_num + 2]],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_corner(player: &signer, top_left: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(is_valid_corner(top_left), E_INVALID_CORNER);
        place_multi_bet(
            player,
            vector[15], // Corner bet type
            vector[top_left],
            vector[vector[top_left, top_left + 1, top_left + 3, top_left + 4]],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_line(player: &signer, start_num: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        assert!(is_valid_line(start_num), E_INVALID_LINE);
        let line_numbers = vector[
            start_num, start_num + 1, start_num + 2, 
            start_num + 3, start_num + 4, start_num + 5
        ];
        place_multi_bet(
            player,
            vector[16], // Line bet type
            vector[start_num],
            vector[line_numbers],
            vector[amount]
        );
    }

    //
    // Validation Functions
    //

    /// Validate a bet using enum
    fun validate_bet(bet_type: &BetType, amount: u64) {
        // Validate amount
        assert!(amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(amount <= MAX_BET, E_INVALID_AMOUNT);

        // Validate bet type specific constraints
        match (bet_type) {
            BetType::SingleNumber { number } => {
                assert!(*number <= MAX_ROULETTE_NUMBER, E_INVALID_NUMBER);
            },
            BetType::Split { num1, num2 } => {
                assert!(is_valid_split(*num1, *num2), E_INVALID_SPLIT);
            },
            BetType::Street { start_num } => {
                assert!(is_valid_street(*start_num), E_INVALID_STREET);
            },
            BetType::Corner { top_left } => {
                assert!(is_valid_corner(*top_left), E_INVALID_CORNER);
            },
            BetType::Line { start_num } => {
                assert!(is_valid_line(*start_num), E_INVALID_LINE);
            },
            BetType::Red => {
                // No additional validation needed
            },
            BetType::Black => {
                // No additional validation needed
            },
            BetType::Even => {
                // No additional validation needed
            },
            BetType::Odd => {
                // No additional validation needed
            },
            BetType::High => {
                // No additional validation needed
            },
            BetType::Low => {
                // No additional validation needed
            },
            BetType::FirstDozen => {
                // No additional validation needed
            },
            BetType::SecondDozen => {
                // No additional validation needed
            },
            BetType::ThirdDozen => {
                // No additional validation needed
            },
            BetType::FirstColumn => {
                // No additional validation needed
            },
            BetType::SecondColumn => {
                // No additional validation needed
            },
            BetType::ThirdColumn => {
                // No additional validation needed
            }
        };
    }

    //
    // Utility Functions
    //

    fun build_game_seed(): vector<u8> {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"AptosRoulette_");
        vector::append(&mut seed, GAME_VERSION);
        seed
    }

    fun get_game_object_address(): address {
        let creator = @roulette_game;
        let seed = build_game_seed();
        object::create_object_address(&creator, seed)
    }

    //
    // Test-Only Functions (Following your security pattern)
    //

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_spin_roulette(player: &signer, bet_number: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        spin_roulette(player, bet_number, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_place_multi_bet(
        player: &signer,
        bet_types_u8: vector<u8>,
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult {
        place_multi_bet(player, bet_types_u8, bet_values, bet_numbers_list, amounts);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_red_black(player: &signer, is_red: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_red_black(player, is_red, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_even_odd(player: &signer, is_even: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_even_odd(player, is_even, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_high_low(player: &signer, is_high: bool, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_high_low(player, is_high, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_dozen(player: &signer, dozen: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_dozen(player, dozen, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_column(player: &signer, column: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_column(player, column, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_split(player: &signer, num1: u8, num2: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_split(player, num1, num2, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_street(player: &signer, start_num: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_street(player, start_num, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_corner(player: &signer, top_left: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_corner(player, top_left, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_line(player: &signer, start_num: u8, amount: u64) 
    acquires GameAuth, SpinResult {
        bet_line(player, start_num, amount);
    }

    // Test helper to create enum variants (module boundary pattern)
    #[test_only]
    public fun create_single_number_bet(number: u8): BetType {
        BetType::SingleNumber { number }
    }

    #[test_only]
    public fun create_red_bet(): BetType {
        BetType::Red
    }

    #[test_only]
    public fun create_split_bet(num1: u8, num2: u8): BetType {
        BetType::Split { num1, num2 }
    }

    //
    // View Functions
    //

    #[view]
    public fun is_valid_roulette_number(number: u8): bool {
        number <= MAX_ROULETTE_NUMBER
    }

    #[view]
    public fun calculate_single_number_payout(amount: u64): u64 {
        amount * SINGLE_NUMBER_PAYOUT
    }

    #[view]
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, SINGLE_NUMBER_PAYOUT, HOUSE_EDGE_BPS)
    }

    #[view]
    public fun get_roulette_range(): (u8, u8) {
        (0, MAX_ROULETTE_NUMBER)
    }

    #[view]
    public fun get_wheel_info(): (u8, String, u64) {
        (MAX_ROULETTE_NUMBER + 1, string::utf8(b"European"), SINGLE_NUMBER_PAYOUT)
    }

    #[view]
    /// Get payout multipliers for all bet types
    public fun get_payout_table(): (u64, u64, u64, u64, u64, u64, u64) {
        (
            SINGLE_NUMBER_PAYOUT,  // 35:1
            EVEN_MONEY_PAYOUT,     // 1:1
            DOZEN_COLUMN_PAYOUT,   // 2:1
            SPLIT_PAYOUT,          // 17:1
            STREET_PAYOUT,         // 11:1
            CORNER_PAYOUT,         // 8:1
            LINE_PAYOUT            // 5:1
        )
    }

    #[view]
    /// Get player's latest spin result
    public fun get_latest_result(player: address): (
        u8, String, bool, bool, u8, u8, u64, u64, u8, u64, bool
    ) acquires SpinResult {
        assert!(exists<SpinResult>(player), E_INVALID_AMOUNT);
        let result = borrow_global<SpinResult>(player);
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
            result.session_id,
            result.net_result
        )
    }

    #[view]
    public fun can_handle_payout(bet_amount: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let expected_payout = bet_amount * SINGLE_NUMBER_PAYOUT;
        let game_treasury_balance = CasinoHouse::game_treasury_balance(registry.game_object);

        game_treasury_balance >= expected_payout || 
        CasinoHouse::central_treasury_balance() >= expected_payout
    }

    #[view]
    public fun game_treasury_balance(): u64 acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        CasinoHouse::game_treasury_balance(registry.game_object)
    }

    #[view]
    public fun game_treasury_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        CasinoHouse::get_game_treasury_address(registry.game_object)
    }

    #[view]
    public fun is_registered(): bool acquires GameRegistry {
        if (!exists<GameRegistry>(@roulette_game)) { false }
        else {
            let registry = borrow_global<GameRegistry>(@roulette_game);
            CasinoHouse::is_game_registered(registry.game_object)
        }
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameRegistry>(@roulette_game)
    }

    #[view]
    public fun is_ready(): bool acquires GameRegistry {
        is_registered() && is_initialized()
    }

    #[view]
    public fun object_exists(): bool {
        if (!is_initialized()) { false }
        else {
            let object_addr = get_game_object_address();
            exists<GameAuth>(object_addr)
        }
    }

    #[view]
    public fun get_game_info(): (address, Object<CasinoHouse::GameMetadata>, String, String) 
    acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        (registry.creator, registry.game_object, registry.game_name, registry.version)
    }
}
