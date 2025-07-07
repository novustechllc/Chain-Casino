//! MIT License
//!
//! AptosRoulette Game Module
//!
//! European roulette with comprehensive betting options and casino integration.

module roulette_game::AptosRoulette {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::object::{Self, Object};
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
    const GAME_VERSION: vector<u8> = b"v1";
    /// Minimum bet amount (0.01 APT)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.3 APT)
    const MAX_BET: u64 = 30000000;
    /// Maximum bets per transaction
    const MAX_BETS_PER_TRANSACTION: u64 = 10;

    // Bet type constants
    const BET_TYPE_NUMBER: u8 = 0;
    const BET_TYPE_SPLIT: u8 = 1;
    const BET_TYPE_STREET: u8 = 2;
    const BET_TYPE_CORNER: u8 = 3;
    const BET_TYPE_RED_BLACK: u8 = 4;
    const BET_TYPE_EVEN_ODD: u8 = 5;
    const BET_TYPE_HIGH_LOW: u8 = 6;
    const BET_TYPE_DOZEN: u8 = 7;
    const BET_TYPE_COLUMN: u8 = 8;
    const BET_TYPE_LINE: u8 = 9;

    // Payout multipliers
    const PAYOUT_SINGLE: u64 = 35; // 35:1
    const PAYOUT_SPLIT: u64 = 17; // 17:1
    const PAYOUT_STREET: u64 = 11; // 11:1
    const PAYOUT_CORNER: u64 = 8; // 8:1
    const PAYOUT_LINE: u64 = 5; // 5:1
    const PAYOUT_EVEN_MONEY: u64 = 1; // 1:1 (red/black, even/odd, high/low)
    const PAYOUT_DOZEN_COLUMN: u64 = 2; // 2:1 (dozens, columns)

    //
    // Structs
    //

    /// Session identifier following BetId pattern
    struct SessionId has copy, drop, store {
        player: address,
        sequence: u64
    }

    /// Individual bet result
    struct BetResult has copy, drop, store {
        bet_type: u8,
        bet_value: u8,
        amount: u64,
        payout: u64,
        won: bool
    }

    /// Complete roulette spin result stored at player address
    struct SpinResult has key {
        winning_number: u8,
        winning_color: String,
        is_even: bool,
        is_high: bool,
        dozen: u8,
        column: u8,
        all_bets: vector<BetResult>,
        total_wagered: u64,
        total_payout: u64,
        winning_bets: u8,
        session_id: SessionId,
        net_result: bool
    }

    /// Game registry storing game metadata
    struct GameRegistry has key {
        creator: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    /// Game authentication storing capability
    struct GameAuth has key {
        capability: GameCapability,
        extend_ref: object::ExtendRef
    }

    //
    // Events
    //

    #[event]
    /// Emitted for each individual bet result
    struct BetResultEvent has drop, store {
        player: address,
        bet_type_description: String,
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
    // Helper Functions
    //

    /// Generate unique session ID following BetId pattern
    fun generate_session_id(player_addr: address): SessionId {
        SessionId {
            player: player_addr,
            sequence: account::get_sequence_number(player_addr)
        }
    }

    /// Build seed for game object creation
    fun build_game_seed(): vector<u8> {
        let seed = b"AptosRoulette";
        vector::append(&mut seed, GAME_VERSION);
        seed
    }

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
        if (diff == 3) {
            return true
        };

        false
    }

    /// Convert bet type to string for events
    fun bet_type_to_string(bet_type: u8): String {
        if (bet_type == BET_TYPE_NUMBER) {
            string::utf8(b"Number")
        } else if (bet_type == BET_TYPE_SPLIT) {
            string::utf8(b"Split")
        } else if (bet_type == BET_TYPE_STREET) {
            string::utf8(b"Street")
        } else if (bet_type == BET_TYPE_CORNER) {
            string::utf8(b"Corner")
        } else if (bet_type == BET_TYPE_RED_BLACK) {
            string::utf8(b"Red/Black")
        } else if (bet_type == BET_TYPE_EVEN_ODD) {
            string::utf8(b"Even/Odd")
        } else if (bet_type == BET_TYPE_HIGH_LOW) {
            string::utf8(b"High/Low")
        } else if (bet_type == BET_TYPE_DOZEN) {
            string::utf8(b"Dozen")
        } else if (bet_type == BET_TYPE_COLUMN) {
            string::utf8(b"Column")
        } else if (bet_type == BET_TYPE_LINE) {
            string::utf8(b"Line")
        } else {
            string::utf8(b"Unknown")
        }
    }

    //
    // Initialization
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

        // Create named object for storing capability
        let seed = build_game_seed();
        let constructor_ref = object::create_named_object(deployer, seed);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        // Get capability from casino
        let capability = CasinoHouse::get_game_capability(deployer, game_object);

