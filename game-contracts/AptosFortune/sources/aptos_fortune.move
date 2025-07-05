//! MIT License
//!
//! AptosFortune - Premium Slot Machine with Frequent Wins
//!
//! A sophisticated 3-reel slot machine featuring:
//! - Partial match payouts (frequent wins)
//! - 5 premium symbols with weighted probabilities
//! - 22% house edge for sustainable treasury growth
//! - Betting range: 0.1 to 1 APT
//! - Maximum payout: 20x (20 APT)

module aptos_fortune::AptosFortune {
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin;
    use casino::CasinoHouse::{Self, GameCapability};

    //
    // Error Codes
    //

    /// Invalid bet amount
    const E_INVALID_AMOUNT: u64 = 0x01;
    /// Unauthorized access
    const E_UNAUTHORIZED: u64 = 0x02;
    /// Game not registered yet
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    /// Game already initialized
    const E_ALREADY_INITIALIZED: u64 = 0x04;
    /// Game not ready for play
    const E_NOT_READY: u64 = 0x05;

    //
    // Game Constants
    //

    /// Minimum bet: 0.1 APT in octas
    const MIN_BET: u64 = 10000000;
    /// Maximum bet: 1 APT in octas
    const MAX_BET: u64 = 100000000;
    /// House edge: 22% (2200 basis points)
    const HOUSE_EDGE_BPS: u64 = 2200;
    /// Maximum payout: 20x bet (20 APT max)
    const MAX_PAYOUT: u64 = 2000000000;
    /// Game version
    const GAME_VERSION: vector<u8> = b"v1";

    //
    // Symbol Weights & Probabilities
    //

    /// Cherry weight: 35% (0-34)
    const CHERRY_WEIGHT: u8 = 35;
    /// Bell weight: 30% (35-64)
    const BELL_WEIGHT: u8 = 30;
    /// Coin weight: 25% (65-89)
    const COIN_WEIGHT: u8 = 25;
    /// Star weight: 8% (90-97)
    const STAR_WEIGHT: u8 = 8;
    /// Diamond weight: 2% (98-99)
    const DIAMOND_WEIGHT: u8 = 2;

    /// Pre-computed thresholds for gas efficiency
    const CHERRY_TO_BELL_TOTAL: u8 = 65;  // 35 + 30
    const CHERRY_TO_COIN_TOTAL: u8 = 90;  // 35 + 30 + 25
    const CHERRY_TO_STAR_TOTAL: u8 = 98;  // 35 + 30 + 25 + 8

    //
    // Payout Multipliers
    //

    /// 3 matching symbols payouts
    const CHERRY_PAYOUT_3X: u64 = 3;   // 3x bet
    const BELL_PAYOUT_3X: u64 = 4;     // 4x bet
    const COIN_PAYOUT_3X: u64 = 6;     // 6x bet
    const STAR_PAYOUT_3X: u64 = 12;    // 12x bet
    const DIAMOND_PAYOUT_3X: u64 = 20; // 20x bet

    /// 2 matching symbols payout (partial return)
    const PARTIAL_PAYOUT_2X: u64 = 50; // 0.5x bet (50% in basis points)

    /// 1 matching symbol payout (consolation)
    const CONSOLATION_PAYOUT_1X: u64 = 10; // 0.1x bet (10% in basis points)

    //
    // Symbol Constants
    //

    const SYMBOL_CHERRY: u8 = 1;
    const SYMBOL_BELL: u8 = 2;
    const SYMBOL_COIN: u8 = 3;
    const SYMBOL_STAR: u8 = 4;
    const SYMBOL_DIAMOND: u8 = 5;

    //
    // Resources
    //

    /// Game registry at module address
    struct GameRegistry has key {
        creator: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Game authorization stored at object address
    struct GameAuth has key {
        capability: GameCapability,
        extend_ref: ExtendRef
    }

    /// Player result storage for UI display
    struct PlayerResult has key, drop {
        /// Last spin results
        reel1: u8,
        reel2: u8,
        reel3: u8,
        /// Match type (0=no match, 1=one match, 2=two match, 3=three match)
        match_type: u8,
        /// Matching symbol (0 if no match)
        matching_symbol: u8,
        /// Payout received
        payout: u64,
        /// Session identifier
        session_id: u64,
        /// Bet amount
        bet_amount: u64
    }

