# InvestorToken Smart Contract Specifications

## 1. Overview

This document outlines the specifications for the `InvestorToken` smart contract, implemented in Move for the Aptos blockchain. The contract manages NAV-based investor tokens for the ChainCasino platform, allowing users to deposit AptosCoin (APT) to mint InvestorTokens and redeem InvestorTokens for APT based on the current Net Asset Value (NAV).

## 2. Module Details

*   **Module Name:** `casino::InvestorTokenInterface`
*   **Purpose:** Implements NAV-based investor tokens for the ChainCasino platform.

## 3. Error Codes

The following error codes are defined within the contract:

*   `E_UNAUTHORIZED_INIT (0x70)`: InvestorToken initialization not called by `@casino`.
*   `E_INVALID_AMOUNT (0x71)`: Invalid amount (zero or exceeds limits) provided for an operation.
*   `E_INSUFFICIENT_BALANCE (0x72)`: Insufficient Fungible Asset (FA) balance for the requested operation.
*   `E_INSUFFICIENT_TREASURY (0x73)`: Treasury balance is insufficient for token redemption.
*   `E_INVALID_METADATA (0x74)`: Invalid Fungible Asset metadata object.
*   `E_TRANSFERS_FROZEN (0x75)`: Fungible Asset transfers are currently frozen.

## 4. Constants

The contract utilizes the following constants:

*   `NAV_SCALE (1_000_000)`: Fixed-point scale for NAV calculations, representing 6 decimal places.
*   `DEFAULT_FEE_BPS (10)`: Default redemption fee of 0.1% (10 basis points).
*   `MIN_FEE_APT (1_000)`: Minimum redemption fee of 0.001 APT in octas.
*   `MAX_SAFE_MULTIPLY (18446744073709551)`: Maximum safe multiplication value to prevent overflow (u64::MAX / NAV_SCALE).

## 5. Resources (Structs)

### 5.1. `InvestorTokenRefs`

*   **Purpose:** Stores capability references required for Fungible Asset operations.
*   **Fields:**
    *   `mint_ref`: `MintRef` - Reference for minting InvestorTokens.
    *   `burn_ref`: `BurnRef` - Reference for burning InvestorTokens.
    *   `transfer_ref`: `TransferRef` - Reference for transferring InvestorTokens.
    *   `extend_ref`: `ExtendRef` - Reference for extending the object.

### 5.2. `DividendMetadata`

*   **Purpose:** Holds economic metadata for tracking dividends and treasury backing.
*   **Fields:**
    *   `treasury_backing_ratio`: `u64` - The ratio of treasury backing per token, updated with NAV.
    *   `total_dividends_paid`: `u64` - Accumulates the total amount of dividends paid out.
    *   `creation_timestamp`: `u64` - Timestamp of the contract's creation.

### 5.3. `MockTreasury`

*   **Purpose:** A mock treasury used for standalone testing of the contract. In a production environment, this would be replaced by integration with the `CasinoHouse` module.
*   **Fields:**
    *   `vault`: `coin::Coin<AptosCoin>` - A vault holding AptosCoin for the treasury.

## 6. Events

### 6.1. `DividendPaidEvent`

*   **Purpose:** Emitted when an investor redeems tokens and realizes a profit.
*   **Fields:**
    *   `recipient`: `address` - The address of the user who received the dividend.
    *   `amount`: `u64` - The amount of profit (dividend) paid.

## 7. Initialization Interface

### 7.1. `init(owner: &signer)`

*   **Function Type:** `public entry fun`
*   **Description:** Initializes the InvestorToken fungible asset. This function can only be called by the `@casino` address.
*   **Actions:**
    *   Asserts that the caller is the `@casino` address.
    *   Creates a named object for `InvestorToken`.
    *   Initializes a primary fungible store for the asset with name "ChainCasino Investor Token", symbol "CCIT", and 8 decimal places.
    *   Generates and stores `MintRef`, `BurnRef`, `TransferRef`, and `ExtendRef` capabilities in `InvestorTokenRefs`.
    *   Initializes `DividendMetadata` with `treasury_backing_ratio` set to `NAV_SCALE`, `total_dividends_paid` to 0, and `creation_timestamp` to the current time.
    *   Initializes `MockTreasury` with an empty `AptosCoin` vault for testing purposes.

## 8. Core Economic Interface

### 8.1. `nav(): u64 acquires MockTreasury`

*   **Function Type:** `public view fun`
*   **Description:** Calculates the current Net Asset Value (NAV) per token. Includes safe overflow handling using `u128` arithmetic.
*   **Returns:** `u64` - The calculated NAV per token.
*   **Logic:**
    *   If `total_supply` is 0, returns `NAV_SCALE`.
    *   Otherwise, calculates `(treasury_balance * NAV_SCALE) / total_supply` using `u128` to prevent overflow.

### 8.2. `deposit_and_mint(user: &signer, amount: u64) acquires InvestorTokenRefs, DividendMetadata, MockTreasury`

*   **Function Type:** `public entry fun`
*   **Description:** Allows a user to deposit APT and mint a proportional amount of InvestorTokens.
*   **Parameters:**
    *   `user`: `&signer` - The signer of the user depositing APT.
    *   `amount`: `u64` - The amount of APT to deposit.
