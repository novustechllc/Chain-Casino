//! MIT License
//!
//! Simple Dice Game for ChainCasino Platform (Object-Based Refactor)
//!
//! Single die guessing game where players bet on the exact outcome (1-6).
//! Now uses named objects for game instance storage instead of fixed addresses.

module dice_game::DiceGame {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use casino::CasinoHouse;
    use casino::CasinoHouse::GameCapability;

    //
    // Error Codes
    //

    /// Invalid guess (must be 1-6)
    const E_INVALID_GUESS: u64 = 0x01;
    /// Invalid bet amount
    const E_INVALID_AMOUNT: u64 = 0x02;
    /// Unauthorized initialization
    const E_UNAUTHORIZED: u64 = 0x03;
    /// Game not registered by casino yet
    const E_GAME_NOT_REGISTERED: u64 = 0x04;
    /// Game already initialized
    const E_ALREADY_INITIALIZED: u64 = 0x05;
    /// Game object does not exist
    const E_GAME_OBJECT_NOT_EXISTS: u64 = 0x06;

    //
    // Constants
    //

    /// Payout multiplier for correct guess
    const PAYOUT_MULTIPLIER: u64 = 5;
    /// Minimum bet amount (0.01 APT in octas)
    const MIN_BET: u64 = 1000000;
    /// Maximum bet amount (0.5 APT in octas)
    const MAX_BET: u64 = 50000000;
    /// House edge in basis points (1667 = 16.67%)
    const HOUSE_EDGE_BPS: u64 = 1667;
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
        object_address: address,
        game_name: String,
        version: String
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when dice is rolled and bet is resolved
    struct DiceRolled has drop, store {
        bet_id: u64,
        player: address,
        guess: u8,
        result: u8,
        bet_amount: u64,
        won: bool,
        payout: u64
    }

    #[event]
    /// Emitted when game successfully initializes with object details
    struct GameInitialized has drop, store {
        creator: address,
        object_address: address,
        game_name: String,
        version: String,
        min_bet: u64,
        max_bet: u64,
        payout_multiplier: u64,
        house_edge_bps: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize dice game with named object - claims capability from casino
    public entry fun initialize_game(dice_admin: &signer) {
        assert!(signer::address_of(dice_admin) == @dice_game, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@dice_game), E_ALREADY_INITIALIZED);
        assert!(CasinoHouse::is_game_registered(@dice_game), E_GAME_NOT_REGISTERED);

        // Create named object for game instance
        let game_name = string::utf8(b"DiceGame");
        let version = string::utf8(GAME_VERSION);
        let seed = build_seed(game_name, version);

        let constructor_ref = object::create_named_object(dice_admin, seed);
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

        // Get capability from casino
        let capability = CasinoHouse::get_game_capability(dice_admin);

        // Store GameAuth in the object
        move_to(&object_signer, GameAuth { capability, extend_ref });

        // Store registry info at module address for easy lookup
        move_to(
            dice_admin,
            GameRegistry {
                creator: signer::address_of(dice_admin),
                object_address: object_addr,
                game_name,
                version
            }
        );

        event::emit(
            GameInitialized {
                creator: signer::address_of(dice_admin),
                object_address: object_addr,
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
    /// Play dice game - now uses object-based capability
    entry fun play_dice(player: &signer, guess: u8, bet_amount: u64) acquires GameRegistry, GameAuth {
        assert!(guess >= 1 && guess <= 6, E_INVALID_GUESS);
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);
        let expected_payout = bet_amount * PAYOUT_MULTIPLIER;

        // Withdraw bet as FungibleAsset from player
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get capability from object
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Place bet with casino
        let bet_id =
            CasinoHouse::place_bet(
                capability,
                bet_fa,
                player_addr,
                expected_payout
            );

        // Roll dice and determine outcome
        let dice_result = randomness::u8_range(1, 7);
        let player_won = dice_result == guess;
        let actual_payout = if (player_won) {
            expected_payout
        } else { 0 };

        // Settle bet
        CasinoHouse::settle_bet(capability, bet_id, player_addr, actual_payout);

        event::emit(
            DiceRolled {
                bet_id,
                player: player_addr,
                guess,
                result: dice_result,
                bet_amount,
                won: player_won,
                payout: actual_payout
            }
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Test version allowing unsafe randomness
    public entry fun test_only_play_dice(
        player: &signer, guess: u8, bet_amount: u64
    ) acquires GameRegistry, GameAuth {
        play_dice(player, guess, bet_amount);
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
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, PAYOUT_MULTIPLIER, HOUSE_EDGE_BPS)
    }

    #[view]
    public fun calculate_payout(bet_amount: u64): u64 {
        bet_amount * PAYOUT_MULTIPLIER
    }

    #[view]
    public fun get_game_object_address(): address acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@dice_game);
        registry.object_address
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
    public fun get_game_info(): (address, address, String, String) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@dice_game);
        (registry.creator, registry.object_address, registry.game_name, registry.version)
    }

    #[view]
    public fun is_registered(): bool {
        CasinoHouse::is_game_registered(@dice_game)
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameRegistry>(@dice_game)
    }

    #[view]
    public fun is_ready(): bool {
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
}
