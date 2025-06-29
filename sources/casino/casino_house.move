//! MIT License
//!
//! Casino treasury and game registry management (Object-Based Refactor)
//!
//! Central hub for game authorization, bet settlement, and treasury operations.
//! Now supports object-based game instances with deterministic addressing.

module casino::CasinoHouse {
    use std::string::{String};
    use std::vector;
    use std::signer;
    use std::option;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event;
    use aptos_std::ordered_map::{Self, OrderedMap};

    //
    // Error Codes
    //

    /// Only casino admin can perform this operation
    const E_NOT_ADMIN: u64 = 0x01;
    /// Invalid amount (zero or exceeds limits)
    const E_INVALID_AMOUNT: u64 = 0x02;
    /// Game not registered
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    /// Game already registered
    const E_GAME_ALREADY_REGISTERED: u64 = 0x05;
    /// Insufficient treasury balance for payout
    const E_INSUFFICIENT_TREASURY: u64 = 0x06;
    /// Invalid bet settlement parameters
    const E_INVALID_SETTLEMENT: u64 = 0x07;
    /// Insufficient treasury balance for expected payout
    const E_INSUFFICIENT_TREASURY_FOR_PAYOUT: u64 = 0x08;
    /// Payout exceeds expected payout for bet
    const E_PAYOUT_EXCEEDS_EXPECTED: u64 = 0x09;
    /// Bet already settled
    const E_BET_ALREADY_SETTLED: u64 = 0x0A;
    /// Game capability already claimed
    const E_CAPABILITY_ALREADY_CLAIMED: u64 = 0x0B;

    //
    // Resource Specifications
    //

    /// Central treasury holding all casino funds as Fungible Assets
    struct Treasury has key {
        /// Primary store for AptosCoin FA
        store: Object<aptos_framework::fungible_asset::FungibleStore>
    }

    /// Casino signer capability for treasury operations
    struct CasinoSignerCapability has key {
        signer_cap: account::SignerCapability
    }

    /// Registry of authorized casino games (by module address)
    struct GameRegistry has key {
        registered_games: OrderedMap<address, GameInfo>
    }

    /// Auto-incrementing bet identifier
    struct BetIndex has key {
        next: u64
    }

    /// Registry of bet information for payout validation
    struct BetRegistry has key {
        bets: OrderedMap<u64, BetInfo>
    }

    /// Game metadata and configuration
    struct GameInfo has copy, drop, store {
        name: String,
        module_address: address,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64,
        capability_claimed: bool,
        // New fields for object support
        game_version: String,
        object_address: option::Option<address>
    }

    /// Bet information for payout validation
    struct BetInfo has copy, drop, store {
        expected_payout: u64,
        settled: bool
    }

    /// Capability resource proving game authorization
    struct GameCapability has key, store {
        game_address: address
    }

    //
    // Event Specifications
    //

    #[event]
    struct BetAcceptedEvent has drop, store {
        bet_id: u64,
        game_address: address,
        player: address,
        amount: u64,
        expected_payout: u64
    }

    #[event]
    struct BetSettledEvent has drop, store {
        bet_id: u64,
        winner: address,
        payout: u64
    }

    #[event]
    struct GameRegisteredEvent has drop, store {
        game_address: address,
        name: String,
        module_address: address,
        game_version: String
    }

    #[event]
    struct GameUnregisteredEvent has drop, store {
        game_address: address,
        name: String
    }

    #[event]
    struct GameCapabilityClaimedEvent has drop, store {
        game_address: address,
        name: String,
        object_address: address
    }

    #[event]
    struct GameObjectRegisteredEvent has drop, store {
        module_address: address,
        object_address: address,
        name: String,
        version: String
    }

    //
    // Initialization Interface
    //

    /// Initialize casino house with treasury and game registry
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        // Create resource account for treasury operations
        let (resource_signer, signer_cap) =
            account::create_resource_account(admin, b"casino_treasury");

