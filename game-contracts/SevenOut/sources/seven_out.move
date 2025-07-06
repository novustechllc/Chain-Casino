//! MIT License
//!
//! Seven Out Dice Game for ChainCasino Platform
//!
//! Classic Over/Under 7 dice game with two dice. Players bet whether the sum
//! will be over or under 7. Sum of exactly 7 is a push (bet returned).

module seven_out_game::SevenOut {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::timestamp;
    use aptos_framework::account;
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

    /// Invalid bet type
    const E_INVALID_BET_TYPE: u64 = 0x01;
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

    /// Minimum bet amount (0.02 APT in octas)
    const MIN_BET: u64 = 2000000;
    /// Maximum bet amount (0.4 APT in octas)
    const MAX_BET: u64 = 40000000;
    /// Payout multiplier for Over/Under wins (2:1)
    const PAYOUT_MULTIPLIER: u64 = 2;
    /// House edge in basis points (278 = 2.78%)
    const HOUSE_EDGE_BPS: u64 = 278;
    /// Game version for object naming
    const GAME_VERSION: vector<u8> = b"v1";

    //
    // Types
    //

    /// Betting options for Seven Out game
    enum BetType has copy, drop, store {
        Over, // Bet that dice sum > 7
        Under // Bet that dice sum < 7
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

    /// User's latest game result stored at their address
    struct GameResult has key {
        /// First die result (1-6)
        die1: u8,
        /// Second die result (1-6)
        die2: u8,
        /// Sum of both dice
        dice_sum: u8,
        /// The bet type (Over/Under)
        bet_type: BetType,
        /// Amount wagered in octas
        bet_amount: u64,
        /// Payout received (0 if lost, bet_amount if push)
        payout: u64,
        /// When the game occurred
        timestamp: u64,
        /// Session identifier for frontend state management
        session_id: u64,
        /// Game outcome
        outcome: u8 // 0 = lose, 1 = win, 2 = push
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when dice are rolled and bet is resolved
    struct SevenOutEvent has drop, store {
        player: address,
        die1: u8,
        die2: u8,
        dice_sum: u8,
        bet_type_over: bool, // true if Over, false if Under
        bet_amount: u64,
        outcome: u8, // 0 = lose, 1 = win, 2 = push
        payout: u64,
        treasury_used: address,
        session_id: u64
    }

    #[event]
    /// Emitted when game successfully initializes
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
    /// Emitted when user clears their game result
    struct ResultCleanedEvent has drop, store {
        player: address,
        session_id: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize Seven Out game with named object
    public entry fun initialize_game(game_admin: &signer) {
        assert!(signer::address_of(game_admin) == @seven_out_game, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@seven_out_game), E_ALREADY_INITIALIZED);

        // Derive the game object that casino should have created
        let game_name = string::utf8(b"SevenOut");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr =
            CasinoHouse::derive_game_object_address(@casino, game_name, version);
        let game_object: Object<CasinoHouse::GameMetadata> =
            object::address_to_object(game_object_addr);

        // Verify game object exists
        assert!(CasinoHouse::game_object_exists(game_object), E_GAME_NOT_REGISTERED);

        // Create named object for game instance
        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(game_admin, seed);
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
        let capability = CasinoHouse::get_game_capability(game_admin, game_object);

        // Store GameAuth in the object
        move_to(&object_signer, GameAuth { capability, extend_ref });

        // Store registry info at module address for easy lookup
        move_to(
            game_admin,
            GameRegistry {
                creator: signer::address_of(game_admin),
                game_object,
                game_name,
                version
            }
        );

        event::emit(
            GameInitialized {
                creator: signer::address_of(game_admin),
                object_address: object_addr,
                game_object,
                game_name,
                version,
                min_bet: MIN_BET,
                max_bet: MAX_BET,
                payout_multiplier: PAYOUT_MULTIPLIER,
                house_edge_bps: HOUSE_EDGE_BPS
            }
        );
    }

