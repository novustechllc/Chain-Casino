//! MIT License
//!
//! Always Lose Game - Mock game for testing treasury drainage scenarios
//!
//! This game always pays out 3x the bet amount, guaranteed to drain treasury

#[test_only]
module casino::AlwaysLoseGame {
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin;
    use aptos_framework::event;
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
    /// Maximum bet amount (0.1 APT in octas) - smaller to drain faster
    const MAX_BET: u64 = 10000000;
    /// This game always pays 3x (guaranteed loss for house)
    const LOSS_MULTIPLIER: u64 = 3;
    /// Negative house edge (-200%)
    const HOUSE_EDGE_BPS: u64 = 20000;
    /// Game version
    const GAME_VERSION: vector<u8> = b"v1";

    //
    // Resources
    //

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GameAuth has key {
        capability: GameCapability,
        extend_ref: ExtendRef
    }

    struct GameRegistry has key {
        creator: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        game_name: String,
        version: String
    }

    //
    // Events
    //

    #[event]
    struct AlwaysLoseEvent has drop, store {
        player: address,
        bet_amount: u64,
        payout: u64,
        treasury_used: address
    }

    #[event]
    struct GameInitialized has drop, store {
        creator: address,
        object_address: address,
        game_object: Object<CasinoHouse::GameMetadata>,
        loss_multiplier: u64
    }

    //
    // Initialization
    //

    public entry fun initialize_game(admin: &signer) {
        assert!(signer::address_of(admin) == @casino, E_UNAUTHORIZED);
        assert!(!exists<GameRegistry>(@casino), E_ALREADY_INITIALIZED);

        let game_name = string::utf8(b"AlwaysLoseGame");
        let version = string::utf8(GAME_VERSION);
        let game_object_addr =
            CasinoHouse::derive_game_object_address(@casino, game_name, version);
        let game_object: Object<CasinoHouse::GameMetadata> =
            object::address_to_object(game_object_addr);

        assert!(CasinoHouse::game_object_exists(game_object), E_GAME_NOT_REGISTERED);

        let seed = build_seed(game_name, version);
        let constructor_ref = object::create_named_object(admin, seed);
        let object_signer = object::generate_signer(&constructor_ref);
        let object_addr =
            object::object_address(
                &object::object_from_constructor_ref<ObjectCore>(&constructor_ref)
            );

        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        let capability = CasinoHouse::get_game_capability(admin, game_object);

        move_to(&object_signer, GameAuth { capability, extend_ref });
        move_to(
            admin,
            GameRegistry {
                creator: signer::address_of(admin),
                game_object,
                game_name,
                version
            }
        );

        event::emit(
            GameInitialized {
                creator: signer::address_of(admin),
                object_address: object_addr,
                game_object,
                loss_multiplier: LOSS_MULTIPLIER
            }
        );
    }

    //
    // Core Game Interface
    //

    /// Always lose game - guarantees 3x payout to drain treasury
    public entry fun always_lose_bet(player: &signer, bet_amount: u64) acquires GameRegistry, GameAuth {
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Withdraw bet from player
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get capability
        let object_addr = get_game_object_address();
        let game_auth = borrow_global<GameAuth>(object_addr);
        let capability = &game_auth.capability;

        // Place bet
        let (treasury_source, bet_id) =
            CasinoHouse::place_bet(capability, bet_fa, player_addr);

        // Always pay 3x (guaranteed house loss)
        let payout = bet_amount * LOSS_MULTIPLIER;

        // Settle bet with guaranteed payout
        CasinoHouse::settle_bet(
            capability,
            bet_id,
            player_addr,
            payout,
            treasury_source
        );

        event::emit(
            AlwaysLoseEvent {
                player: player_addr,
                bet_amount,
                payout,
                treasury_used: treasury_source
            }
        );
    }

    //
    // Helper Functions
    //

    fun build_seed(name: String, version: String): vector<u8> {
        let seed = *string::bytes(&name);
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *string::bytes(&version));
        seed
    }

    //
    // View Functions
    //

    #[view]
    public fun get_game_config(): (u64, u64, u64) {
        (MIN_BET, MAX_BET, LOSS_MULTIPLIER)
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
    public fun is_initialized(): bool {
        exists<GameRegistry>(@casino)
    }

    #[view]
    public fun is_ready(): bool acquires GameRegistry {
        if (!is_initialized()) { false }
        else {
            let registry = borrow_global<GameRegistry>(@casino);
            CasinoHouse::is_game_registered(registry.game_object)
        }
    }
}