        // Create primary store for AptosCoin FA on resource account
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let treasury_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(&resource_signer),
                aptos_metadata
            );

        // Store signer capability at casino address
        move_to(admin, CasinoSignerCapability { signer_cap });

        // Store treasury reference at casino address
        move_to(admin, Treasury { store: treasury_store });

        move_to(
            admin,
            GameRegistry {
                registered_games: ordered_map::new<address, GameInfo>()
            }
        );

        move_to(
            admin,
            BetRegistry {
                bets: ordered_map::new<u64, BetInfo>()
            }
        );

        move_to(admin, BetIndex { next: 1 });
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        init_module(admin);
    }

    //
    // Game Management Interface
    //

    /// Register new game by module address (casino admin only)
    public entry fun register_game(
        admin: &signer,
        game_address: address,
        name: String,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);

        assert!(
            !ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_ALREADY_REGISTERED
        );

        assert!(max_bet >= min_bet, E_INVALID_AMOUNT);

        let game_info = GameInfo {
            name,
            module_address: game_address,
            min_bet,
            max_bet,
            house_edge_bps,
            capability_claimed: false,
            game_version: std::string::utf8(b"v1"), // Default version
            object_address: option::none<address>()
        };

        registry.registered_games.add(game_address, game_info);

        event::emit(
            GameRegisteredEvent {
                game_address,
                name,
                module_address: game_address,
                game_version: std::string::utf8(b"v1")
            }
        );
    }

    /// Game claims its capability and registers object address
    public fun get_game_capability(game_signer: &signer): GameCapability acquires GameRegistry {
        let game_address = signer::address_of(game_signer);

        let registry = borrow_global_mut<GameRegistry>(@casino);

        assert!(
            registry.registered_games.contains(&game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = registry.registered_games.borrow_mut(&game_address);

        assert!(!game_info.capability_claimed, E_CAPABILITY_ALREADY_CLAIMED);

        game_info.capability_claimed = true;

        // Derive the expected object address for this game
        let object_addr =
            derive_game_object_address(
                game_address,
                game_info.name,
                game_info.game_version
            );

        // Update registry with object address
        game_info.object_address = option::some(object_addr);

        event::emit(
            GameCapabilityClaimedEvent {
                game_address,
                name: game_info.name,
                object_address: object_addr
            }
        );

        GameCapability { game_address }
    }

    /// Register game object address after initialization (called by games)
    public fun register_game_object(
        game_signer: &signer,
        object_address: address,
        name: String,
        version: String
    ) acquires GameRegistry {
        let module_address = signer::address_of(game_signer);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&module_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = registry.registered_games.borrow_mut(&module_address);
        game_info.object_address = option::some(object_address);
        game_info.game_version = version;

        event::emit(
            GameObjectRegisteredEvent { module_address, object_address, name, version }
        );
    }

    /// Remove game from registry (casino admin only)
    public entry fun unregister_game(
        admin: &signer, game_address: address
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = registry.registered_games.remove(&game_address);
        event::emit(GameUnregisteredEvent { game_address, name: game_info.name });
    }

    //
    // Bet Flow Interface
    //

    /// Accept bet from authorized game
    public fun place_bet(
        capability: &GameCapability,
        bet_fa: FungibleAsset,
        player: address,
        expected_payout: u64
    ): u64 acquires Treasury, BetIndex, GameRegistry, BetRegistry {
        let game_addr = capability.game_address;
        let amount = fungible_asset::amount(&bet_fa);

        // Mandatory game registry check
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&game_addr),
            E_GAME_NOT_REGISTERED
        );
        let game_info = registry.registered_games.borrow(&game_addr);
        assert!(amount >= game_info.min_bet, E_INVALID_AMOUNT);
        assert!(amount <= game_info.max_bet, E_INVALID_AMOUNT);

        assert!(expected_payout > 0, E_INVALID_AMOUNT);

        // Deposit bet to treasury store
        let treasury = borrow_global<Treasury>(@casino);
        fungible_asset::deposit(treasury.store, bet_fa);

        let treasury_addr = get_treasury_address();
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let treasury_balance =
            primary_fungible_store::balance(treasury_addr, aptos_metadata);

        // Check if treasury has sufficient funds for expected payout after bet contribution
        assert!(
            expected_payout <= treasury_balance,
            E_INSUFFICIENT_TREASURY_FOR_PAYOUT
        );

        // Generate bet ID
        let bet_index = borrow_global_mut<BetIndex>(@casino);
        let bet_id = bet_index.next;
        bet_index.next = bet_id + 1;

        // Store bet information
        let bet_registry = borrow_global_mut<BetRegistry>(@casino);
        let bet_info = BetInfo { expected_payout, settled: false };
        bet_registry.bets.add(bet_id, bet_info);

        event::emit(
            BetAcceptedEvent {
                bet_id,
                game_address: game_addr,
                player,
                amount,
                expected_payout
            }
        );

        bet_id
    }

    /// Settle bet with payout from treasury
    public fun settle_bet(
        capability: &GameCapability,
        bet_id: u64,
        winner: address,
        payout: u64
    ) acquires BetRegistry, GameRegistry, CasinoSignerCapability {
        // Mandatory game registry check
        let game_addr = capability.game_address;
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&game_addr),
            E_GAME_NOT_REGISTERED
        );

        // Get bet information and validate
        let bet_registry = borrow_global_mut<BetRegistry>(@casino);
        assert!(
            bet_registry.bets.contains(&bet_id),
            E_INVALID_SETTLEMENT
        );

        let bet_info = bet_registry.bets.borrow_mut(&bet_id);
        assert!(!bet_info.settled, E_BET_ALREADY_SETTLED);
        assert!(payout <= bet_info.expected_payout, E_PAYOUT_EXCEEDS_EXPECTED);

        bet_info.settled = true;

        let treasury_addr = get_treasury_address();
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let treasury_balance =
            primary_fungible_store::balance(treasury_addr, aptos_metadata);
        assert!(payout <= treasury_balance, E_INSUFFICIENT_TREASURY);

        // Pay winner if payout > 0
        if (payout > 0) {
            let treasury_signer = get_treasury_signer();
            let aptos_metadata_option =
                coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
            let aptos_metadata = option::extract(&mut aptos_metadata_option);
            primary_fungible_store::transfer(
                &treasury_signer,
                aptos_metadata,
                winner,
                payout
            );
        };

        event::emit(BetSettledEvent { bet_id, winner, payout });
    }

    /// Internal function to get treasury signer from capability
    fun get_treasury_signer(): signer acquires CasinoSignerCapability {
        let signer_cap = &borrow_global<CasinoSignerCapability>(@casino).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Get the treasury resource account address
    fun get_treasury_address(): address {
        account::create_resource_address(&@casino, b"casino_treasury")
    }

    /// Extract funds from treasury for InvestorToken redemptions
    package fun redeem_from_treasury(amount: u64): FungibleAsset acquires CasinoSignerCapability {
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let treasury_addr = get_treasury_address();
        let treasury_balance =
            primary_fungible_store::balance(treasury_addr, aptos_metadata);
        assert!(amount <= treasury_balance, E_INSUFFICIENT_TREASURY);

        let treasury_signer = get_treasury_signer();
        primary_fungible_store::withdraw(&treasury_signer, aptos_metadata, amount)
    }

    /// Deposit fungible asset to treasury
    package fun deposit_to_treasury(fa: FungibleAsset) acquires Treasury {
        let treasury = borrow_global<Treasury>(@casino);
        fungible_asset::deposit(treasury.store, fa);
    }

    //
    // Object Address Derivation
    //

    /// Derive game object address from creator and game details
    public fun derive_game_object_address(
        creator: address, name: String, version: String
    ): address {
        let seed = *std::string::bytes(&name);
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *std::string::bytes(&version));
        object::create_object_address(&creator, seed)
    }

    //
    // View Interface
    //

    #[view]
    public fun get_registered_games(): vector<GameInfo> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        let games = vector::empty<GameInfo>();

        let keys = registry.registered_games.keys();
        let i = 0;
        while (i < vector::length(&keys)) {
            let game_address = *vector::borrow(&keys, i);
            let game_info =
                *ordered_map::borrow(&registry.registered_games, &game_address);
            vector::push_back(&mut games, game_info);
            i = i + 1;
        };

        games
    }

    #[view]
    public fun get_game_info(game_address: address): GameInfo acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_NOT_REGISTERED
        );
        *ordered_map::borrow(&registry.registered_games, &game_address)
    }

    #[view]
    public fun get_game_object_address(
        game_address: address
    ): option::Option<address> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        if (!ordered_map::contains(&registry.registered_games, &game_address)) {
            option::none<address>()
        } else {
            let game_info = ordered_map::borrow(
                &registry.registered_games, &game_address
            );
            game_info.object_address
        }
    }

    #[view]
    /// Get current treasury balance using primary store
    public fun treasury_balance(): u64 {
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let treasury_addr = get_treasury_address();
        primary_fungible_store::balance(treasury_addr, aptos_metadata)
    }

    #[view]
    public fun is_game_registered(game_address: address): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        ordered_map::contains(&registry.registered_games, &game_address)
    }

    #[view]
    public fun is_game_capability_claimed(game_address: address): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        if (!ordered_map::contains(&registry.registered_games, &game_address)) { false }
        else {
            let game_info = ordered_map::borrow(
                &registry.registered_games, &game_address
            );
            game_info.capability_claimed
        }
    }
}
