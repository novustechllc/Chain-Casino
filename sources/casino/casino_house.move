//! MIT License
//!
//! Casino treasury and game registry management (Block-STM Optimized)
//!
//! FIXED: Treasury signer mismatch - now uses SignerCapability for resource accounts

module casino::CasinoHouse {
    use std::string::{Self, String};
    use std::vector;
    use std::signer;
    use std::option;
    use std::bcs;

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
    /// Game capability already claimed
    const E_CAPABILITY_ALREADY_CLAIMED: u64 = 0x0B;
    /// Invalid game object
    const E_INVALID_GAME_OBJECT: u64 = 0x0C;
    /// Game treasury not found
    const E_GAME_TREASURY_NOT_FOUND: u64 = 0x0D;

    //
    // Constants
    //

    /// Default overflow threshold multiplier (110%)
    const OVERFLOW_MULTIPLIER: u64 = 110;
    /// Default drain threshold multiplier (25%)
    const DRAIN_MULTIPLIER: u64 = 25;
    /// Target reserve safety multiplier (1.5x)
    const SAFETY_MULTIPLIER: u64 = 150;
    /// Percentage basis (100%)
    const PERCENTAGE_BASE: u64 = 100;

    //
    // Collision-Free Bet Identifier
    //

    /// Collision-free bet identifier using player address + sequence number
    public struct BetId has drop, store {
        player: address,
        sequence: u64
    }

    //
    // Resource Specifications
    //

    /// Central treasury registry managing all game treasuries
    struct TreasuryRegistry has key {
        /// Central treasury for large payouts and liquidity management
        central_store: Object<aptos_framework::fungible_asset::FungibleStore>,
        /// Mapping of game objects to their treasury addresses
        game_treasuries: OrderedMap<Object<GameMetadata>, address>,
        /// Casino signer capability for treasury operations
        casino_signer_cap: account::SignerCapability
    }

    /// Per-game treasury with automatic rebalancing
    /// FIXED: Now uses SignerCapability for resource account operations
    struct GameTreasury has key {
        /// Game's isolated fungible asset store
        hot_store: Object<aptos_framework::fungible_asset::FungibleStore>,
        /// Game metadata reference
        game_object: Object<GameMetadata>,
        /// Target operational reserve amount
        target_reserve: u64,
        /// Threshold to send excess to central (target * 1.1)
        overflow_threshold: u64,
        /// Threshold to request central help (target * 0.25)
        drain_threshold: u64,
        /// 7-day rolling bet volume for reserve calculation
        rolling_volume: u64,
        /// FIXED: Resource account signer capability (not object ExtendRef)
        resource_signer_cap: account::SignerCapability
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

    /// Capability resource proving game authorization (Object-Based)
    struct GameCapability has key, store {
        game_object: Object<GameMetadata>
    }

    //
    // Event Specifications
    //

    #[event]
    struct GameRegisteredEvent has drop, store {
        game_object: Object<GameMetadata>,
        name: String,
        module_address: address,
        version: String,
        treasury_address: address
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

    #[event]
    struct TreasuryRebalancedEvent has drop, store {
        game_object: Object<GameMetadata>,
        transfer_amount: u64,
        direction: bool,
        new_balance: u64
    }

    #[event]
    struct LiquidityInjectedEvent has drop, store {
        game_treasury_addr: address,
        amount: u64
    }

    #[event]
    struct LiquidityWithdrawnEvent has drop, store {
        game_treasury_addr: address,
        amount: u64
    }

    #[event]
    struct BetPlacedEvent has drop, store {
        player: address,
        sequence: u64,
        game_object: Object<GameMetadata>,
        amount: u64,
        treasury_source: address
    }

    #[event]
    struct BetSettledEvent has drop, store {
        player: address,
        sequence: u64,
        winner: address,
        payout: u64,
        treasury_source: address
    }

    //
    // Initialization Interface
    //

    /// Initialize casino house with central treasury and game registry
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        // Create resource account for central treasury
        let (resource_signer, signer_cap) =
            account::create_resource_account(admin, b"central_treasury");

        // Create primary store for AptosCoin FA
        let aptos_metadata = get_aptos_metadata();
        let central_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(&resource_signer),
                aptos_metadata
            );

        // Initialize registries
        move_to(
            admin,
            TreasuryRegistry {
                central_store,
                game_treasuries: ordered_map::new<Object<GameMetadata>, address>(),
                casino_signer_cap: signer_cap
            }
        );