        // Store capability in object
        let game_auth = GameAuth { capability, extend_ref };
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

    //
    // Core Game Logic
    //

    #[randomness]
    entry fun place_multi_bet(
        player: &signer,
        bet_types_u8: vector<u8>,
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult, GameRegistry {
        let num_bets = vector::length(&bet_types_u8);
        assert!(num_bets > 0, E_INVALID_AMOUNT);
        assert!(num_bets <= MAX_BETS_PER_TRANSACTION, E_TOO_MANY_BETS);
        assert!(vector::length(&bet_values) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&bet_numbers_list) == num_bets, E_MISMATCHED_BET_ARRAYS);
        assert!(vector::length(&amounts) == num_bets, E_MISMATCHED_BET_ARRAYS);

        let player_addr = signer::address_of(player);

        // Auto-cleanup: Remove previous result
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

        // Validate all bets and calculate total
        let total_amount = 0u64;
        let i = 0;
        while (i < num_bets) {
            let amount = *vector::borrow(&amounts, i);
            assert!(amount >= MIN_BET, E_INVALID_AMOUNT);
            assert!(amount <= MAX_BET, E_INVALID_AMOUNT);
            total_amount = total_amount + amount;
            i = i + 1;
        };

        // Get fungible asset metadata
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);

        // Withdraw total bet amount
        let bet_fa = primary_fungible_store::withdraw(
            player, aptos_metadata, total_amount
        );

        // Get capability from object
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Casino creates bet ID
        let (treasury_source, bet_id) =
            CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Spin the roulette wheel with secure randomness
        let winning_number = randomness::u8_range(0, 37); // 0-36

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

        // Process all bets and calculate payouts
        let all_bets = vector::empty<BetResult>();
        let total_payout = 0u64;
        let winning_bets_count = 0u8;
        let sequence = account::get_sequence_number(player_addr);

        i = 0;
        while (i < num_bets) {
            let bet_type = *vector::borrow(&bet_types_u8, i);
            let bet_value = *vector::borrow(&bet_values, i);
            let amount = *vector::borrow(&amounts, i);

            let (won, payout) =
                calculate_bet_payout(bet_type, bet_value, winning_number, amount);

            if (won) {
                total_payout = total_payout + payout;
                winning_bets_count = winning_bets_count + 1;
            };

            let bet_result = BetResult { bet_type, bet_value, amount, payout, won };
            vector::push_back(&mut all_bets, bet_result);

            // Emit individual bet result event
            event::emit(
                BetResultEvent {
                    player: player_addr,
                    bet_type_description: bet_type_to_string(bet_type),
                    amount,
                    payout,
                    won,
                    sequence
                }
            );

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

        // Generate collision-free session ID
        let session_id = generate_session_id(player_addr);
        let net_result = total_payout > total_amount;

        // Store comprehensive result
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
            session_id,
            net_result
        };
        move_to(player, spin_result);

        // Emit comprehensive spin event
        event::emit(
            RouletteSpinEvent {
                player: player_addr,
                winning_number,
                winning_color,
                total_wagered: total_amount,
                total_payout,
                winning_bets: winning_bets_count,
                total_bets: (num_bets as u8),
                treasury_used: treasury_source,
                sequence
            }
        );
    }

    /// Calculate payout for individual bet
    fun calculate_bet_payout(
        bet_type: u8,
        bet_value: u8,
        winning_number: u8,
        amount: u64
    ): (bool, u64) {
        if (bet_type == BET_TYPE_NUMBER) {
            if (bet_value == winning_number) {
                (true, amount * PAYOUT_SINGLE)
            } else {
                (false, 0)
            }
        } else if (bet_type == BET_TYPE_RED_BLACK) {
            let is_red_bet = bet_value == 1;
            let is_winning_red = is_red_number(winning_number);
            if (winning_number != 0 && is_red_bet == is_winning_red) {
                (true, amount * PAYOUT_EVEN_MONEY)
            } else {
                (false, 0)
            }
        } else if (bet_type == BET_TYPE_EVEN_ODD) {
            let is_even_bet = bet_value == 1;
            if (winning_number != 0 && (winning_number % 2 == 0) == is_even_bet) {
                (true, amount * PAYOUT_EVEN_MONEY)
            } else {
                (false, 0)
            }
        } else if (bet_type == BET_TYPE_HIGH_LOW) {
            let is_high_bet = bet_value == 1;
            let is_high = winning_number >= 19 && winning_number <= 36;
            let is_low = winning_number >= 1 && winning_number <= 18;
            if ((is_high_bet && is_high) || (!is_high_bet && is_low)) {
                (true, amount * PAYOUT_EVEN_MONEY)
            } else {
                (false, 0)
            }
        } else if (bet_type == BET_TYPE_DOZEN) {
            let dozen = get_dozen_for_number(winning_number);
            if (bet_value == dozen && dozen != 0) {
                (true, amount * PAYOUT_DOZEN_COLUMN)
            } else {
                (false, 0)
            }
        } else if (bet_type == BET_TYPE_COLUMN) {
            let column = get_column_for_number(winning_number);
            if (bet_value == column && column != 0) {
                (true, amount * PAYOUT_DOZEN_COLUMN)
            } else {
                (false, 0)
            }
        } else {
            (false, 0)
        }
    }

