//! MIT License
//!
//! Slot Machine Game for ChainCasino Platform (Block-STM Compatible)
//!
//! 3-reel slot machine with weighted symbols and secure randomness.
//! Uses simplified bet flow with BetId struct.

module casino::SlotMachine {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;

    //
    // Error Codes
    //

    /// Invalid bet amount
    const E_INVALID_AMOUNT: u64 = 0x01;
    /// Unauthorized initialization
    const E_UNAUTHORIZED: u64 = 0x02;
    /// Game not registered by casino yet
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    /// Game already initialized
    const E_ALREADY_INITIALIZED: u64 = 0x04;

    //
    // Constants
    //

    /// Minimum bet amount (0.01 APT in octas)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.5 APT in octas)
    const MAX_BET: u64 = 50000000;
    /// House edge in basis points (1550 = 15.5%)
    const HOUSE_EDGE_BPS: u64 = 1550;
    /// Game version for object naming
    const GAME_VERSION: vector<u8> = b"v1";

    /// Symbol weights for weighted random selection
    const CHERRY_WEIGHT: u8 = 40; // 0-39
    const BELL_WEIGHT: u8 = 30; // 40-69
    const COIN_WEIGHT: u8 = 20; // 70-89
    const CHAIN_WEIGHT: u8 = 8; // 90-97
    const SEVEN_WEIGHT: u8 = 2; // 98-99

    /// Pre-computed weight thresholds for gas optimization
    const CHERRY_TO_BELL_TOTAL: u8 = 70; // CHERRY_WEIGHT + BELL_WEIGHT
    const CHERRY_TO_COIN_TOTAL: u8 = 90; // CHERRY_WEIGHT + BELL_WEIGHT + COIN_WEIGHT
    const CHERRY_TO_CHAIN_TOTAL: u8 = 98; // CHERRY_WEIGHT + BELL_WEIGHT + COIN_WEIGHT + CHAIN_WEIGHT

    /// Payout multipliers for 3 matching symbols
    const CHERRY_PAYOUT: u64 = 1; // 1x bet
    const BELL_PAYOUT: u64 = 2; // 2x bet
    const COIN_PAYOUT: u64 = 5; // 5x bet
    const CHAIN_PAYOUT: u64 = 20; // 20x bet
    const SEVEN_PAYOUT: u64 = 100; // 100x bet

    /// Symbol constants for events and calculations
    const SYMBOL_CHERRY: u8 = 1;
    const SYMBOL_BELL: u8 = 2;
    const SYMBOL_COIN: u8 = 3;
    const SYMBOL_CHAIN: u8 = 4;
    const SYMBOL_SEVEN: u8 = 5;

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

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when slot reels are spun and bet is resolved
    struct SlotSpinEvent has drop, store {
        player: address,
        bet_amount: u64,
        reel1: u8,
        reel2: u8,
        reel3: u8,
        won: bool,
        payout: u64,
        symbol_name: vector<u8>,
        treasury_used: address
    }

    #[event]
    /// Emitted when game successfully initializes with object details
    struct GameInitialized has drop, store {
        creator: address,
        object_address: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize slot machine game with named object - claims capability from casino
    public entry fun initialize_game(slot_admin: &signer) {
        assert!(signer::address_of(slot_admin) == @casino, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@casino), E_ALREADY_INITIALIZED);

        // Derive the game object that casino should have created
        let game_name = string::utf8(b"SlotMachine");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr =
            CasinoHouse::derive_game_object_address(@casino, game_name, version);
        let game_object: Object<CasinoHouse::GameMetadata> =
            object::address_to_object(game_object_addr);

        // Verify game object exists
        assert!(CasinoHouse::game_object_exists(game_object), E_GAME_NOT_REGISTERED);

        // Create named object for game instance
        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(slot_admin, seed);
        let object_signer = object::generate_signer(&constructor_ref);
        let object_addr =
            object::object_address(
                &object::object_from_constructor_ref<ObjectCore>(&constructor_ref)
            );

        // Configure as non-transferable
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        // Generate extend ref for future operations
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Get capability from casino using game object
        let capability = CasinoHouse::get_game_capability(slot_admin, game_object);

        // Store GameAuth in the object
        move_to(&object_signer, GameAuth { capability, extend_ref });

