//! MIT License
//!
//! Slot Machine Game for ChainCasino Platform (Refactored for FA)
//!
//! 3-reel slot machine with weighted symbols and secure randomness.
//! Features 5 symbols with varying rarity and payouts for balanced gameplay.

module slot_game::SlotMachine {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use std::signer;
    use std::option;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin;
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

    /// Symbol weights for weighted random selection
    const CHERRY_WEIGHT: u8 = 40; // 0-39
    const BELL_WEIGHT: u8 = 30; // 40-69
    const COIN_WEIGHT: u8 = 20; // 70-89
    const CHAIN_WEIGHT: u8 = 8; // 90-97
    const SEVEN_WEIGHT: u8 = 2; // 98-99

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

    /// Stores the game's authorization capability at @slot_game
    struct GameAuth has key {
        capability: GameCapability
    }

    //
    // Event Specifications
    //

    #[event]
    /// Emitted when slot reels are spun and bet is resolved
    struct SlotSpinEvent has drop, store {
        bet_id: u64,
        player: address,
        bet_amount: u64,
        reel1: u8,
        reel2: u8,
        reel3: u8,
        won: bool,
        payout: u64,
        symbol_name: vector<u8>
    }

    #[event]
    /// Emitted when game successfully initializes
    struct GameInitialized has drop, store {
        game_address: address,
        min_bet: u64,
        max_bet: u64,
        house_edge_bps: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize slot machine game - claims capability from casino
    public entry fun initialize_game(slot_admin: &signer) {
        assert!(signer::address_of(slot_admin) == @slot_game, E_UNAUTHORIZED);
        assert!(!exists<GameAuth>(@slot_game), E_ALREADY_INITIALIZED);
        assert!(CasinoHouse::is_game_registered(@slot_game), E_GAME_NOT_REGISTERED);

        let capability = CasinoHouse::get_game_capability(slot_admin);
        move_to(slot_admin, GameAuth { capability });

        event::emit(
            GameInitialized {
                game_address: @slot_game,
                min_bet: MIN_BET,
                max_bet: MAX_BET,
                house_edge_bps: HOUSE_EDGE_BPS
            }
        );
    }

    //
    // Core Game Interface - REFACTORED
    //

    #[randomness]
    /// Spin the slot machine reels - now uses FungibleAsset operations
    entry fun spin_slots(player: &signer, bet_amount: u64) acquires GameAuth {
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);
        let expected_payout = bet_amount * SEVEN_PAYOUT; // Maximum possible payout

        // Withdraw bet as FungibleAsset from player
        let aptos_metadata_option =
            coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        let aptos_metadata = option::extract(&mut aptos_metadata_option);
        let bet_fa = primary_fungible_store::withdraw(player, aptos_metadata, bet_amount);

        // Get stored capability
        let game_auth = borrow_global<GameAuth>(@slot_game);
        let capability = &game_auth.capability;

        // Place bet with casino (FA gets deposited to treasury)
        let bet_id =
            CasinoHouse::place_bet(
                capability,
                bet_fa,
                player_addr,
                expected_payout
            );

        // Spin the three reels
        let reel1 = spin_reel_internal();
        let reel2 = spin_reel_internal();
        let reel3 = spin_reel_internal();

        // Calculate actual payout
        let (payout_multiplier, symbol_name) =
            calculate_payout_internal(reel1, reel2, reel3);
        let actual_payout = bet_amount * payout_multiplier;
        let player_won = payout_multiplier > 0;

        // Settle bet (casino handles FA transfer to winner if any)
        CasinoHouse::settle_bet(capability, bet_id, player_addr, actual_payout);

        event::emit(
            SlotSpinEvent {
                bet_id,
                player: player_addr,
                bet_amount,
                reel1,
                reel2,
                reel3,
                won: player_won,
                payout: actual_payout,
                symbol_name
            }
        );
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Test version allowing unsafe randomness
    public entry fun test_only_spin_slots(
        player: &signer, bet_amount: u64
    ) acquires GameAuth {
        spin_slots(player, bet_amount);
    }

    //
    // Internal Game Logic
    //

    #[lint::allow_unsafe_randomness]
    fun spin_reel_internal(): u8 {
        let rand_value = randomness::u8_range(0, 100);

        if (rand_value < CHERRY_WEIGHT) {
            SYMBOL_CHERRY
        } else if (rand_value < CHERRY_WEIGHT + BELL_WEIGHT) {
            SYMBOL_BELL
        } else if (rand_value < CHERRY_WEIGHT + BELL_WEIGHT + COIN_WEIGHT) {
            SYMBOL_COIN
        } else if (rand_value
            < CHERRY_WEIGHT + BELL_WEIGHT + COIN_WEIGHT + CHAIN_WEIGHT) {
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
    public fun is_registered(): bool {
        CasinoHouse::is_game_registered(@slot_game)
    }

    #[view]
    public fun is_initialized(): bool {
        exists<GameAuth>(@slot_game)
    }

    #[view]
    public fun is_ready(): bool {
        is_registered() && is_initialized()
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
