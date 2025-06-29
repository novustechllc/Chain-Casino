# 🎰 ChainCasino

> **"The first on-chain casino protocol where a token-backed treasury powers multiple games, and investors earn real yield through rising NAV as the house wins."**

ChainCasino is a decentralized protocol on **Aptos** that merges casino gaming with DeFi investing.

- 💰 **Investor Token (CCIT):** NAV-based token that tracks a growing treasury
- 🎲 **Modular Games:** Games are external smart contracts with access granted via capabilities
- 🏦 **On-Chain Treasury:** Treasury handles all bets and redemptions transparently
- 🔐 **Security First:** Built in Move 2 on Aptos

---

ChainCasino turns **"The House Always Wins"** into **"The Investor Always Earns."**

![ChainCasino Banner](./.github/assets/Banner_Final.jpg)

---

## 📐 Architecture Overview

```mermaid
flowchart LR

  subgraph Investors
    investor[Investor]
    token["InvestorToken"]
  end

  subgraph Core_System
    treasury["Treasury"]
    casino["CasinoHouse"]
  end

  subgraph Players
    player[Player]
    game["Game Contract"]
  end

  investor -->|Deposit APT| token
  token -->|Send APT| treasury
  treasury -->|NAV Up with Game Earnings| token

  player -->|Bet| game
  game -->|place_bet / settle_bet| casino
  casino -->|Payout| player

  casino <--> treasury
```

---

## 🚀 Key Concepts

- **NAV-Based Tokenomics**  
  Minting and redemption adjust token supply to keep NAV constant for others.  
  Treasury grows → NAV increases → CCIT is worth more.

- **Modular Game Authorization**  
  Games are **independent contracts**. Casino only grants treasury access using `GameCapability`.  
  Anyone can write games, no central control.

- **On-Chain Fairness**  
  Aptos randomness is used in all games. Events log all rolls, spins, and payouts.

---

## 🔬 Move 2 Feature Explorations

- `fungible-assets` - Modern FA standard implementation
- `randomness` - Randomness patterns  
- `object-composability` - Object relationships & inheritance

---

## 🔧 Modules

### `CasinoHouse.move`
- Treasury manager
- Game registry and capability issuer
- Bet placement and settlement logic

### `InvestorToken.move`
- CCIT minting/redeeming
- NAV tracking
- Redemption fee logic

### `DiceGame.move` & `SlotMachine.move`
- Example modular games
- Use randomness for outcome
- Call CasinoHouse to settle bets

---

## 📦 How to Use

1. Deploy modules: `CasinoHouse`, `InvestorToken`, and game contracts
2. Register games using `CasinoHouse::register_game()` to create game objects
3. Games initialize and claim capabilities via `CasinoHouse::get_game_capability()`
4. Fund treasury using `InvestorToken::deposit_and_mint()` to mint CCIT tokens
5. Players bet through game contracts using `CasinoHouse::place_bet()`
6. Games settle outcomes using `CasinoHouse::settle_bet()`
7. Investors redeem profits using `InvestorToken::redeem()`

---

## 📊 House Edge Example (DiceGame)

- Player chooses number 1–6  
- Wins if guess is correct  
- Payout: 5x  
- House Edge: ~16.67%  
- Treasury absorbs losses → NAV grows

---

## TODO

- Add Previous Branch Tests Refactor Made Obsolete
- Optimize for Transaction Parallelization on Aptos Blockchain
- Gas Waste Removal

---

## 🧠 Future Ideas

- DAO for treasury governance
- More games

---

ChainCasino turns **"The House Always Wins"** into **"The Investor Always Earns."**

---

MIT License