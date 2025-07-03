//! MIT License
//!
//! European Roulette Game for ChainCasino Platform (Block-STM Compatible)
//!
//! European roulette with 37 numbers (0-36) and single number betting.
//! Enhanced with immediate result storage for optimal frontend UX.

module roulette_game::AptosRoulette {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
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

    //
    // Constants
    //

    /// European roulette numbers (0-36)
    const MAX_ROULETTE_NUMBER: u8 = 36;
    /// Single number payout multiplier (35:1)
    const SINGLE_NUMBER_PAYOUT: u64 = 35;
    /// Minimum bet amount (0.01 APT in octas)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.3 APT in octas) - conservative for 35:1 payout
    const MAX_BET: u64 = 30000000;
    /// House edge in basis points (270 = 2.70% for European roulette)
    const HOUSE_EDGE_BPS: u64 = 270;
    /// Game version for object naming
    const GAME_VERSION: vector<u8> = b"v1";

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

    /// User's latest spin result stored at their address for immediate frontend access
    struct SpinResult has key {
        /// The number that won (0-36)
        winning_number: u8,
        /// The number the player bet on
        bet_number: u8,
        /// Amount wagered in octas
        bet_amount: u64,
        /// Payout received (0 if lost)
        payout: u64,
        /// When the spin occurred
        timestamp: u64,
        /// Session identifier for frontend state management
        session_id: u64,
        /// Whether player won this spin
        won: bool
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when roulette wheel is spun and bet is resolved
    struct RouletteSpinEvent has drop, store {
        player: address,
        bet_number: u8,
        winning_number: u8,
        bet_amount: u64,
        won: bool,
        payout: u64,
        treasury_used: address,
        session_id: u64
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
        payout_multiplier: u64,
        house_edge_bps: u64
    }

    #[event]
    /// Emitted when user cleans their spin result
    struct ResultCleanedEvent has drop, store {
        player: address,
        session_id: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize roulette game with named object - claims capability from casino
    public entry fun initialize_game(roulette_admin: &signer) {
        assert!(signer::address_of(roulette_admin) == @roulette_game, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@roulette_game), E_ALREADY_INITIALIZED);

        // Derive the game object that casino should have created
        let game_name = string::utf8(b"AptosRoulette");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr =
            CasinoHouse::derive_game_object_address(@casino, game_name, version);
        let game_object: Object<CasinoHouse::GameMetadata> =
            object::address_to_object(game_object_addr);

        // Verify game object exists
        assert!(CasinoHouse::game_object_exists(game_object), E_GAME_NOT_REGISTERED);

        // Create named object for game instance
        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(roulette_admin, seed);
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
        let capability = CasinoHouse::get_game_capability(roulette_admin, game_object);

        // Store GameAuth in the object
        move_to(&object_signer, GameAuth { capability, extend_ref });

        // Store registry info at module address for easy lookup
        move_to(
            roulette_admin,
            GameRegistry {
                creator: signer::address_of(roulette_admin),
                game_object,
                game_name,
                version
            }
        );

        event::emit(
            GameInitialized {
                creator: signer::address_of(roulette_admin),
                object_address: object_addr,
                game_object,
                game_name,
                version,
                min_bet: MIN_BET,
                max_bet: MAX_BET,
                payout_multiplier: SINGLE_NUMBER_PAYOUT,
                house_edge_bps: HOUSE_EDGE_BPS
            }
        );
    }

    //
    // Core Game Interface
    //

    #[randomness]
    /// Spin the European roulette wheel - stores result at user address for immediate frontend access
    entry fun spin_roulette(
        player: &signer, bet_number: u8, bet_amount: u64
    ) acquires GameRegistry, GameAuth, SpinResult {
        assert!(bet_number <= MAX_ROULETTE_NUMBER, E_INVALID_NUMBER);
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Auto-cleanup: Remove previous result to prevent storage bloat
        if (exists<SpinResult>(player_addr)) {
            let old_result = move_from<SpinResult>(player_addr);
            // Old result properly destructured and dropped
            let SpinResult { 
                winning_number: _, bet_number: _, bet_amount: _, payout: _, 
                timestamp: _, session_id: _, won: _ 
            } = old_result;
        };

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

        // Spin the roulette wheel with secure randomness (0-36 for European)
        let winning_number = randomness::u8_range(0, 37); // 0 to 36 inclusive

        // Calculate payout
        let player_won = winning_number == bet_number;
        let payout =
            if (player_won) {
                bet_amount * SINGLE_NUMBER_PAYOUT
            } else { 0 };

        // Settle bet (BetId gets consumed here)
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            payout,
            treasury_source
        );

        // Generate session ID for frontend state management
        let current_time = timestamp::now_seconds();
        let session_id = account::get_sequence_number(player_addr);  // Unique per user transaction

        // Store result at user address for immediate frontend access
        let spin_result = SpinResult {
            winning_number,
            bet_number,
            bet_amount,
            payout,
            timestamp: current_time,
            session_id,
            won: player_won
        };
        move_to(player, spin_result);

