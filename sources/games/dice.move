//! Simple Dice Game for ChainCasino Platform
//!
//! Single die guessing game where players bet on the exact outcome (1-6).
//! 6x payout odds with ~16.67% house edge.

module dice_game::DiceGame {
    use aptos_framework::randomness;
    use aptos_framework::event;
    use std::signer;
    use std::string;
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

    /// Stores the game's authorization capability
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

    //
    // Initialization Interface
    //

    /// Initialize game and get capability from casino
    public entry fun initialize_game(casino_admin: &signer) {
        let capability =
            CasinoHouse::register_game(
                casino_admin,
                @dice_game,
                string::utf8(b"Dice Game"),
                MIN_BET,
                MAX_BET,
                HOUSE_EDGE_BPS
            );

        let game_auth = GameAuth { capability };
        move_to(casino_admin, game_auth); // Store at casino admin address
    }

    //
    // Core Game Interface
    //

    #[lint::allow_unsafe_randomness]
    /// Play dice game - player signs transaction, module calls casino
    public entry fun play_dice(
        player: &signer, guess: u8, bet_amount: u64
    ) acquires GameAuth {
        // Validate inputs
        assert!(guess >= 1 && guess <= 6, E_INVALID_GUESS);
        assert!(bet_amount >= MIN_BET, E_INVALID_AMOUNT);
        assert!(bet_amount <= MAX_BET, E_INVALID_AMOUNT);

        let player_addr = signer::address_of(player);

        // Calculate expected payout if player wins
        let expected_payout = bet_amount * PAYOUT_MULTIPLIER;

        // Player provides bet coins
        let bet_coins = coin::withdraw<AptosCoin>(player, bet_amount);

        // Get stored capability
        let game_auth = borrow_global<GameAuth>(@casino);
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
        let dice_result = roll_dice_internal();

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

    #[lint::allow_unsafe_randomness]
    fun roll_dice_internal(): u8 {
        randomness::u8_range(1, 7)
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
}
