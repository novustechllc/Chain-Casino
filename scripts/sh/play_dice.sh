#!/bin/bash

# Multiple dice game bets script
# Usage: ./play_dice.sh [number_of_bets] [bet_amount]

# Get casino and player addresses
CASINO_ADDR=$(aptos config show-profiles --profile casino | grep '"account"' | cut -d'"' -f4)
PLAYER_ADDR=$(aptos config show-profiles --profile player | grep '"account"' | cut -d'"' -f4)

# Parameters
NUM_BETS=${1:-5}
BET_AMOUNT=${2:-1000000}

echo "Playing $NUM_BETS dice games..."
echo "Bet amount: $BET_AMOUNT octas each"
echo "Casino: $CASINO_ADDR"
echo "Player: $PLAYER_ADDR"
echo "=================================="

# Check initial balance
echo "Initial balance:"
aptos account balance --account $PLAYER_ADDR --network devnet

# Play multiple games
for i in $(seq 1 $NUM_BETS); do
    # Random guess 1-6
    GUESS=$((RANDOM % 6 + 1))
    
    echo "Game $i: Guess $GUESS, Bet $BET_AMOUNT"
    
    aptos move run \
      --profile player \
      --function-id $CASINO_ADDR::DiceGame::play_dice \
      --args u8:$GUESS u64:$BET_AMOUNT \
      --assume-yes
    
    sleep 1
done

echo "=================================="
echo "Final balance:"
aptos account balance --account $PLAYER_ADDR --network devnet

echo "All games completed!"