        // Store registry info at module address for easy lookup
        move_to(
            slot_admin,
            GameRegistry {
                creator: signer::address_of(slot_admin),
                game_object,
                game_name,
                version
            }
        );

        event::emit(
            GameInitialized {
                creator: signer::address_of(slot_admin),
                object_address: object_addr,
                game_object,
                game_name,
                version,
                min_bet: MIN_BET,
                max_bet: MAX_BET,
                house_edge_bps: HOUSE_EDGE_BPS
            }
        );
    }

    //
    // Core Game Interface
    //

    #[randomness]
    /// Spin the slot machine reels
    entry fun spin_slots(player: &signer, bet_amount: u64) acquires GameRegistry, GameAuth {
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Withdraw bet as FungibleAsset from player
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get capability from object
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Casino creates and returns bet_id
        let (treasury_source, bet_id) =
            CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Spin the three reels with secure randomness
        let reel1 = spin_reel_internal();
        let reel2 = spin_reel_internal();
        let reel3 = spin_reel_internal();

        // Calculate actual payout
        let (payout_multiplier, symbol_name) =
            calculate_payout_internal(reel1, reel2, reel3);
        let payout = bet_amount * payout_multiplier;
        let player_won = payout_multiplier > 0;

        // Settle bet (BetId gets consumed here)
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            payout,
            treasury_source
        );

        // Game emits own event without bet_id
        event::emit(
            SlotSpinEvent {
                player: player_addr,
                bet_amount,
                reel1,
                reel2,
                reel3,
                won: player_won,
                payout,
                symbol_name,
                treasury_used: treasury_source
            }
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Test version allowing unsafe randomness
    public entry fun test_only_spin_slots(
        player: &signer, bet_amount: u64
    ) acquires GameRegistry, GameAuth {
        spin_slots(player, bet_amount);
    }

    //
    // Internal Game Logic
    //

    #[lint::allow_unsafe_randomness]
    fun spin_reel_internal(): u8 {
        let rand_value = randomness::u8_range(0, 100);

        // Gas-optimized threshold checks using pre-computed constants
        if (rand_value < CHERRY_WEIGHT) {
            SYMBOL_CHERRY
        } else if (rand_value < CHERRY_TO_BELL_TOTAL) {
            SYMBOL_BELL
        } else if (rand_value < CHERRY_TO_COIN_TOTAL) {
            SYMBOL_COIN
        } else if (rand_value < CHERRY_TO_CHAIN_TOTAL) {
            SYMBOL_CHAIN
        } else {
            SYMBOL_SEVEN
        }
    }

    fun calculate_payout_internal(reel1: u8, reel2: u8, reel3: u8): (u64, vector<u8>) {
        if (reel1 == reel2 && reel2 == reel3) {
            if (reel1 == SYMBOL_CHERRY) {
                (CHERRY_PAYOUT, b"Cherry")
            } else if (reel1 == SYMBOL_BELL) {
                (BELL_PAYOUT, b"Bell")
            } else if (reel1 == SYMBOL_COIN) {
                (COIN_PAYOUT, b"Coin")
            } else if (reel1 == SYMBOL_CHAIN) {
                (CHAIN_PAYOUT, b"Chain")
            } else if (reel1 == SYMBOL_SEVEN) {
                (SEVEN_PAYOUT, b"Seven")
            } else {
                (0, b"Unknown")
            }
        } else {
            (0, b"No Match")
        }
    }

    //
    // Game Configuration Management
    //

    /// Request betting limit changes (games can only reduce risk)
    public entry fun request_limit_update(
        game_admin: &signer, new_min_bet: u64, new_max_bet: u64
    ) acquires GameRegistry, GameAuth {
        assert!(signer::address_of(game_admin) == @casino, E_UNAUTHORIZED);
        assert!(new_max_bet >= new_min_bet, E_INVALID_AMOUNT);

        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Games can only reduce risk (increase min or decrease max)
        CasinoHouse::request_limit_update(capability, new_min_bet, new_max_bet);
    }

    //
    // Object Management Functions
    //

    /// Build seed for deterministic object creation
    fun build_seed(name: String, version: String): vector<u8> {
        let seed = *string::bytes(&name);
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *string::bytes(&version));
        seed
    }