*   **Actions:**
    *   Asserts that `amount` is greater than 0.
    *   Calculates the number of tokens to mint based on the current `treasury_balance` and `total_supply` to maintain proportionality. Uses `u128` for overflow prevention.
    *   Withdraws `amount` of `AptosCoin` from the user.
    *   Deposits the withdrawn `AptosCoin` into the `MockTreasury`.
    *   Mints the calculated `tokens_to_mint` to the user.
    *   Ensures the user has a primary fungible store and deposits the minted tokens.
    *   Updates the NAV tracking by calling `update_nav_tracking()`.

### 8.3. `redeem(user: &signer, tokens: u64) acquires InvestorTokenRefs, DividendMetadata, MockTreasury`

*   **Function Type:** `public entry fun`
*   **Description:** Allows a user to burn InvestorTokens and redeem APT at the current NAV.
*   **Parameters:**
    *   `user`: `&signer` - The signer of the user redeeming tokens.
    *   `tokens`: `u64` - The amount of InvestorTokens to burn.
*   **Actions:**
    *   Asserts that `tokens` is greater than 0.
    *   Asserts that the user has sufficient InvestorToken balance.
    *   Calculates the `gross_amount` of APT to be redeemed based on `tokens` and `current_nav`. Uses `u128` for overflow prevention.
    *   Calculates the `fee` using `calculate_fee()`.
    *   Determines the `net_amount` after deducting the fee.
    *   Asserts that the `net_amount` is less than or equal to the `treasury_balance`.
    *   Burns the specified `tokens` from the user's balance.
    *   If `net_amount` is greater than 0, withdraws `net_amount` of APT from the `MockTreasury` and deposits it to the user.
    *   Calculates the `profit` (if any) for the dividend event.
    *   Emits a `DividendPaidEvent` with the recipient's address and the profit amount.
    *   Updates the NAV tracking by calling `update_nav_tracking()`.

## 9. Fee Calculation Interface

### 9.1. `calculate_fee(gross_amount: u64): u64`

*   **Function Type:** `fun` (internal)
*   **Description:** Calculates the redemption fee based on the gross amount.
*   **Parameters:**
    *   `gross_amount`: `u64` - The gross amount of APT to be redeemed.
*   **Returns:** `u64` - The calculated fee.
*   **Logic:**
    *   Calculates a percentage fee: `(gross_amount * DEFAULT_FEE_BPS) / 10000`.
    *   Returns the maximum of the calculated percentage fee and `MIN_FEE_APT`.

## 10. View Interface

### 10.1. `get_metadata(): Object<Metadata>`

*   **Function Type:** `public view fun`
*   **Description:** Retrieves the `Metadata` object for the InvestorToken.
*   **Returns:** `Object<Metadata>` - The metadata object.

### 10.2. `get_dividend_info(): (u64, u64, u64) acquires DividendMetadata`

*   **Function Type:** `public view fun`
*   **Description:** Retrieves dividend- related information.
*   **Returns:** `(u64, u64, u64)` - A tuple containing `treasury_backing_ratio`, `total_dividends_paid`, and `creation_timestamp` from `DividendMetadata`.

### 10.3. `user_balance(user: address): u64`

*   **Function Type:** `public view fun`
*   **Description:** Returns the InvestorToken balance of a given user address.
*   **Parameters:**
    *   `user`: `address` - The address of the user.
*   **Returns:** `u64` - The user's InvestorToken balance.

### 10.4. `total_supply(): u64`

*   **Function Type:** `public view fun`
*   **Description:** Returns the total supply of InvestorTokens.
*   **Returns:** `u64` - The total supply.

### 10.5. `treasury_balance(): u64 acquires MockTreasury`

*   **Function Type:** `public view fun`
*   **Description:** Returns the current balance of APT in the `MockTreasury`.
*   **Returns:** `u64` - The treasury's APT balance.

## 11. Mock Treasury Functions (Internal)

These functions are primarily for testing and will be replaced by integration with `CasinoHouse` in a full implementation.

### 11.1. `deposit_to_treasury(coins: coin::Coin<AptosCoin>) acquires MockTreasury`

*   **Function Type:** `fun` (internal)
*   **Description:** Deposits `AptosCoin` into the `MockTreasury` vault.
*   **Parameters:**
    *   `coins`: `coin::Coin<AptosCoin>` - The coins to deposit.

### 11.2. `redeem_from_treasury(amount: u64): coin::Coin<AptosCoin> acquires MockTreasury`

*   **Function Type:** `fun` (internal)
*   **Description:** Redeems a specified amount of `AptosCoin` from the `MockTreasury` vault.
*   **Parameters:**
    *   `amount`: `u64` - The amount of APT to redeem.
*   **Returns:** `coin::Coin<AptosCoin>` - The redeemed coins.

### 11.3. `update_nav_tracking() acquires DividendMetadata, MockTreasury`

*   **Function Type:** `fun` (internal)
*   **Description:** Updates the `treasury_backing_ratio` in `DividendMetadata` to the current NAV.

## 12. Test Helper Functions

### 12.1. `inject_treasury_profit(profit: coin::Coin<AptosCoin>) acquires MockTreasury`

*   **Function Type:** `public test_only fun`
*   **Description:** A test-only function to inject profit into the `MockTreasury`.
*   **Parameters:**
    *   `profit`: `coin::Coin<AptosCoin>` - The coins representing profit to inject.

## 13. Future Integration Interface

*   The contract includes commented-out `friend` declarations and functions (`get_mint_ref`, `get_burn_ref`) that are intended for integration with the `casino::CasinoHouse` module once it is implemented. These functions would provide controlled access to the minting and burning capabilities for the `CasinoHouse` contract.