    //
    // Core Game Interface
    //

    #[randomness]
    /// Play Seven Out - roll two dice and bet Over or Under 7
    /// bet_over: true for Over (>7), false for Under (<7)
    entry fun play_seven_out(
        player: &signer, bet_over: bool, bet_amount: u64
    ) acquires GameRegistry, GameAuth, GameResult {
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Convert boolean to enum inside module
        let bet_type =
            if (bet_over) {
                BetType::Over
            } else {
                BetType::Under
            };

        // Auto-cleanup: Remove previous result to prevent storage bloat
        if (exists<GameResult>(player_addr)) {
            let old_result = move_from<GameResult>(player_addr);
            // Old result properly destructured and dropped
            let GameResult {
                die1: _,
                die2: _,
                dice_sum: _,
                bet_type: _,
                bet_amount: _,
                payout: _,
                timestamp: _,
                session_id: _,
                outcome: _
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

        // Roll two dice with secure randomness
        let die1 = randomness::u8_range(1, 7); // 1-6
        let die2 = randomness::u8_range(1, 7); // 1-6
        let dice_sum = die1 + die2;

        // Determine outcome
        let (outcome, payout) =
            if (dice_sum == 7) {
                (2, bet_amount) // Push - return bet
            } else if (bet_type == BetType::Over) {
                if (dice_sum > 7) {
                    (1, bet_amount * PAYOUT_MULTIPLIER) // Win
                } else {
                    (0, 0) // Lose
                }
            } else { // Under
                if (dice_sum < 7) {
                    (1, bet_amount * PAYOUT_MULTIPLIER) // Win
                } else {
                    (0, 0) // Lose
                }
            };

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
        let session_id = account::get_sequence_number(player_addr);

        // Store result at user address for immediate frontend access
        let game_result = GameResult {
            die1,
            die2,
            dice_sum,
            bet_type,
            bet_amount,
            payout,
            timestamp: current_time,
            session_id,
            outcome
        };
        move_to(player, game_result);

        // Emit event for indexing/analytics
        event::emit(
            SevenOutEvent {
                player: player_addr,
                die1,
                die2,
                dice_sum,
                bet_type_over: (bet_type == BetType::Over),
                bet_amount,
                outcome,
                payout,
                treasury_used: treasury_source,
                session_id
            }
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Test version allowing unsafe randomness
    /// bet_over: true for Over (>7), false for Under (<7)
    public entry fun test_only_play_seven_out(
        player: &signer, bet_over: bool, bet_amount: u64
    ) acquires GameRegistry, GameAuth, GameResult {
        play_seven_out(player, bet_over, bet_amount);
    }

    //
    // Result Management Interface
    //

    /// User can manually clear their game result
    public entry fun clear_game_result(user: &signer) acquires GameResult {
        let user_addr = signer::address_of(user);
        if (exists<GameResult>(user_addr)) {
            let result = move_from<GameResult>(user_addr);
            let session_id = result.session_id;

            // Properly destructure the resource
            let GameResult {
                die1: _,
                die2: _,
                dice_sum: _,
                bet_type: _,
                bet_amount: _,
                payout: _,
                timestamp: _,
                session_id: _,
                outcome: _
            } = result;

            event::emit(ResultCleanedEvent { player: user_addr, session_id });
        };
    }

    //
    // Game Configuration Management
    //

    /// Request betting limit changes
    public entry fun request_limit_update(
        game_admin: &signer, new_min_bet: u64, new_max_bet: u64
    ) acquires GameRegistry, GameAuth {
        assert!(signer::address_of(game_admin) == @seven_out_game, E_UNAUTHORIZED);
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
    // Helper Functions
    //

    #[test_only]
    /// Create Over bet type for testing
    public fun bet_type_over(): BetType {
        BetType::Over
    }

    #[test_only]
    /// Create Under bet type for testing
    public fun bet_type_under(): BetType {
        BetType::Under
    }

    #[test_only]
    /// Simulate game outcome for testing
    public fun test_simulate_win(dice_sum: u8, bet_type: BetType): bool {
        if (dice_sum == 7) {
            false // Push is not a win
        } else if (bet_type == BetType::Over) {
            dice_sum > 7
        } else {
            dice_sum < 7
        }
    }

    //
    // View Functions
    //

    #[view]
    /// Get user's latest game result
    public fun get_user_game_result(
        player_addr: address
    ): (u8, u8, u8, BetType, u64, u64, u64, u64, u8) acquires GameResult {
        assert!(exists<GameResult>(player_addr), E_INVALID_AMOUNT);

        let result = borrow_global<GameResult>(player_addr);
        (
            result.die1,
            result.die2,
            result.dice_sum,
            result.bet_type,
            result.bet_amount,
            result.payout,
            result.timestamp,
            result.session_id,
            result.outcome
        )
    }

    #[view]
    /// Check if user has a game result available
    public fun has_game_result(player_addr: address): bool {
        exists<GameResult>(player_addr)
    }

    #[view]
    /// Get quick result data for frontend
    public fun get_quick_result(player_addr: address): (u8, u8, u8, u8, u64) acquires GameResult {
        assert!(exists<GameResult>(player_addr), E_INVALID_AMOUNT);

        let result = borrow_global<GameResult>(player_addr);
        (result.die1, result.die2, result.dice_sum, result.outcome, result.payout)
    }

    #[view]
    /// Get session info for frontend state management
    public fun get_session_info(player_addr: address): (u64, u64) acquires GameResult {
        assert!(exists<GameResult>(player_addr), E_INVALID_AMOUNT);

        let result = borrow_global<GameResult>(player_addr);
        (result.session_id, result.timestamp)
    }

    #[view]
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, PAYOUT_MULTIPLIER, HOUSE_EDGE_BPS)
    }

    #[view]
    public fun calculate_payout(bet_amount: u64): u64 {
        bet_amount * PAYOUT_MULTIPLIER
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        let seed = build_seed(registry.game_name, registry.version);
        object::create_object_address(&registry.creator, seed)
    }

    #[view]
    public fun get_casino_game_object(): Object<CasinoHouse::GameMetadata> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        registry.game_object
    }

    #[view]
    public fun get_game_info(): (address, Object<CasinoHouse::GameMetadata>, String, String) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        (registry.creator, registry.game_object, registry.game_name, registry.version)
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameRegistry>(@seven_out_game)
    }

    #[view]
    public fun is_registered(): bool acquires GameRegistry {
        if (!exists<GameRegistry>(@seven_out_game)) { false }
        else {
            let registry = borrow_global<GameRegistry>(@seven_out_game);
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

    #[view]
    /// Get game odds information
    public fun get_game_odds(): (u64, u64, u64) {
        // Over: 21 ways to win out of 36 (58.33%)
        // Under: 15 ways to win out of 36 (41.67%)
        // Push: 6 ways (16.67%)
        (21, 15, 6) // (over_ways, under_ways, push_ways)
    }

    #[view]
    /// Check if game treasury has sufficient balance for a bet
    public fun can_handle_payout(bet_amount: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        let expected_payout = bet_amount * PAYOUT_MULTIPLIER;
        let game_treasury_balance =
            CasinoHouse::game_treasury_balance(registry.game_object);

        // Game can handle if treasury has enough or central will cover
        game_treasury_balance >= expected_payout
            || CasinoHouse::central_treasury_balance() >= expected_payout
    }

    #[view]
    /// Get game treasury balance
    public fun game_treasury_balance(): u64 acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        CasinoHouse::game_treasury_balance(registry.game_object)
    }

    #[view]
    /// Get game treasury address
    public fun game_treasury_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@seven_out_game);
        CasinoHouse::get_game_treasury_address(registry.game_object)
    }
}
