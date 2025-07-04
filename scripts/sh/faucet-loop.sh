#!/bin/bash

# ChainCasino Faucet Loop Script
# Iterates 1100 times to fund casino address via Aptos devnet faucet

set -e

# Configuration
ITERATIONS=1100
AMOUNT=100000000  # 1 APT in octas
FAUCET_URL="https://faucet.devnet.aptoslabs.com/mint"

# Validate CASINO_ADDR environment variable
if [ -z "$CASINO_ADDR" ]; then
    echo "Error: CASINO_ADDR environment variable is not set"
    echo "Usage: export CASINO_ADDR=0x... && ./faucet-loop.sh"
    exit 1
fi

echo "🎰 ChainCasino Faucet Funding Script"
echo "Address: $CASINO_ADDR"
echo "Amount per request: $AMOUNT octas (1 APT)"
echo "Total iterations: $ITERATIONS"
echo "Expected total: $((ITERATIONS * AMOUNT / 100000000)) APT"
echo ""

# Progress tracking
SUCCESS_COUNT=0
FAILURE_COUNT=0
START_TIME=$(date +%s)

for i in $(seq 1 $ITERATIONS); do
    # Progress indicator
    if [ $((i % 50)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "Progress: $i/$ITERATIONS (${SUCCESS_COUNT} success, ${FAILURE_COUNT} failed) - ${ELAPSED}s elapsed"
    fi
    
    # Make faucet request with timeout
    if curl -X POST \
        --max-time 10 \
        --retry 2 \
        --retry-delay 1 \
        --silent \
        --fail \
        "${FAUCET_URL}?amount=${AMOUNT}&address=${CASINO_ADDR}" > /dev/null 2>&1; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "Failed request #$i"
    fi
    
    # Rate limiting: small delay between requests
    sleep 0.1
done

# Final summary
TOTAL_TIME=$(($(date +%s) - START_TIME))
FUNDED_AMOUNT=$((SUCCESS_COUNT * AMOUNT))
FUNDED_APT=$((FUNDED_AMOUNT / 100000000))

echo ""
echo "🎯 Funding Complete!"
echo "Successful requests: $SUCCESS_COUNT/$ITERATIONS"
echo "Failed requests: $FAILURE_COUNT"
echo "Total funded: ${FUNDED_AMOUNT} octas (${FUNDED_APT} APT)"
echo "Total time: ${TOTAL_TIME} seconds"
echo ""

if [ $SUCCESS_COUNT -lt $((ITERATIONS / 2)) ]; then
    echo "⚠️  Warning: Less than 50% success rate. Check network connectivity and faucet status."
    exit 1
else
    echo "✅ Funding successful! Casino address should now have sufficient APT for deployment."
fi
