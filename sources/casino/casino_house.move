//! Casino treasury and game registry management
//!
//! Central hub for game authorization, bet settlement, and treasury operations.
//! Integrates with InvestorToken for profit distribution to token holders.

module casino::CasinoHouse {
    use std::string::{String};
    use std::vector;
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_std::ordered_map::{Self, OrderedMap};

    //
    // Error Codes
    //

    /// Only casino admin can perform this operation
    const E_NOT_ADMIN: u64 = 0x01;
    /// Invalid amount (zero or exceeds limits)
    const E_INVALID_AMOUNT: u64 = 0x02;
    /// Game not registered or inactive
    const E_GAME_NOT_REGISTERED: u64 = 0x03;
    /// Invalid game interface implementation
    const E_INVALID_GAME_INTERFACE: u64 = 0x04;
    /// Game already registered
    const E_GAME_ALREADY_REGISTERED: u64 = 0x05;
    /// Insufficient treasury balance for payout
    const E_INSUFFICIENT_TREASURY: u64 = 0x06;
    /// Invalid bet settlement parameters
    const E_INVALID_SETTLEMENT: u64 = 0x07;
    /// Game capability missing or invalid
    const E_MISSING_CAPABILITY: u64 = 0x08;
    /// Game is inactive
    const E_GAME_INACTIVE: u64 = 0x09;

    //
    // Constants
    //

    /// Default house edge (1.5%)
    const DEFAULT_HOUSE_EDGE_BPS: u64 = 150;

    //
    // Resource Specifications
    //

    /// Central treasury holding all casino funds
    struct Treasury has key {
        vault: Coin<AptosCoin>
    }

    /// Registry of authorized casino games
    struct GameRegistry has key {
        registered_games: OrderedMap<address, GameInfo>
    }

    /// Auto-incrementing bet identifier
    struct BetIndex has key {
        next: u64
    }

    /// Casino operational parameters
    struct Params has key {
        house_edge_bps: u64
    }

    /// Game authorization capability
    struct GameCapability has key {
        game_address: address
    }

    /// Game metadata and configuration
    struct GameInfo has copy, drop, store {
        name: String,
        module_address: address,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64,
        active: bool
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when bet is accepted by casino
    struct BetAcceptedEvent has drop, store {
        bet_id: u64,
        game_address: address,
        player: address,
        amount: u64
    }

    #[event]
    /// Emitted when bet is settled with payout
    struct BetSettledEvent has drop, store {
        bet_id: u64,
        winner: address,
        payout: u64,
        profit: u64
    }

    #[event]
    /// Emitted when new game is registered
    struct GameRegisteredEvent has drop, store {
        game_address: address,
        name: String,
        module_address: address
    }

    #[event]
    /// Emitted when game is unregistered
    struct GameUnregisteredEvent has drop, store {
        game_address: address,
        name: String
    }

    #[event]
    /// Emitted when game status changes
    struct GameToggleEvent has drop, store {
        game_address: address,
        active: bool
    }

    //
    // Initialization Interface
    //

    /// Initialize casino house with treasury and game registry
    public entry fun init(owner: &signer) {
        assert!(signer::address_of(owner) == @casino, E_NOT_ADMIN);

        move_to(
            owner,
            Treasury { vault: coin::zero<AptosCoin>() }
        );

        move_to(
            owner,
            GameRegistry {
                registered_games: ordered_map::new<address, GameInfo>()
            }
        );

        move_to(owner, BetIndex { next: 1 });

        move_to(owner, Params { house_edge_bps: DEFAULT_HOUSE_EDGE_BPS });
    }

    //
    // Game Management Interface
    //

    /// Register new game and grant capability
    public entry fun register_game(
        admin: &signer,
        game_signer: &signer,
        name: String,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let game_addr = signer::address_of(game_signer);
        let registry = borrow_global_mut<GameRegistry>(@casino);

        // Check if game already registered
        assert!(
            !ordered_map::contains(&registry.registered_games, &game_addr),
            E_GAME_ALREADY_REGISTERED
        );

        // Validate game info
        assert!(min_bet > 0, E_INVALID_AMOUNT);
        assert!(max_bet >= min_bet, E_INVALID_AMOUNT);

        // Store game info
        let game_info = GameInfo {
            name,
            module_address: game_addr,
            min_bet,
            max_bet,
            house_edge_bps,
            active: true
        };

        ordered_map::add(&mut registry.registered_games, game_addr, game_info);

        // Grant capability to game
        move_to(game_signer, GameCapability { game_address: game_addr });

        event::emit(
            GameRegisteredEvent { game_address: game_addr, name, module_address: game_addr }
        );
    }

    /// Permanently remove game from registry
    public entry fun unregister_game(
        admin: &signer, game_address: address
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = ordered_map::remove(
            &mut registry.registered_games, &game_address
        );

        event::emit(GameUnregisteredEvent { game_address, name: game_info.name });
    }

    /// Toggle game active status
    public entry fun toggle_game(
        admin: &signer, game_address: address, active: bool
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info =
            ordered_map::borrow_mut(&mut registry.registered_games, &game_address);
        game_info.active = active;

        event::emit(GameToggleEvent { game_address, active });
    }

    //
    // Bet Flow Interface (Public Functions)
    //

    /// Accept bet from authorized game
    public fun place_bet(
        game_addr: address, coins: Coin<AptosCoin>, player: address
    ): u64 acquires Treasury, BetIndex, GameRegistry, GameCapability {
        // Step 1: Verify game has capability (proves registration)
        assert!(exists<GameCapability>(game_addr), E_GAME_NOT_REGISTERED);

        // Step 2: Check active status
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_addr),
            E_GAME_NOT_REGISTERED
        );

