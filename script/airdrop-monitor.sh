# This script monitors the Airdrop canister for new parcipants list,
# and sends ethereum transaction to distribute ICP ERC20 tokens.
#
# Environment variables must be set:
#
# ETH_RPC_URL   RPC provider's URL
#
# ETH_FROM      The address to sign & send airdrop transactions.
#               It is also the owner of Airdrop contract.
#               Lastly seth must import the private key first.
#
# AIRDROP_FROM  The address of the Airdrop contract

AIRDROP_CLAIMED_JSON="airdrop_claimed.json"
AIRDROP_CLAIMED_HASH="airdrop_claimed.hash"
INTERVAL_SECS=60

test -z "$ETH_RPC_URL" && echo "Must set ETH_RPC_URL" && exit 1
test -z "$ETH_FROM" && echo "Must set ETH_FROM" && exit 1
test -z "$AIRDROP_FROM" && echo "Must set AIRDROP_FROM" && exit 1

function sync_participant_list() {
    echo "[[\"0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd\", \"100000000000000000\"], [\"0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd\", \"100000000000000000\"]]"
}

while true; do
    echo 1. Syncing participant list...
    LIST=$(sync_participant_list)
    if [[ -z "$LIST" ]]; then
        echo '   No new participants'
    else
        NUM=$(echo "$LIST" | jq length)
        ADDRS=$(echo "$LIST" | jq 'map(.[0])' | sed -e 's/"//g')
        AMOUNTS=$(echo "$LIST" | jq 'map(.[1])' | sed -e 's/"//g')
        echo "  Synced, and found $NUM new participants."

        while true; do
            echo 2. Creating the airdrop transaction...
            NONCE=$(seth nonce "$ETH_FROM")
            TX=$(seth --nonce "$NONCE" -S/dev/null mktx "$AIRDROP_FROM" "airdrop(address[],uint256[])" "${ADDRS}" "${AMOUNTS}")
            echo '   Created'
            ETH_GAS=$(seth estimate "$AIRDROP_FROM" "airdrop(address[],uint256[])" "${ADDRS}" "${AMOUNTS}")
            if [[ "$ETH_GAS" =~ ^[0-9][0-9]*$ ]]; then
                export ETH_GAS
                echo 3. Sending the airdrop transaction with "$ETH_GAS" gas
                BLOCK=$(seth publish "$TX")
                if [[ "$BLOCK" =~ ^0x[0-9a-f]{64}$ ]]; then
                    echo "   Sent. Block is $BLOCK"
                    echo "$LIST" >>"$AIRDROP_CLAIMED_JSON"
                    echo "$BLOCK" >>"$AIRDROP_CLAIMED_HASH"
                    break
                fi
              else
                echo "   Gas estimation failure! (Please check remaining tokens in the Airdrop contract)"
            fi
            echo "   Transaction not sent! will try again in 10 seconds."
            sleep 10
        done
    fi

    echo "   Restart monitoring in $INTERVAL_SECS seconds.."
    sleep "$INTERVAL_SECS"
done
