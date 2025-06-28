//! Integration tests between CasinoHouse and InvestorToken modules
//!
//! Tests cross-module interactions, treasury synchronization, and profit flow.

#[test_only]
module casino::IntegrationTest {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;
    use casino::InvestorToken;

    const INITIAL_INVESTMENT: u64 = 500000000; // 5 APT
    const BIG_BET: u64 = 200000000; // 2 APT
    const PLAYER_BALANCE: u64 = 300000000; // 3 APT

    #[test]
    #[expected_failure(abort_code = casino::InvestorToken::E_INSUFFICIENT_TREASURY, location = casino::InvestorToken)]
    fun test_treasury_depleted_by_game_payouts() {
    // Setup framework
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_account = account::create_account_for_test(@casino);
        let game_account = account::create_account_for_test(@0x123);
        let investor = account::create_account_for_test(@0x111);
        let player1 = account::create_account_for_test(@0x222);
        let player2 = account::create_account_for_test(@0x333);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(1000000);

        // Register accounts
        coin::register<AptosCoin>(&casino_account);
        coin::register<AptosCoin>(&game_account);
        coin::register<AptosCoin>(&investor);
        coin::register<AptosCoin>(&player1);
        coin::register<AptosCoin>(&player2);

        // Fund accounts
        aptos_coin::mint(&aptos_framework, @casino, 1000000000);
        aptos_coin::mint(&aptos_framework, @0x111, INITIAL_INVESTMENT);
        aptos_coin::mint(&aptos_framework, @0x222, PLAYER_BALANCE);
        aptos_coin::mint(&aptos_framework, @0x333, PLAYER_BALANCE);

        // Initialize modules
        CasinoHouse::init_module_for_test(&casino_account);
        InvestorToken::init(&casino_account);

        // Register game
        CasinoHouse::register_game(
            &casino_account,
            signer::address_of(&game_account),
            string::utf8(b"TestGame"),
            1000000, // 0.01 APT min
            500000000, // 5 APT max
            150 // 1.5% house edge
        );

        // Investor buys tokens (funds treasury)
        InvestorToken::deposit_and_mint(&investor, INITIAL_INVESTMENT);

        // Treasury should have INITIAL_INVESTMENT
        assert!(CasinoHouse::treasury_balance() == INITIAL_INVESTMENT, 1);

        // Simulate consecutive big payouts that drain treasury
        
        // Big payout 1
        let small_bet1 = 1000000; // 0.01 APT bet
        let coins1 = coin::withdraw<AptosCoin>(&player1, small_bet1);
        let bet_id1 = CasinoHouse::place_bet(&game_account, coins1, @0x222, 200000000); // 2 APT expected payout
        CasinoHouse::settle_bet(
            &game_account, 
            bet_id1, 
            @0x222, 
            200000000 // 2 APT payout
        );

        // Big payout 2  
        let small_bet2 = 1000000; // 0.01 APT bet
        let coins2 = coin::withdraw<AptosCoin>(&player2, small_bet2);
        let bet_id2 = CasinoHouse::place_bet(&game_account, coins2, @0x333, 200000000); // 2 APT expected payout
        CasinoHouse::settle_bet(
            &game_account,
            bet_id2,
            @0x333,
            200000000 // 2 APT payout
        );

        // Big payout 3
        let small_bet3 = 1000000; // 0.01 APT bet
        let coins3 = coin::withdraw<AptosCoin>(&player1, small_bet3);
        let bet_id3 = CasinoHouse::place_bet(&game_account, coins3, @0x222, 100000000); // 1 APT expected payout
        CasinoHouse::settle_bet(
            &game_account,
            bet_id3,
            @0x222,
            100000000 // 1 APT payout
        );

        // Treasury: 5 + 0.03 - 2 - 2 - 1 = 0.03 APT remaining
        // Investor tries to redeem 5 APT worth of tokens, needs ~5 APT from treasury
        
        // This should fail due to insufficient treasury
        InvestorToken::redeem(&investor, INITIAL_INVESTMENT);
    }
}