    //
    // Events
    //

    #[event]
    /// Emitted when reels are spun and outcome determined
    struct SpinResultEvent has drop, store {
        /// Player address
        player: address,
        /// Reel 1 result
        reel1: u8,
        /// Reel 2 result
        reel2: u8,
        /// Reel 3 result
        reel3: u8,
        /// Match type (0=no match, 1=one match, 2=two match, 3=three match)
        match_type: u8,
        /// Matching symbol (0 if no match)
        matching_symbol: u8,
        /// Bet amount
        bet_amount: u64,
        /// Payout amount
        payout: u64,
        /// Session identifier
        session_id: u64,
        /// Treasury address used
        treasury_address: address
    }

    #[event]
    /// Emitted when game initializes successfully
    struct GameInitialized has drop, store {
        creator: address,
        object_address: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    #[event]
    /// Emitted when player clears their result
    struct ResultCleared has drop, store {
        player: address,
        session_id: u64
    }

    //
    // Initialization
    //

    /// Initialize AptosFortune game with casino registration
    public entry fun initialize_game(game_admin: &signer) {
        assert!(signer::address_of(game_admin) == @aptos_fortune, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@aptos_fortune), E_ALREADY_INITIALIZED);

        // Derive the game object that casino should have created
        let game_name = string::utf8(b"AptosFortune");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr = CasinoHouse::derive_game_object_address(
            @casino, game_name, version
        );
        let game_object: Object<CasinoHouse::GameMetadata> = 
            object::address_to_object(game_object_addr);

        // Verify game object exists (casino must register first)
        assert!(object::is_object(game_object_addr), E_GAME_NOT_REGISTERED);

        // Get game capability from casino
        let capability = CasinoHouse::get_game_capability(game_admin, game_object);

        // Store game registry at module address
        move_to(game_admin, GameRegistry {
            creator: @aptos_fortune,
            game_object,
            game_name,
            version
        });

        // Create named object for game auth
        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(game_admin, seed);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        // Store game auth at object address
        move_to(&object_signer, GameAuth {
            capability,
            extend_ref
        });

        // Emit initialization event
        event::emit(GameInitialized {
            creator: @aptos_fortune,
            object_address: object::address_from_constructor_ref(&constructor_ref),
            game_object,
            game_name,
            version
        });
    }

    //
    // Game Logic
    //

    #[randomness]
    entry fun spin_reels(player: &signer, bet_amount: u64) acquires GameRegistry, GameAuth, PlayerResult {
        // Validate bet amount
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        // Verify game is ready
        assert!(is_ready(), E_NOT_READY);

        let player_addr = signer::address_of(player);
        let session_id = account::get_sequence_number(player_addr);

        // Withdraw bet as FungibleAsset from player
        let aptos_metadata_option = coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get capability from object
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Casino creates and returns bet_id
        let (treasury_source, bet_id) = CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Generate random symbols for each reel
        let reel1 = generate_symbol();
        let reel2 = generate_symbol();
        let reel3 = generate_symbol();

        // Calculate payout and match type
        let (payout, match_type, matching_symbol) = calculate_payout(
            reel1, reel2, reel3, bet_amount
        );

        // Settle bet (BetId gets consumed here)
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            payout,
            treasury_source
        );

        // Store result for player
        let player_result = PlayerResult {
            reel1,
            reel2,
            reel3,
            match_type,
            matching_symbol,
            payout,
            session_id,
            bet_amount
        };

        if (exists<PlayerResult>(player_addr)) {
            move_from<PlayerResult>(player_addr);
        };
        move_to(player, player_result);

        // Emit spin event
        event::emit(SpinResultEvent {
            player: player_addr,
            reel1,
            reel2,
            reel3,
            match_type,
            matching_symbol,
            bet_amount,
            payout,
            session_id,
            treasury_address: treasury_source
        });
    }

    //
    // Private Helper Functions
    //

    /// Generate a random symbol based on weighted probabilities
    fun generate_symbol(): u8 {
        let rand_value = randomness::u8_range(0, 100);
        
        if (rand_value < CHERRY_WEIGHT) {
            SYMBOL_CHERRY
        } else if (rand_value < CHERRY_TO_BELL_TOTAL) {
            SYMBOL_BELL
        } else if (rand_value < CHERRY_TO_COIN_TOTAL) {
            SYMBOL_COIN
        } else if (rand_value < CHERRY_TO_STAR_TOTAL) {
            SYMBOL_STAR
        } else {
            SYMBOL_DIAMOND
        }
    }