    /// Get object signer from stored extend ref
    fun get_object_signer(object_addr: address): signer acquires GameAuth {
        let game_auth = borrow_global<GameAuth>(object_addr);
        object::generate_signer_for_extending(&game_auth.extend_ref)
    }

    //
    // View Functions
    //

    #[view]
    public fun get_game_config(): (u64, u64, u64) {
        (MIN_BET, MAX_BET, HOUSE_EDGE_BPS)
    }

    #[view]
    public fun get_symbol_weights(): (u8, u8, u8, u8, u8) {
        (CHERRY_WEIGHT, BELL_WEIGHT, COIN_WEIGHT, CHAIN_WEIGHT, SEVEN_WEIGHT)
    }

    #[view]
    public fun get_payout_multipliers(): (u64, u64, u64, u64, u64) {
        (CHERRY_PAYOUT, BELL_PAYOUT, COIN_PAYOUT, CHAIN_PAYOUT, SEVEN_PAYOUT)
    }

    #[view]
    public fun calculate_symbol_payout(bet_amount: u64, symbol: u8): u64 {
        let multiplier =
            if (symbol == SYMBOL_CHERRY) {
                CHERRY_PAYOUT
            } else if (symbol == SYMBOL_BELL) {
                BELL_PAYOUT
            } else if (symbol == SYMBOL_COIN) {
                COIN_PAYOUT
            } else if (symbol == SYMBOL_CHAIN) {
                CHAIN_PAYOUT
            } else if (symbol == SYMBOL_SEVEN) {
                SEVEN_PAYOUT
            } else { 0 };

        bet_amount * multiplier
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        let seed = build_seed(registry.game_name, registry.version);
        object::create_object_address(&registry.creator, seed)
    }

    #[view]
    public fun get_casino_game_object(): Object<CasinoHouse::GameMetadata> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        registry.game_object
    }

    #[view]
    /// Derive object address from creator and game details
    public fun derive_game_object_address(
        creator: address, name: String, version: String
    ): address {
        let seed = build_seed(name, version);
        object::create_object_address(&creator, seed)
    }

    #[view]
    public fun get_game_info(): (address, Object<CasinoHouse::GameMetadata>, String, String) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        (registry.creator, registry.game_object, registry.game_name, registry.version)
    }

    #[view]
    /// Check if game treasury has sufficient balance for a bet
    public fun can_handle_payout(bet_amount: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        let expected_payout = bet_amount * SEVEN_PAYOUT; // Max possible payout
        let game_treasury_balance =
            CasinoHouse::game_treasury_balance(registry.game_object);

        // Game can handle if treasury has enough or central will cover
        game_treasury_balance >= expected_payout
            || CasinoHouse::central_treasury_balance() >= expected_payout
    }

    #[view]
    /// Get game treasury balance
    public fun game_treasury_balance(): u64 acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        CasinoHouse::game_treasury_balance(registry.game_object)
    }

    #[view]
    /// Get game treasury address
    public fun game_treasury_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        CasinoHouse::get_game_treasury_address(registry.game_object)
    }

    #[view]
    /// Get game treasury configuration
    public fun game_treasury_config(): (u64, u64, u64, u64) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        let treasury_addr = CasinoHouse::get_game_treasury_address(registry.game_object);
        CasinoHouse::get_game_treasury_config(treasury_addr)
    }

    #[view]
    public fun is_registered(): bool acquires GameRegistry {
        if (!exists<GameRegistry>(@casino)) { false }
        else {
            let registry = borrow_global<GameRegistry>(@casino);
            CasinoHouse::is_game_registered(registry.game_object)
        }
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameRegistry>(@casino)
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

    #[view]
    public fun get_symbol_name(symbol: u8): vector<u8> {
        if (symbol == SYMBOL_CHERRY) {
            b"Cherry"
        } else if (symbol == SYMBOL_BELL) {
            b"Bell"
        } else if (symbol == SYMBOL_COIN) {
            b"Coin"
        } else if (symbol == SYMBOL_CHAIN) {
            b"Chain"
        } else if (symbol == SYMBOL_SEVEN) {
            b"Seven"
        } else {
            b"Unknown"
        }
    }
}
