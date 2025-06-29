//! LICENSE: GPL-3.0
//!
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
    // Constants
    //

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
        capability_claimed: bool
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
    /// Emitted when bet is accepted by casino
    struct BetAcceptedEvent has drop, store {
        bet_id: u64,
        game_address: address,
        player: address,
        amount: u64,
        expected_payout: u64
    }

    #[event]
    /// Emitted when bet is settled with payout
    struct BetSettledEvent has drop, store {
        bet_id: u64,
        winner: address,
        payout: u64
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
    /// Emitted when game claims its capability
    struct GameCapabilityClaimedEvent has drop, store {
        game_address: address,
        name: String
    }

    //
    // Initialization Interface
    //

    /// Initialize casino house with treasury and game registry
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        move_to(
            admin,
            Treasury { vault: coin::zero<AptosCoin>() }
        );

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

    /// Register new game by address (casino admin only)
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

        // Check if game already registered
        assert!(
            !ordered_map::contains(&registry.registered_games, &game_address),
            E_GAME_ALREADY_REGISTERED
        );

        // Validate game info
        assert!(max_bet >= min_bet, E_INVALID_AMOUNT);

        // Store game info with capability_claimed = false
        let game_info = GameInfo {
            name,
            module_address: game_address,
            min_bet,
            max_bet,
            house_edge_bps,
            capability_claimed: false
        };

        registry.registered_games.add(game_address, game_info);

        event::emit(
            GameRegisteredEvent { game_address, name, module_address: game_address }
        );
    }

    /// Game claims its capability (only if registered and not already claimed)
    public fun get_game_capability(game_signer: &signer): GameCapability acquires GameRegistry {
        let game_address = signer::address_of(game_signer);

        let registry = borrow_global_mut<GameRegistry>(@casino);

        // Check if game is registered
        assert!(
            registry.registered_games.contains(&game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = registry.registered_games.borrow_mut(&game_address);

        // Check if capability already claimed
        assert!(!game_info.capability_claimed, E_CAPABILITY_ALREADY_CLAIMED);

        // Mark capability as claimed
        game_info.capability_claimed = true;

        // Emit capability claimed event
        event::emit(GameCapabilityClaimedEvent { game_address, name: game_info.name });

        // Return capability for game authorization
        GameCapability { game_address }
    }

    /// Remove game from registry (casino admin only)
    public entry fun unregister_game(
        admin: &signer, game_address: address
    ) acquires GameRegistry {
        assert!(signer::address_of(admin) == @casino, E_NOT_ADMIN);

        // Remove from game registry
        let registry = borrow_global_mut<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&game_address),
            E_GAME_NOT_REGISTERED
        );

        let game_info = registry.registered_games.remove(&game_address);
        event::emit(GameUnregisteredEvent { game_address, name: game_info.name });
    }

    //
    // Bet Flow Interface (Public Functions)
    //

    /// Accept bet from authorized game
    public fun place_bet(
        capability: &GameCapability,
        coins: Coin<AptosCoin>,
        player: address,
        expected_payout: u64
    ): u64 acquires Treasury, BetIndex, GameRegistry, BetRegistry {
        let game_addr = capability.game_address;
        let amount = coin::value(&coins);

        // Mandatory game registry check
        let registry = borrow_global<GameRegistry>(@casino);
        assert!(
            registry.registered_games.contains(&game_addr),
            E_GAME_NOT_REGISTERED
        );
        let game_info = registry.registered_games.borrow(&game_addr);
        assert!(amount >= game_info.min_bet, E_INVALID_AMOUNT);
        assert!(amount <= game_info.max_bet, E_INVALID_AMOUNT);

        // Validate expected payout
        assert!(expected_payout > 0, E_INVALID_AMOUNT);

        // Merge coins into treasury first
        let treasury_mut = borrow_global_mut<Treasury>(@casino);
        coin::merge(&mut treasury_mut.vault, coins);
        let treasury_balance = coin::value(&treasury_mut.vault);

        // Check if treasury has sufficient funds for expected payout after bet contribution
        assert!(
            expected_payout <= treasury_balance + amount,
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
    ) acquires Treasury, BetRegistry, GameRegistry {
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

        // Mark bet as settled
        bet_info.settled = true;

        let treasury = borrow_global_mut<Treasury>(@casino);
        let treasury_balance = coin::value(&treasury.vault);
        assert!(payout <= treasury_balance, E_INSUFFICIENT_TREASURY);

        // Pay winner if payout > 0
        if (payout > 0) {
            let payout_coins = coin::extract(&mut treasury.vault, payout);
            coin::deposit(winner, payout_coins);
        };

        // Profit remains in treasury for InvestorToken holders

        event::emit(BetSettledEvent { bet_id, winner, payout });
    }

    /// Extract funds from treasury for InvestorToken redemptions
    package fun redeem_from_treasury(amount: u64): Coin<AptosCoin> acquires Treasury {
        let treasury = borrow_global_mut<Treasury>(@casino);
        let treasury_balance = coin::value(&treasury.vault);
        assert!(amount <= treasury_balance, E_INSUFFICIENT_TREASURY);

        coin::extract(&mut treasury.vault, amount)
    }

    /// Deposit coins to treasury (for InvestorToken deposits)
    package fun deposit_to_treasury(coins: Coin<AptosCoin>) acquires Treasury {
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
    /// Get current treasury balance
    public fun treasury_balance(): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(@casino);
        coin::value(&treasury.vault)
    }

    #[view]
    /// Check if game is registered
    public fun is_game_registered(game_address: address): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@casino);
        ordered_map::contains(&registry.registered_games, &game_address)
    }

    #[view]
    /// Check if game has claimed its capability
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
