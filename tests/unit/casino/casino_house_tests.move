//! MIT License
//!
//! Focused Unit Tests for CasinoHouse Module
//!
//! Tests only business logic that makes sense at unit level:
//! - Initialization validation
//! - Game registration business rules
//! - Limit management validation
//! - View function correctness
//! - Error conditions through public APIs

#[test_only]
module casino::CasinoHouseTests {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::Self;
    use aptos_framework::timestamp;
    use casino::CasinoHouse;

    // Test constants
    const CASINO_ADMIN: address = @casino;
    const GAME_MODULE_1: address = @0x1001;
    const GAME_MODULE_2: address = @0x1002;
    const UNAUTHORIZED_USER: address = @0x2001;

    const INITIAL_FUNDING: u64 = 10000000000; // 100 APT

    /// Minimal setup for business logic testing
    fun setup_basic(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let casino_admin = account::create_account_for_test(CASINO_ADMIN);
        let unauthorized = account::create_account_for_test(UNAUTHORIZED_USER);

        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        (aptos_framework, casino_admin, unauthorized)
    }

    // ========================================================================================
    // INITIALIZATION BUSINESS LOGIC
    // ========================================================================================

    #[test]
    fun test_init_creates_empty_registries() {
        let (_, casino_admin, _) = setup_basic();

        CasinoHouse::init_module_for_test(&casino_admin);

        // Verify clean initial state
        assert!(CasinoHouse::treasury_balance() == 0, 1);
        assert!(CasinoHouse::central_treasury_balance() == 0, 2);

        let games = CasinoHouse::get_registered_games();
        assert!(vector::length(&games) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_NOT_ADMIN)]
    fun test_init_fails_wrong_admin() {
        let (_, _, unauthorized) = setup_basic();

        CasinoHouse::init_module_for_test(&unauthorized);
    }

    // ========================================================================================
    // GAME REGISTRATION BUSINESS RULES
    // ========================================================================================

    #[test]
    #[expected_failure(abort_code = casino::CasinoHouse::E_INVALID_AMOUNT)]
    fun test_register_game_fails_invalid_limits() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            50000000,
            1000000,
            1500 // max < min
        );
    }

    #[test]
    #[expected_failure]
    // Object creation prevents duplicates at framework level
    fun test_register_duplicate_game_fails() {
        let (_, casino_admin, _) = setup_basic();
        CasinoHouse::init_module_for_test(&casino_admin);

        // Register once
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );

        // Try to register same game again - object creation will fail
        CasinoHouse::register_game(
            &casino_admin,
            GAME_MODULE_1,
            string::utf8(b"TestGame"),
            string::utf8(b"v1"),
            1000000,
            50000000,
            1500
        );
    }

    // ========================================================================================
    // VIEW FUNCTION CORRECTNESS
    // ========================================================================================

    #[test]
    fun test_derive_game_object_address_deterministic() {
        // Test deterministic address derivation
        let addr1 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN, string::utf8(b"TestGame"), string::utf8(b"v1")
            );
        let addr2 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN, string::utf8(b"TestGame"), string::utf8(b"v1")
            );
        let addr3 =
            CasinoHouse::derive_game_object_address(
                CASINO_ADMIN,
                string::utf8(b"TestGame"),
                string::utf8(b"v2") // Different version
            );

        assert!(addr1 == addr2, 1); // Same inputs = same address
        assert!(addr1 != addr3, 2); // Different inputs = different address
    }

}