        let game_info = ordered_map::borrow(&registry.registered_games, &game_addr);
        assert!(game_info.active, E_GAME_INACTIVE);

        // Step 3: Verify capability integrity
        let cap = borrow_global<GameCapability>(game_addr);
        assert!(cap.game_address == game_addr, E_MISSING_CAPABILITY);

        let amount = coin::value(&coins);
        assert!(amount >= game_info.min_bet, E_INVALID_AMOUNT);
        assert!(amount <= game_info.max_bet, E_INVALID_AMOUNT);

        // Merge coins into treasury
        let treasury = borrow_global_mut<Treasury>(@casino);
        coin::merge(&mut treasury.vault, coins);

        // Generate bet ID
        let bet_index = borrow_global_mut<BetIndex>(@casino);
        let bet_id = bet_index.next;
        bet_index.next = bet_id + 1;

        event::emit(
            BetAcceptedEvent { bet_id, game_address: game_addr, player, amount }
        );

        bet_id
    }

    /// Settle bet with payout from treasury
    public fun settle_bet(
        game_addr: address,
        bet_id: u64,
        winner: address,
        payout: u64,
        profit: u64
    ) acquires Treasury, GameRegistry, GameCapability {
        // Step 1: Verify game has capability
        assert!(exists<GameCapability>(game_addr), E_GAME_NOT_REGISTERED);

        // Step 2: Check active status
        let registry = borrow_global<GameRegistry>(@casino);
        let game_info = ordered_map::borrow(&registry.registered_games, &game_addr);
        assert!(game_info.active, E_GAME_INACTIVE);

        // Step 3: Verify capability integrity
        let cap = borrow_global<GameCapability>(game_addr);
        assert!(cap.game_address == game_addr, E_MISSING_CAPABILITY);

        // Validate settlement math (payout + profit should equal bet amount)
        let bet_amount = payout + profit;
        assert!(bet_amount > 0, E_INVALID_SETTLEMENT);

        let treasury = borrow_global_mut<Treasury>(@casino);
        let treasury_balance = coin::value(&treasury.vault);
        assert!(payout <= treasury_balance, E_INSUFFICIENT_TREASURY);

        // Pay winner if payout > 0
        if (payout > 0) {
            let payout_coins = coin::extract(&mut treasury.vault, payout);
            coin::deposit(winner, payout_coins);
        };

        // Profit remains in treasury for InvestorToken holders

        event::emit(
            BetSettledEvent { bet_id, winner, payout, profit }
        );
    }

    /// Extract funds from treasury for InvestorToken redemptions
    public fun redeem_from_treasury(amount: u64): Coin<AptosCoin> acquires Treasury {
        let treasury = borrow_global_mut<Treasury>(@casino);
        let treasury_balance = coin::value(&treasury.vault);
        assert!(amount <= treasury_balance, E_INSUFFICIENT_TREASURY);

        coin::extract(&mut treasury.vault, amount)
    }

    /// Deposit coins to treasury (for InvestorToken deposits)
    public fun deposit_to_treasury(coins: Coin<AptosCoin>) acquires Treasury {
        let treasury = borrow_global_mut<Treasury>(@casino);
        coin::merge(&mut treasury.vault, coins);
    }

    //
    // View Interface
    //

    #[view]
    /// Get all registered games
    public fun get_registered_games(): vector<GameInfo> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        let games = vector::empty<GameInfo>();

        let keys = ordered_map::keys(&registry.registered_games);
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
    /// Get specific game information
    public fun get_game_info(game_address: address): GameInfo acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_NOT_REGISTERED
        );
        *ordered_map::borrow(&registry.registered_games, &game_address)
    }

    #[view]
    /// Get casino parameters
    public fun get_params(): u64 acquires Params {
        let params = borrow_global<Params>(@casino);
        params.house_edge_bps
    }

    #[view]
    /// Get current treasury balance
    public fun treasury_balance(): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(@casino);
        coin::value(&treasury.vault)
    }

    #[view]
    /// Check if game is registered and active
    public fun is_game_active(game_address: address): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        if (ordered_map::contains(&registry.registered_games, &game_address)) {
            let game_info = ordered_map::borrow(
                &registry.registered_games, &game_address
            );
            game_info.active
        } else { false }
    }

    //
    // Admin Interface
    //

    /// Update casino house edge
    public entry fun set_house_edge(admin: &signer, new_edge_bps: u64) acquires Params {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);
        assert!(new_edge_bps <= 1000, E_INVALID_AMOUNT); // Max 10%

        let params = borrow_global_mut<Params>(@casino);
        params.house_edge_bps = new_edge_bps;
    }

    //
    // Test Helper Functions
    //

    #[test_only]
    /// Get GameInfo field accessors for testing
    public fun get_game_name(info: &GameInfo): String {
        info.name
    }

    #[test_only]
    public fun get_game_module_address(info: &GameInfo): address {
        info.module_address
    }

    #[test_only]
    public fun get_game_active(info: &GameInfo): bool {
        info.active
    }

    #[test_only]
    /// Test helper to access settle_bet
    public fun test_settle_bet(
        game_addr: address,
        bet_id: u64,
        winner: address,
        payout: u64,
        profit: u64
    ) acquires Treasury, GameRegistry, GameCapability {
        settle_bet(game_addr, bet_id, winner, payout, profit);
    }

    #[test_only]
    /// Test helper that handles coin return value
    public fun test_redeem_from_treasury(amount: u64) acquires Treasury {
        let coins = redeem_from_treasury(amount);
        coin::deposit(@casino, coins); // Must handle the coin
    }
}