        // Emit event for indexing/analytics (traditional event)
        event::emit(
            RouletteSpinEvent {
                player: player_addr,
                bet_number,
                winning_number,
                bet_amount,
                won: player_won,
                payout,
                treasury_used: treasury_source,
                session_id
            }
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Test version allowing unsafe randomness
    public entry fun test_only_spin_roulette(
        player: &signer, bet_number: u8, bet_amount: u64
    ) acquires GameRegistry, GameAuth, SpinResult {
        spin_roulette(player, bet_number, bet_amount);
    }

    //
    // Result Management Interface
    //

    /// User can manually clear their spin result to clean up storage
    public entry fun clear_spin_result(user: &signer) acquires SpinResult {
        let user_addr = signer::address_of(user);
        if (exists<SpinResult>(user_addr)) {
            let result = move_from<SpinResult>(user_addr);
            let session_id = result.session_id;
            
            // Properly destructure the resource
            let SpinResult { 
                winning_number: _, bet_number: _, bet_amount: _, payout: _, 
                timestamp: _, session_id: _, won: _ 
            } = result;
            
            event::emit(ResultCleanedEvent { player: user_addr, session_id });
        };
    }

    //
    // Game Configuration Management
    //

    /// Request betting limit changes (games can only reduce risk)
    public entry fun request_limit_update(
        game_admin: &signer, new_min_bet: u64, new_max_bet: u64
    ) acquires GameRegistry, GameAuth {
        assert!(signer::address_of(game_admin) == @roulette_game, E_UNAUTHORIZED);
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
    // Frontend-Optimized View Functions
    //

    #[view]
    /// Get user's latest spin result - PRIMARY FRONTEND FUNCTION
    /// Returns: (winning_number, bet_number, bet_amount, payout, won, timestamp, session_id)
    public fun get_user_spin_result(player_addr: address): (u8, u8, u64, u64, bool, u64, u64) acquires SpinResult {
        assert!(exists<SpinResult>(player_addr), E_INVALID_AMOUNT);
        
        let result = borrow_global<SpinResult>(player_addr);
        (
            result.winning_number,
            result.bet_number,
            result.bet_amount,
            result.payout,
            result.won,
            result.timestamp,
            result.session_id
        )
    }

    #[view]
    /// Check if user has a spin result available
    public fun has_spin_result(player_addr: address): bool {
        exists<SpinResult>(player_addr)
    }

    #[view]
    /// Get only the essential result data for quick frontend updates
    /// Returns: (winning_number, won, payout)
    public fun get_quick_result(player_addr: address): (u8, bool, u64) acquires SpinResult {
        assert!(exists<SpinResult>(player_addr), E_INVALID_AMOUNT);
        
        let result = borrow_global<SpinResult>(player_addr);
        (result.winning_number, result.won, result.payout)
    }

    #[view]
    /// Get session info for frontend state management
    /// Returns: (session_id, timestamp)
    public fun get_session_info(player_addr: address): (u64, u64) acquires SpinResult {
        assert!(exists<SpinResult>(player_addr), E_INVALID_AMOUNT);
        
        let result = borrow_global<SpinResult>(player_addr);
        (result.session_id, result.timestamp)
    }

    //
    // Standard View Functions
    //

    #[view]
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, SINGLE_NUMBER_PAYOUT, HOUSE_EDGE_BPS)
    }

    #[view]
    public fun calculate_single_number_payout(bet_amount: u64): u64 {
        bet_amount * SINGLE_NUMBER_PAYOUT
    }

    #[view]
    public fun is_valid_roulette_number(number: u8): bool {
        number <= MAX_ROULETTE_NUMBER
    }

    #[view]
    public fun get_roulette_range(): (u8, u8) {
        (0, MAX_ROULETTE_NUMBER)
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let seed = build_seed(registry.game_name, registry.version);
        object::create_object_address(&registry.creator, seed)
    }

    #[view]
    public fun get_casino_game_object(): Object<CasinoHouse::GameMetadata> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
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
        let registry = borrow_global<GameRegistry>(@roulette_game);
        (registry.creator, registry.game_object, registry.game_name, registry.version)
    }

    #[view]
    /// Check if game treasury has sufficient balance for a bet
    public fun can_handle_payout(bet_amount: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let expected_payout = bet_amount * SINGLE_NUMBER_PAYOUT;
        let game_treasury_balance =
            CasinoHouse::game_treasury_balance(registry.game_object);

        // Game can handle if treasury has enough or central will cover
        game_treasury_balance >= expected_payout
            || CasinoHouse::central_treasury_balance() >= expected_payout
    }

    #[view]
    /// Get game treasury balance
    public fun game_treasury_balance(): u64 acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        CasinoHouse::game_treasury_balance(registry.game_object)
    }

    #[view]
    /// Get game treasury address
    public fun game_treasury_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        CasinoHouse::get_game_treasury_address(registry.game_object)
    }

    #[view]
    /// Get game treasury configuration
    public fun game_treasury_config(): (u64, u64, u64, u64) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@roulette_game);
        let treasury_addr = CasinoHouse::get_game_treasury_address(registry.game_object);
        CasinoHouse::get_game_treasury_config(treasury_addr)
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
    public fun object_exists(): bool acquires GameRegistry {
        if (!is_initialized()) { false }
        else {
            let object_addr = get_game_object_address();
            exists<GameAuth>(object_addr)
        }
    }

    #[view]
    /// Get European roulette wheel layout information
    public fun get_wheel_info(): (u8, String, u64) {
        (MAX_ROULETTE_NUMBER + 1, string::utf8(b"European"), SINGLE_NUMBER_PAYOUT) // 37 numbers, European, 35:1
    }
}