    /// Calculate payout based on symbol combination
    fun calculate_payout(reel1: u8, reel2: u8, reel3: u8, bet: u64): (u64, u8, u8) {
        // Check for 3 matching symbols
        if (reel1 == reel2 && reel2 == reel3) {
            let multiplier = if (reel1 == SYMBOL_CHERRY) {
                CHERRY_PAYOUT_3X
            } else if (reel1 == SYMBOL_BELL) {
                BELL_PAYOUT_3X
            } else if (reel1 == SYMBOL_COIN) {
                COIN_PAYOUT_3X
            } else if (reel1 == SYMBOL_STAR) {
                STAR_PAYOUT_3X
            } else if (reel1 == SYMBOL_DIAMOND) {
                DIAMOND_PAYOUT_3X
            } else {
                0
            };
            return (bet * multiplier, 3, reel1)
        };

        // Check for 2 matching symbols
        let (match_count, matching_symbol) = count_matches(reel1, reel2, reel3);
        if (match_count == 2) {
            let payout = (bet * PARTIAL_PAYOUT_2X) / 100;
            return (payout, 2, matching_symbol)
        };

        // Check for 1 matching symbol (consolation)
        if (match_count == 1) {
            let payout = (bet * CONSOLATION_PAYOUT_1X) / 100;
            return (payout, 1, matching_symbol)
        };

        // No matches
        (0, 0, 0)
    }

    /// Count matching symbols and return most frequent
    fun count_matches(reel1: u8, reel2: u8, reel3: u8): (u8, u8) {
        if (reel1 == reel2 || reel1 == reel3) {
            (2, reel1)
        } else if (reel2 == reel3) {
            (2, reel2)
        } else {
            // For consolation, return the highest value symbol
            let max_symbol = if (reel1 > reel2 && reel1 > reel3) {
                reel1
            } else if (reel2 > reel3) {
                reel2
            } else {
                reel3
            };
            (1, max_symbol)
        }
    }

    //
    // Helper Functions
    //