    //
    // Convenience Entry Functions
    //

    #[randomness]
    entry fun bet_number(
        player: &signer, number: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        assert!(number <= 36, E_INVALID_NUMBER);

        place_multi_bet(
            player,
            vector[BET_TYPE_NUMBER],
            vector[number],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_red_black(
        player: &signer, is_red: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_value = if (is_red) { 1 }
        else { 0 };

        place_multi_bet(
            player,
            vector[BET_TYPE_RED_BLACK],
            vector[bet_value],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_even_odd(
        player: &signer, is_even: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_value = if (is_even) { 1 }
        else { 0 };

        place_multi_bet(
            player,
            vector[BET_TYPE_EVEN_ODD],
            vector[bet_value],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_high_low(
        player: &signer, is_high: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        let bet_value = if (is_high) { 1 }
        else { 0 };

        place_multi_bet(
            player,
            vector[BET_TYPE_HIGH_LOW],
            vector[bet_value],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_dozen(
        player: &signer, dozen: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        assert!(dozen >= 1 && dozen <= 3, E_INVALID_DOZEN);

        place_multi_bet(
            player,
            vector[BET_TYPE_DOZEN],
            vector[dozen],
            vector[vector::empty<u8>()],
            vector[amount]
        );
    }

    #[randomness]
    entry fun bet_column(
        player: &signer, column: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        assert!(column >= 1 && column <= 3, E_INVALID_COLUMN);

        place_multi_bet(
            player,
            vector[BET_TYPE_COLUMN],
            vector[column],
            vector[vector::empty<u8>()],
            vector[amount]
        );
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
    /// Get session info returning SessionId struct
    public fun get_session_info(player_addr: address): SessionId acquires SpinResult {
        assert!(exists<SpinResult>(player_addr), E_NOT_INITIALIZED);
        let result = borrow_global<SpinResult>(player_addr);
        result.session_id
    }

    #[view]
    /// Get payout table
    public fun get_payout_table(): (u64, u64, u64, u64, u64, u64, u64) {
        (
            PAYOUT_SINGLE, // 35:1
            PAYOUT_EVEN_MONEY, // 1:1
            PAYOUT_DOZEN_COLUMN, // 2:1
            PAYOUT_SPLIT, // 17:1
            PAYOUT_STREET, // 11:1
            PAYOUT_CORNER, // 8:1
            PAYOUT_LINE // 5:1
        )
    }

    #[view]
    public fun is_red(number: u8): bool {
        is_red_number(number)
    }

    #[view]
    public fun is_black(number: u8): bool {
        number != 0 && !is_red_number(number)
    }

    #[view]
    public fun is_even(number: u8): bool {
        number != 0 && number % 2 == 0
    }

    #[view]
    public fun is_odd(number: u8): bool {
        number != 0 && number % 2 == 1
    }

    #[view]
    public fun get_dozen(number: u8): u8 {
        get_dozen_for_number(number)
    }

    #[view]
    public fun get_column(number: u8): u8 {
        get_column_for_number(number)
    }

    #[view]
    public fun get_color_string(number: u8): String {
        if (number == 0) {
            string::utf8(b"green")
        } else if (is_red_number(number)) {
            string::utf8(b"red")
        } else {
            string::utf8(b"black")
        }
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let seed = build_game_seed();
        object::create_object_address(&registry.creator, seed)
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameRegistry>(@roulette_game)
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
    public fun is_ready(): bool acquires GameRegistry {
        is_registered() && is_initialized()
    }

    #[view]
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
    public entry fun test_only_bet_even_odd(
        player: &signer, is_even: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_even_odd(player, is_even, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_high_low(
        player: &signer, is_high: bool, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_high_low(player, is_high, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_dozen(
        player: &signer, dozen: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_dozen(player, dozen, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_bet_column(
        player: &signer, column: u8, amount: u64
    ) acquires GameAuth, SpinResult, GameRegistry {
        bet_column(player, column, amount);
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_place_multi_bet(
        player: &signer,
        bet_types_u8: vector<u8>,
        bet_values: vector<u8>,
        bet_numbers_list: vector<vector<u8>>,
        amounts: vector<u64>
    ) acquires GameAuth, SpinResult, GameRegistry {
        place_multi_bet(
            player,
            bet_types_u8,
            bet_values,
            bet_numbers_list,
            amounts
        );
    }
}
