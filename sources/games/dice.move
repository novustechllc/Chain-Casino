//! MIT License
//!
//! Simple Dice Game for ChainCasino Platform
//!
//! Single die guessing game where players bet on the exact outcome (1-6).
//! 6x payout odds with ~16.67% house edge.

module dice_game::DiceGame {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
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

    //
    // Resources
    //

    /// Stores the game's authorization capability at @dice_game
    struct GameAuth has key {
        capability: GameCapability
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
    /// Emitted when game successfully initializes
    struct GameInitialized has drop, store {
        game_address: address,
        min_bet: u64,
        max_bet: u64,
        payout_multiplier: u64,
        house_edge_bps: u64
    }

    //
    // Initialization Interface
    //

    /// Initialize dice game - claims capability from casino
    /// Prerequisites: Casino admin must have called CasinoHouse::register_game first
    public entry fun initialize_game(dice_admin: &signer) {
        assert!(signer::address_of(dice_admin) == @dice_game, E_UNAUTHORIZED);

        // Check if already initialized
        assert!(!exists<GameAuth>(@dice_game), E_ALREADY_INITIALIZED);

        // Verify game is registered by casino
        assert!(CasinoHouse::is_game_registered(@dice_game), E_GAME_NOT_REGISTERED);

        // Claim capability from casino (proves dice_game identity)
        let capability = CasinoHouse::get_game_capability(dice_admin);

        // Store capability at dice game's own address
        let game_auth = GameAuth { capability };
        move_to(dice_admin, game_auth);

        // Emit initialization event
        event::emit(
            GameInitialized {
                game_address: @dice_game,
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
    /// Play dice game - player signs transaction, module calls casino
    entry fun play_dice(player: &signer, guess: u8, bet_amount: u64) acquires GameAuth {
        // Validate inputs
        assert!(guess >= 1 && guess <= 6, E_INVALID_GUESS);
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Calculate expected payout if player wins
        let expected_payout = bet_amount * PAYOUT_MULTIPLIER;

        // Player provides bet coins
        let bet_coins = coin::withdraw<AptosCoin>(player, bet_amount);

        // Get stored capability from dice game address
        let game_auth = borrow_global<GameAuth>(@dice_game);
        let capability = &game_auth.capability;

        // Module calls casino with capability authorization
        let bet_id =
            CasinoHouse::place_bet(
                capability,
                bet_coins,
                player_addr,
                expected_payout
            );

        // Roll the dice (1-6)
        let dice_result = randomness::u8_range(1, 7);

        // Determine outcome
        let player_won = dice_result == guess;
        let actual_payout = if (player_won) {
            expected_payout
        } else { 0 };

        // Settle bet through CasinoHouse
        CasinoHouse::settle_bet(capability, bet_id, player_addr, actual_payout);

        // Emit game event
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

    // Test only
    #[test_only]
    #[lint::allow_unsafe_randomness]
    /// Play dice game - player signs transaction, module calls casino
    public entry fun test_only_play_dice(
        player: &signer, guess: u8, bet_amount: u64
    ) acquires GameAuth {
        play_dice(player, guess, bet_amount);
    }

    //
    // View Functions
    //

    #[view]
    /// Get game configuration
    public fun get_game_config(): (u64, u64, u64, u64) {
        (MIN_BET, MAX_BET, PAYOUT_MULTIPLIER, HOUSE_EDGE_BPS)
    }

    #[view]
    /// Calculate expected payout for a bet amount
    public fun calculate_payout(bet_amount: u64): u64 {
        bet_amount * PAYOUT_MULTIPLIER
    }

    #[view]
    /// Check if game is registered with CasinoHouse
    public fun is_registered(): bool {
        CasinoHouse::is_game_registered(@dice_game)
    }

    #[view]
    /// Check if game is fully initialized (has capability)
    public fun is_initialized(): bool {
        exists<GameAuth>(@dice_game)
    }

    #[view]
    /// Check if game is ready to accept bets (registered + initialized)
    public fun is_ready(): bool {
        is_registered() && is_initialized()
    }
}
