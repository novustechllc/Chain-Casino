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
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
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
    /// Invalid game object
    const E_INVALID_GAME_OBJECT: u64 = 0x0C;

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

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Game metadata stored in named object
    struct GameMetadata has key {
        name: String,
        version: String,
        module_address: address,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64,
        created_at: u64,
        capability_claimed: bool,
        extend_ref: ExtendRef
    }

    /// Registry of authorized casino games (by game object)
    struct GameRegistry has key {
        registered_games: OrderedMap<Object<GameMetadata>, bool>
    }

    /// Auto-incrementing bet identifier
    struct BetIndex has key {
        next: u64
    }

    /// Registry of bet information for payout validation
    struct BetRegistry has key {
        bets: OrderedMap<u64, BetInfo>
    }

    /// Bet information for payout validation
    struct BetInfo has copy, drop, store {
        expected_payout: u64,
        settled: bool
    }

    /// Capability resource proving game authorization (Object-Based)
    struct GameCapability has key, store {
        game_object: Object<GameMetadata>
    }

    //
    // Event Specifications
    //

    #[event]
    struct BetAcceptedEvent has drop, store {
        bet_id: u64,
        game_object: Object<GameMetadata>,
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
        game_object: Object<GameMetadata>,
        name: String,
        module_address: address,
        version: String
    }

    #[event]
    struct GameUnregisteredEvent has drop, store {
        game_object: Object<GameMetadata>,
        name: String
    }

    #[event]
    struct GameCapabilityClaimedEvent has drop, store {
        game_object: Object<GameMetadata>,
        module_address: address,
        name: String
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
                registered_games: ordered_map::new<Object<GameMetadata>, bool>()
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

    /// Register new game by creating game object
    public entry fun register_game(
        admin: &signer,
        game_creator: address,
        name: String,
        version: String,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);
        assert!(max_bet >= min_bet, E_INVALID_AMOUNT);

        // Create named object for this game instance
        let seed = build_game_seed(name, version);
        let constructor_ref = object::create_named_object(admin, seed);

        // Make it non-transferable for security
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Store game metadata in the object FIRST
        move_to(
            &object_signer,
            GameMetadata {
                name,
                version,
                module_address: game_creator,
                min_bet,
                max_bet,
                house_edge_bps,
                created_at: timestamp::now_seconds(),
                capability_claimed: false,
                extend_ref
            }
        );

        // THEN create object reference
        let game_object =
            object::object_from_constructor_ref<GameMetadata>(&constructor_ref);

        // Register in global registry
        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            !ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_ALREADY_REGISTERED
        );
        registry.registered_games.add(game_object, true);

        event::emit(
            GameRegisteredEvent { game_object, name, module_address: game_creator, version }
        );
    }

    /// Game claims its capability using object reference
    public fun get_game_capability(
        game_signer: &signer, game_object: Object<GameMetadata>
    ): GameCapability acquires GameRegistry, GameMetadata {
        let game_address = signer::address_of(game_signer);
        let object_addr = object::object_address(&game_object);

        // Verify game is registered
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        // Verify metadata exists and signer matches
        assert!(exists<GameMetadata>(object_addr), E_INVALID_GAME_OBJECT);
        let game_metadata = borrow_global_mut<GameMetadata>(object_addr);

        assert!(
            game_metadata.module_address == game_address,
            E_NOT_ADMIN
        );
        assert!(!game_metadata.capability_claimed, E_CAPABILITY_ALREADY_CLAIMED);

        game_metadata.capability_claimed = true;

        event::emit(
            GameCapabilityClaimedEvent {
                game_object,
                module_address: game_address,
                name: game_metadata.name
            }
        );

        GameCapability { game_object }
    }

    /// Remove game from registry
    public entry fun unregister_game(
        admin: &signer, game_object: Object<GameMetadata>
    ) acquires GameRegistry, GameMetadata {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        registry.registered_games.remove(&game_object);

        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global<GameMetadata>(object_addr);

        event::emit(GameUnregisteredEvent { game_object, name: game_metadata.name });
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
    ): u64 acquires Treasury, BetIndex, GameRegistry, BetRegistry, GameMetadata {
        let game_object = capability.game_object;
        let amount = fungible_asset::amount(&bet_fa);

        // Verify game is registered
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        // Get game constraints from metadata
        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global<GameMetadata>(object_addr);
        assert!(amount >= game_metadata.min_bet, E_INVALID_AMOUNT);
        assert!(amount <= game_metadata.max_bet, E_INVALID_AMOUNT);
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

        // Check if treasury has sufficient funds for expected payout
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
            BetAcceptedEvent { bet_id, game_object, player, amount, expected_payout }
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
        // Verify game is registered
        let game_object = capability.game_object;
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
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

    /// Build seed for deterministic object creation
    fun build_game_seed(name: String, version: String): vector<u8> {
        let seed = *std::string::bytes(&name);
        vector::append(&mut seed, b"_");
        vector::append(&mut seed, *std::string::bytes(&version));
        seed
    }

    /// Derive game object address from creator and game details
    public fun derive_game_object_address(
        creator: address, name: String, version: String
    ): address {
        let seed = build_game_seed(name, version);
        object::create_object_address(&creator, seed)
    }

    //
    // View Interface
    //

    #[view]
    public fun get_registered_games(): vector<Object<GameMetadata>> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        registry.registered_games.keys()
    }

    #[view]
    public fun get_game_metadata(
        game_object: Object<GameMetadata>
    ): (String, String, address, u64, u64, u64, bool) acquires GameMetadata {
        let object_addr = object::object_address(&game_object);
        let metadata = borrow_global<GameMetadata>(object_addr);
        (
            metadata.name,
            metadata.version,
            metadata.module_address,
            metadata.min_bet,
            metadata.max_bet,
            metadata.house_edge_bps,
            metadata.capability_claimed
        )
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
    public fun is_game_registered(game_object: Object<GameMetadata>): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        ordered_map::contains(&registry.registered_games, &game_object)
    }

    #[view]
    public fun is_game_capability_claimed(
        game_object: Object<GameMetadata>
    ): bool acquires GameMetadata {
        let object_addr = object::object_address(&game_object);
        if (!exists<GameMetadata>(object_addr)) { false }
        else {
            let metadata = borrow_global<GameMetadata>(object_addr);
            metadata.capability_claimed
        }
    }

    #[view]
    public fun game_object_exists(game_object: Object<GameMetadata>): bool {
        let object_addr = object::object_address(&game_object);
        exists<GameMetadata>(object_addr)
    }
}