        move_to(
            admin,
            GameRegistry {
                registered_games: ordered_map::new<Object<GameMetadata>, bool>()
            }
        );
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        init_module(admin);
    }

    //
    // Game Management Interface
    //

    /// Register new game by creating game object and dedicated treasury
    public entry fun register_game(
        admin: &signer,
        game_creator: address,
        name: String,
        version: String,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    ) acquires GameRegistry, TreasuryRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);
        assert!(max_bet >= min_bet, E_INVALID_AMOUNT);

        // Create named object for game instance
        let seed = build_game_seed(name, version);
        let constructor_ref = object::create_named_object(admin, seed);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Store game metadata
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

        let game_object =
            object::object_from_constructor_ref<GameMetadata>(&constructor_ref);

        // Register in global registry
        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            !ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_ALREADY_REGISTERED
        );
        registry.registered_games.add(game_object, true);

        // Create dedicated treasury
        let treasury_addr = create_game_treasury(admin, game_object, min_bet * 100);

        // Register treasury mapping
        let treasury_registry = borrow_global_mut<TreasuryRegistry>(@casino);
        treasury_registry.game_treasuries.add(game_object, treasury_addr);

        // Fund game treasury with 10x max bet for initial liquidity
        inject_liquidity(treasury_addr, max_bet * 10);

        event::emit(
            GameRegisteredEvent {
                game_object,
                name,
                module_address: game_creator,
                version,
                treasury_address: treasury_addr
            }
        );
    }

    /// FIXED: Create per-game treasury resource account with proper signer capability storage
    fun create_game_treasury(
        admin: &signer, game_object: Object<GameMetadata>, initial_target_reserve: u64
    ): address {
        let game_seed = object::object_address(&game_object);
        let treasury_seed = vector::empty<u8>();
        vector::append(&mut treasury_seed, b"game_treasury_");
        vector::append(&mut treasury_seed, bcs::to_bytes(&game_seed));

        // Create resource account for game treasury
        let (treasury_signer, resource_signer_cap) =
            account::create_resource_account(admin, treasury_seed);
        let treasury_addr = signer::address_of(&treasury_signer);

        // Create FA store at the resource account address
        let hot_store =
            primary_fungible_store::ensure_primary_store_exists(
                treasury_addr, get_aptos_metadata()
            );

        // Calculate thresholds
        let overflow_threshold =
            (initial_target_reserve * OVERFLOW_MULTIPLIER) / PERCENTAGE_BASE;
        let drain_threshold = (initial_target_reserve * DRAIN_MULTIPLIER)
            / PERCENTAGE_BASE;

        // FIXED: Store GameTreasury with resource account's SignerCapability
        move_to(
            &treasury_signer,
            GameTreasury {
                hot_store,
                game_object,
                target_reserve: initial_target_reserve,
                overflow_threshold,
                drain_threshold,
                rolling_volume: 0,
                resource_signer_cap // FIXED: Store the resource account capability
            }
        );

        treasury_addr
    }

    /// Game claims capability using object reference
    public fun get_game_capability(
        game_signer: &signer, game_object: Object<GameMetadata>
    ): GameCapability acquires GameRegistry, GameMetadata {
        let game_address = signer::address_of(game_signer);
        let object_addr = object::object_address(&game_object);

        // Verify registration
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        // Verify metadata and claim capability
        assert!(exists<GameMetadata>(object_addr), E_INVALID_GAME_OBJECT);
        let game_metadata = borrow_global_mut<GameMetadata>(object_addr);
        assert!(game_metadata.module_address == game_address, E_NOT_ADMIN);
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

    /// Remove game from registry and withdraw all treasury funds
    public entry fun unregister_game(
        admin: &signer, game_object: Object<GameMetadata>
    ) acquires GameRegistry, GameMetadata, TreasuryRegistry, GameTreasury {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        registry.registered_games.remove(&game_object);

        // Withdraw all liquidity from game treasury before removing
        // Phase 1: Extract needed data to avoid borrow conflicts
        let (game_treasury_addr_opt, central_store) = {
            let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
            let addr_opt =
                if (treasury_registry.game_treasuries.contains(&game_object)) {
                    option::some(*treasury_registry.game_treasuries.borrow(&game_object))
                } else {
                    option::none()
                };
            (addr_opt, treasury_registry.central_store)
        };

        // Phase 2: Handle treasury withdrawal if game treasury exists
        if (option::is_some(&game_treasury_addr_opt)) {
            let game_treasury_addr = option::extract(&mut game_treasury_addr_opt);

            // Withdraw all funds back to central treasury
            let current_balance =
                primary_fungible_store::balance(
                    game_treasury_addr, get_aptos_metadata()
                );

            if (current_balance > 0) {
                let withdrawn_fa = withdraw_excess(game_treasury_addr, current_balance);
                fungible_asset::deposit(central_store, withdrawn_fa);

                event::emit(
                    LiquidityWithdrawnEvent { game_treasury_addr, amount: current_balance }
                );
            };

            // Phase 3: Remove from registry (separate mutable borrow)
            let treasury_registry = borrow_global_mut<TreasuryRegistry>(@casino);
            treasury_registry.game_treasuries.remove(&game_object);
        };

        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global<GameMetadata>(object_addr);

        event::emit(GameUnregisteredEvent { game_object, name: game_metadata.name });
    }

    //
    // Simplified Bet Flow Interface (Trust Authorized Games)
    //

    /// Accept bet from authorized game - simplified treasury operations only
    public fun place_bet(
        capability: &GameCapability, bet_fa: FungibleAsset, player_addr: address
    ): (address, BetId) acquires GameRegistry, TreasuryRegistry, GameTreasury, GameMetadata {

        let game_object = capability.game_object;
        let amount = fungible_asset::amount(&bet_fa);

        // Get sequence number BEFORE creating BetId struct
        let sequence = account::get_sequence_number(player_addr);

        // Validate game registration and constraints
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global<GameMetadata>(object_addr);
        assert!(amount >= game_metadata.min_bet, E_INVALID_AMOUNT);
        assert!(amount <= game_metadata.max_bet, E_INVALID_AMOUNT);

        // Determine treasury routing
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        let game_treasury_addr = *treasury_registry.game_treasuries.borrow(&game_object);

        let treasury_source = {
            let game_treasury = borrow_global<GameTreasury>(game_treasury_addr);
            let game_balance =
                primary_fungible_store::balance(
                    game_treasury_addr, get_aptos_metadata()
                );

            // Use central if game treasury balance is low
            if (game_balance < game_treasury.drain_threshold) {
                get_central_treasury_address()
            } else {
                game_treasury_addr
            }
        };

        // Deposit to appropriate treasury
        if (treasury_source == get_central_treasury_address()) {
            fungible_asset::deposit(treasury_registry.central_store, bet_fa);
        } else {
            fungible_asset::deposit(
                borrow_global<GameTreasury>(game_treasury_addr).hot_store, bet_fa
            );
            update_rolling_volume(game_treasury_addr, amount);
        };

        // EMIT EVENT FIRST - using raw fields
        event::emit(
            BetPlacedEvent {
                player: player_addr,
                sequence,
                game_object,
                amount,
                treasury_source
            }
        );

        // CREATE BetId struct AFTER event emission
        let bet_id = BetId { player: player_addr, sequence };

        (treasury_source, bet_id)
    }

    /// Settle bet with payout - simplified payout operations only
    public fun settle_bet(
        capability: &GameCapability,
        bet_id: BetId,
        winner: address,
        payout: u64,
        treasury_source: address
    ) acquires GameRegistry, TreasuryRegistry, GameTreasury {

        // EXTRACT fields from BetId BEFORE it gets consumed
        let BetId { player, sequence } = bet_id;

        // Verify game registration
        let game_object = capability.game_object;
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_object),
            E_GAME_NOT_REGISTERED
        );

        // Pay winner if payout > 0
        if (payout > 0) {
            let central_addr = get_central_treasury_address();

            if (treasury_source == central_addr) {
                // Pay from central treasury
                let central_treasury_signer = get_central_treasury_signer();
                primary_fungible_store::transfer(
                    &central_treasury_signer,
                    get_aptos_metadata(),
                    winner,
                    payout
                );
            } else {
                // Pay from game treasury
                let game_treasury_signer = get_game_treasury_signer(treasury_source);
                primary_fungible_store::transfer(
                    &game_treasury_signer,
                    get_aptos_metadata(),
                    winner,
                    payout
                );
            };
        };

        // Always check rebalancing regardless of treasury source
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        let game_treasury_addr = *treasury_registry.game_treasuries.borrow(&game_object);

        rebalance_game_treasury(game_treasury_addr);

        // EMIT EVENT using extracted fields
        event::emit(
            BetSettledEvent { player, sequence, winner, payout, treasury_source }
        );
    }

    //
    // Treasury Management Interface
    //

    /// Inject liquidity into specific game treasury
    package fun inject_liquidity(
        game_treasury_addr: address, amount: u64
    ) acquires TreasuryRegistry {
        let central_treasury_signer = get_central_treasury_signer();
        primary_fungible_store::transfer(
            &central_treasury_signer,
            get_aptos_metadata(),
            game_treasury_addr,
            amount
        );

        event::emit(LiquidityInjectedEvent { game_treasury_addr, amount });
    }

    /// FIXED: Withdraw excess from game treasury to central using resource account signer
    package fun withdraw_excess(
        game_treasury_addr: address, amount: u64
    ): FungibleAsset acquires GameTreasury {
        let game_treasury_signer = get_game_treasury_signer(game_treasury_addr);
        let treasury_signer_addr = signer::address_of(&game_treasury_signer);

        // Verify addresses match
        assert!(treasury_signer_addr == game_treasury_addr, E_INVALID_GAME_OBJECT);

        let withdrawn_fa =
            primary_fungible_store::withdraw(
                &game_treasury_signer,
                get_aptos_metadata(),
                amount
            );

        withdrawn_fa
    }

    /// Automatic rebalancing for game treasuries
    fun rebalance_game_treasury(
        game_treasury_addr: address
    ) acquires GameTreasury, TreasuryRegistry {
        // Phase 1: Read treasury configuration
        let (game_object, target_reserve, overflow_threshold, drain_threshold) = {
            let game_treasury = borrow_global<GameTreasury>(game_treasury_addr);
            (
                game_treasury.game_object,
                game_treasury.target_reserve,
                game_treasury.overflow_threshold,
                game_treasury.drain_threshold
            )
        };

        // Phase 2: Check current balance
        let current_balance =
            primary_fungible_store::balance(game_treasury_addr, get_aptos_metadata());

        // Phase 3: Execute rebalancing if needed
        if (current_balance > overflow_threshold) {
            // Send excess to central treasury
            let excess = current_balance - target_reserve;
            let transfer_amount = excess / 10; // 10% of excess

            let excess_fa = withdraw_excess(game_treasury_addr, transfer_amount);

            let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
            fungible_asset::deposit(treasury_registry.central_store, excess_fa);

            event::emit(
                TreasuryRebalancedEvent {
                    game_object,
                    transfer_amount,
                    direction: true,
                    new_balance: current_balance - transfer_amount
                }
            );
        } else if (current_balance < drain_threshold) {
            // Request liquidity from central
            let needed = target_reserve - current_balance;

            inject_liquidity(game_treasury_addr, needed);

            event::emit(
                TreasuryRebalancedEvent {
                    game_object,
                    transfer_amount: needed,
                    direction: false,
                    new_balance: current_balance + needed
                }
            );
        } else {
            // No rebalancing needed - balance within thresholds
        };
    }

    /// Update rolling volume for target reserve calculation
    fun update_rolling_volume(
        game_treasury_addr: address, new_volume: u64
    ) acquires GameTreasury {
        let game_treasury = borrow_global_mut<GameTreasury>(game_treasury_addr);

        let old_volume = game_treasury.rolling_volume;
        let old_target = game_treasury.target_reserve;

        // Simple rolling average (7-day weighted)
        game_treasury.rolling_volume =
            (game_treasury.rolling_volume * 6 + new_volume * SAFETY_MULTIPLIER) / 7;

        // Update thresholds based on new volume
        game_treasury.target_reserve = game_treasury.rolling_volume;
        game_treasury.overflow_threshold =
            (game_treasury.target_reserve * OVERFLOW_MULTIPLIER) / PERCENTAGE_BASE;
        game_treasury.drain_threshold =
            (game_treasury.target_reserve * DRAIN_MULTIPLIER) / PERCENTAGE_BASE;
    }

    //
    // Helper Functions
    //

    /// Get central treasury signer
    fun get_central_treasury_signer(): signer acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        account::create_signer_with_capability(&treasury_registry.casino_signer_cap)
    }

    /// FIXED: Get game treasury signer from resource account capability
    fun get_game_treasury_signer(game_treasury_addr: address): signer acquires GameTreasury {
        let game_treasury = borrow_global<GameTreasury>(game_treasury_addr);
        let signer =
            account::create_signer_with_capability(&game_treasury.resource_signer_cap);

        let signer_addr = signer::address_of(&signer);
        // This should now match!
        assert!(signer_addr == game_treasury_addr, E_INVALID_GAME_OBJECT);
        signer
    }

    /// Get central treasury address
    fun get_central_treasury_address(): address {
        account::create_resource_address(&@casino, b"central_treasury")
    }

    /// Get AptosCoin metadata
    fun get_aptos_metadata(): Object<aptos_framework::fungible_asset::Metadata> {
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        option::extract(&mut aptos_metadata_option)
    }

    /// Extract funds from central treasury for InvestorToken redemptions
    package fun redeem_from_treasury(amount: u64): FungibleAsset acquires TreasuryRegistry {
        let central_balance = central_treasury_balance();
        assert!(amount <= central_balance, E_INSUFFICIENT_TREASURY);

        let central_treasury_signer = get_central_treasury_signer();
        primary_fungible_store::withdraw(
            &central_treasury_signer,
            get_aptos_metadata(),
            amount
        )
    }

    /// Deposit fungible asset to central treasury
    package fun deposit_to_treasury(fa: FungibleAsset) acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        fungible_asset::deposit(treasury_registry.central_store, fa);
    }

    //
    // Game Limit Management Interface
    //

    /// Update game betting limits (casino controls risk)
    public entry fun update_game_limits(
        admin: &signer,
        game_object: Object<GameMetadata>,
        new_min_bet: u64,
        new_max_bet: u64
    ) acquires GameMetadata {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);
        assert!(new_max_bet >= new_min_bet, E_INVALID_AMOUNT);

        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global_mut<GameMetadata>(object_addr);

        game_metadata.min_bet = new_min_bet;
        game_metadata.max_bet = new_max_bet;
    }

    /// Games can request limit changes (reduce risk only)
    public fun request_limit_update(
        capability: &GameCapability, new_min_bet: u64, new_max_bet: u64
    ) acquires GameMetadata {
        let game_object = capability.game_object;
        let object_addr = object::object_address(&game_object);
        let game_metadata = borrow_global_mut<GameMetadata>(object_addr);

        // Games can only reduce risk (increase min or decrease max)
        assert!(new_min_bet >= game_metadata.min_bet, E_INVALID_AMOUNT);
        assert!(new_max_bet <= game_metadata.max_bet, E_INVALID_AMOUNT);

        game_metadata.min_bet = new_min_bet;
        game_metadata.max_bet = new_max_bet;
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

    /// Derive game object address
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
    /// Get total treasury balance (central + all game treasuries)
    public fun treasury_balance(): u64 acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        let central_balance = fungible_asset::balance(treasury_registry.central_store);

        let aptos_metadata = get_aptos_metadata();
        let game_total = 0u64;

        // Sum all game treasury balances
        let game_addrs = treasury_registry.game_treasuries.values();
        let i = 0;
        let len = vector::length(&game_addrs);
        while (i < len) {
            let game_addr = *vector::borrow(&game_addrs, i);
            let game_balance = primary_fungible_store::balance(
                game_addr, aptos_metadata
            );
            game_total = game_total + game_balance;
            i = i + 1;
        };

        central_balance + game_total
    }

    #[view]
    /// Get central treasury balance only
    public fun central_treasury_balance(): u64 acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        fungible_asset::balance(treasury_registry.central_store)
    }

    #[view]
    /// Get specific game treasury balance
    public fun game_treasury_balance(
        game_object: Object<GameMetadata>
    ): u64 acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        assert!(
            treasury_registry.game_treasuries.contains(&game_object),
            E_GAME_TREASURY_NOT_FOUND
        );

        let game_treasury_addr = *treasury_registry.game_treasuries.borrow(&game_object);
        primary_fungible_store::balance(game_treasury_addr, get_aptos_metadata())
    }

    #[view]
    /// Get game treasury address
    public fun get_game_treasury_address(
        game_object: Object<GameMetadata>
    ): address acquires TreasuryRegistry {
        let treasury_registry = borrow_global<TreasuryRegistry>(@casino);
        assert!(
            treasury_registry.game_treasuries.contains(&game_object),
            E_GAME_TREASURY_NOT_FOUND
        );
        *treasury_registry.game_treasuries.borrow(&game_object)
    }

    #[view]
    /// Get game treasury configuration
    public fun get_game_treasury_config(
        game_treasury_addr: address
    ): (u64, u64, u64, u64) acquires GameTreasury {
        let game_treasury = borrow_global<GameTreasury>(game_treasury_addr);
        (
            game_treasury.target_reserve,
            game_treasury.overflow_threshold,
            game_treasury.drain_threshold,
            game_treasury.rolling_volume
        )
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