    /// Build seed for deterministic object creation
    fun build_seed(name: String, version: String): vector<u8> {
        let seed = *string::bytes(&name);
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *string::bytes(&version));
        seed
    }

    //
    // Public View Functions
    //

    #[view]
    public fun is_ready(): bool acquires GameRegistry {
        if (!exists<GameRegistry>(@aptos_fortune)) { false }
        else {
            let registry = borrow_global<GameRegistry>(@aptos_fortune);
            CasinoHouse::is_game_registered(registry.game_object)
        }
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@aptos_fortune);
        let seed = build_seed(registry.game_name, registry.version);
        object::create_object_address(&registry.creator, seed)
    }

    #[view]
    public fun get_player_result(player: address): (u8, u8, u8, u8, u8, u64, u64, u64) acquires PlayerResult {
        if (!exists<PlayerResult>(player)) {
            return (0, 0, 0, 0, 0, 0, 0, 0)
        };
        let result = borrow_global<PlayerResult>(player);
        (
            result.reel1,
            result.reel2,
            result.reel3,
            result.match_type,
            result.matching_symbol,
            result.payout,
            result.session_id,
            result.bet_amount
        )
    }

    #[view]
    public fun get_game_info(): (address, Object<CasinoHouse::GameMetadata>, String, String) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@aptos_fortune);
        (registry.creator, registry.game_object, registry.game_name, registry.version)
    }

    #[view]
    public fun get_casino_game_object(): Object<CasinoHouse::GameMetadata> acquires GameRegistry {
        borrow_global<GameRegistry>(@aptos_fortune).game_object
    }

    #[view]
    public fun get_symbol_name(symbol: u8): vector<u8> {
        if (symbol == SYMBOL_CHERRY) {
            b"Cherry"
        } else if (symbol == SYMBOL_BELL) {
            b"Bell"
        } else if (symbol == SYMBOL_COIN) {
            b"Coin"
        } else if (symbol == SYMBOL_STAR) {
            b"Star"
        } else if (symbol == SYMBOL_DIAMOND) {
            b"Diamond"
        } else {
            b"Unknown"
        }
    }

    #[view]
    public fun get_symbol_char(symbol: u8): vector<u8> {
        if (symbol == SYMBOL_CHERRY) {
            b"C"
        } else if (symbol == SYMBOL_BELL) {
            b"B"
        } else if (symbol == SYMBOL_COIN) {
            b"O"
        } else if (symbol == SYMBOL_STAR) {
            b"S"
        } else if (symbol == SYMBOL_DIAMOND) {
            b"D"
        } else {
            b"?"
        }
    }

    #[view]
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, HOUSE_EDGE_BPS, MAX_PAYOUT)
    }

    #[view]
    public fun get_symbol_probabilities(): (u8, u8, u8, u8, u8) {
        (CHERRY_WEIGHT, BELL_WEIGHT, COIN_WEIGHT, STAR_WEIGHT, DIAMOND_WEIGHT)
    }

    #[view]
    public fun get_payout_table(): (u64, u64, u64, u64, u64, u64, u64) {
        (
            CHERRY_PAYOUT_3X,
            BELL_PAYOUT_3X,
            COIN_PAYOUT_3X,
            STAR_PAYOUT_3X,
            DIAMOND_PAYOUT_3X,
            PARTIAL_PAYOUT_2X,
            CONSOLATION_PAYOUT_1X
        )
    }

    #[view]
    public fun calculate_potential_payout(bet_amount: u64, symbol: u8, match_type: u8): u64 {
        if (match_type == 3) {
            let multiplier = if (symbol == SYMBOL_CHERRY) {
                CHERRY_PAYOUT_3X
            } else if (symbol == SYMBOL_BELL) {
                BELL_PAYOUT_3X
            } else if (symbol == SYMBOL_COIN) {
                COIN_PAYOUT_3X
            } else if (symbol == SYMBOL_STAR) {
                STAR_PAYOUT_3X
            } else if (symbol == SYMBOL_DIAMOND) {
                DIAMOND_PAYOUT_3X
            } else {
                0
            };
            bet_amount * multiplier
        } else if (match_type == 2) {
            (bet_amount * PARTIAL_PAYOUT_2X) / 100
        } else if (match_type == 1) {
            (bet_amount * CONSOLATION_PAYOUT_1X) / 100
        } else {
            0
        }
    }

    //
    // Player Management
    //

    public entry fun clear_result(player: &signer) acquires PlayerResult {
        let player_addr = signer::address_of(player);
        if (exists<PlayerResult>(player_addr)) {
            let result = move_from<PlayerResult>(player_addr);
            let session_id = result.session_id; // Extract session_id before result is consumed
            event::emit(ResultCleared {
                player: player_addr,
                session_id
            });
        };
    }

    //
    // Testing Functions
    //

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun test_only_spin_reels(player: &signer, bet_amount: u64) acquires GameRegistry, GameAuth, PlayerResult {
        spin_reels(player, bet_amount);
    }

    #[test_only]
    public entry fun test_spin_reels(
        player: &signer, 
        bet_amount: u64, 
        reel1: u8, 
        reel2: u8, 
        reel3: u8
    ) acquires GameRegistry, GameAuth, PlayerResult {
        // Validate bet amount
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);
        let session_id = account::get_sequence_number(player_addr);

        // Withdraw bet as FungibleAsset from player
        let aptos_metadata_option = coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get capability from object
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Casino creates and returns bet_id
        let (treasury_source, bet_id) = CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Use provided reel values
        let (payout, match_type, matching_symbol) = calculate_payout(
            reel1, reel2, reel3, bet_amount
        );

        // Settle bet (BetId gets consumed here)
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            payout,
            treasury_source
        );

        // Store result for player
        let player_result = PlayerResult {
            reel1,
            reel2,
            reel3,
            match_type,
            matching_symbol,
            payout,
            session_id,
            bet_amount
        };

        if (exists<PlayerResult>(player_addr)) {
            move_from<PlayerResult>(player_addr);
        };
        move_to(player, player_result);

        // Emit spin event
        event::emit(SpinResultEvent {
            player: player_addr,
            reel1,
            reel2,
            reel3,
            match_type,
            matching_symbol,
            bet_amount,
            payout,
            session_id,
            treasury_address: treasury_source
        });
    }

    #[test_only]
    public fun initialize_game_for_test(game_admin: &signer) {
        initialize_game(game_admin);
    }
}
