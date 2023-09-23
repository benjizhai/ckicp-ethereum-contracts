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
#
# PEM_FILE      Secret key of the identity to use for the call.

AIRDROP_CLAIMED_LOG="airdrop_claimed.log"
AIRDROP_CLAIMED_TXS="airdrop_claimed.txs"
INTERVAL_SECS=60

# Max number of transfers allowed in a single call to Airdrop.
MAX_RECORDS_IN_A_BATCH=20
AIRDROP_CANISTER_ID=t7tos-nyaaa-aaaad-aadkq-cai

test -z "$ETH_RPC_URL" && echo "Must set ETH_RPC_URL" && exit 1
test -z "$ETH_FROM" && echo "Must set ETH_FROM" && exit 1
test -z "$AIRDROP_FROM" && echo "Must set AIRDROP_FROM" && exit 1
test -z "$PEM_FILE" && echo "Must set PEM_FILE" && exit 1

# Make sure these file exists
touch "$AIRDROP_CLAIMED_LOG"
touch "$AIRDROP_CLAIMED_TXS"

# Sync the participant list by calling get_airdrop method on the Airdrop canister.
#
# 1. It would convert the result to json and store in file airdrop_json.XXXX.
#
# 2. The XXXX is basically just an incrementing number, but if the result is
#    unchanged since the last one, no such file will be created.
#
# 3. A diff with the already transfered record is returned as a multiline
#    string (each line is a JSON array [index, address, amount]). Number of
#    lines is capped at BATCH_NAX.
#
# 4. If anything goes wrong, nothing is returned.
function sync_participant_list() {
    # 1. Get latest airdrop list
    # TODO: call get_airdrop
    local LIST=$(icx --pem "$PEM_FILE" https://ic0.app update --candid airdrop.did "$AIRDROP_CANISTER_ID" get_airdrop '(0)' | idl2json | jq -c '.Ok|map([."0", ."1", ."2"])')
    echo "DEBUG: LIST=$LIST" >>/dev/stderr
    # local LIST='[["0","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"],["1","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"]]'
    # local LIST='[["0","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"],["1","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"],["2","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"],["3","0x2c91e73a358e6f0aff4b9200c8bad0d4739a70dd","100"]]'
    if [[ -n "$LIST" ]]; then
        # 2. Find the last airdrop list file, if any
        local n=0
        local last_file=/dev/null
        while true; do
            filename=$(printf airdrop_json.%04d "$n")
            if [[ -s "$filename" ]]; then
                last_file="$filename"
                n=$((n + 1))
            else
                break
            fi
        done
        # 3. Compare LIST with last file if known. If changed, save LIST
        #    to $filename.
        local DIFF="$(diff <(jq -c .[] "$last_file") <(jq -c .[] <<<"$LIST"))"
        if [[ -n "$DIFF" ]]; then
            echo "$LIST" >"$filename"
        else
            filename="$last_file"
        fi
        # 4. Compare LIST with claimed records, and return new records.
        DIFF="$(diff <(jq -c .[] "$AIRDROP_CLAIMED_LOG") <(jq -c .[] "$filename"))"
        if [[ -n "$DIFF" ]]; then
            # DIFF should be a 'NaN,N' line, and the rest lines starts with >
            local lines=$(echo "$DIFF" | wc -l)
            local appends=$(echo "$DIFF" | grep '^> ' | wc -l)
            # echo "DEBUG: $lines $appends" >/dev/stderr
            if [[ "$lines" -eq "$((appends + 1))" && "$(echo "$DIFF" | head -n1)" =~ ^[0-9]*a ]]; then
                echo "$DIFF" | tail -n$((lines - 1)) | sed -e 's/^> //' | head -n$MAX_RECORDS_IN_A_BATCH
            else
                echo "ERROR: latest list in ${filename} is not an increment of $AIRDROP_CLAIMED_LOG" >/dev/stderr
            fi
        fi
    fi
}

while true; do
    TX_JSON=$(tail -n1 $AIRDROP_CLAIMED_LOG)
    TX_HASH=$(tail -n1 $AIRDROP_CLAIMED_TXS)
    if [[ -n "$TX_HASH" && -n "$TX_JSON" ]]; then
        echo "0. Checking previous TX $TX_HASH"
        while true; do
            BLOCK=$(seth receipt $TX_HASH blockNumber)
            if [[ -z "$BLOCK" ]]; then
                echo "   ERROR: transaction $TX_HASH failed! Need to resend!"
                break
            fi
            LATEST=$(seth block-number)
            CONFIRMATION=$((LATEST - BLOCK))
            echo "   $CONFIRMATION confirmations"
            if [[ "$CONFIRMATION" -gt 32 ]]; then
                TX_JSON=
                TX_HASH=
                break
            fi
            sleep 30
        done
    fi
    if [[ -z "$TX_JSON" ]]; then
        echo -n 1. Syncing participant list
        TX_JSON=$(sync_participant_list)
        test -z "$TX_JSON" && echo '   No new participants'
    fi
    if [[ -n "$TX_JSON" ]]; then
        # NUM=$(echo "$LIST" | wc -l)
        INDICES=$(echo "$TX_JSON" | jq '.[0]' | jq -nc '[inputs]' | sed -e 's/"//g')
        ADDRS=$(echo "$TX_JSON" | jq '.[1]' | jq -nc '[inputs]' | sed -e 's/"//g')
        AMOUNTS=$(echo "$TX_JSON" | jq '.[2]' | jq -nc '[inputs]' | sed -e 's/"//g')
        echo DEBUG: INDICES=$INDICES
        echo DEBUG: ADDRS=$ADDRS
        echo DEBUG: AMOUNTS=$AMOUNTS
        while true; do
            echo 2. Creating the airdrop transaction...
            NONCE=$(seth nonce "$ETH_FROM")
            TX=$(seth --nonce "$NONCE" -S/dev/null mktx "$AIRDROP_FROM" "airdrop(address[],uint256[])" "${ADDRS}" "${AMOUNTS}")
            echo '   Created'
            ETH_GAS=$(seth estimate "$AIRDROP_FROM" "airdrop(address[],uint256[])" "${ADDRS}" "${AMOUNTS}")
            if [[ "$ETH_GAS" =~ ^[0-9][0-9]*$ ]]; then
                export ETH_GAS
                echo 3. Sending the airdrop transaction with "$ETH_GAS" gas
                TX_HASH=$(seth publish "$TX")
                if [[ "$TX_HASH" =~ ^0x[0-9a-f]{64}$ ]]; then
                    echo "$TX_JSON" | jq -cn '[inputs]' >>"$AIRDROP_CLAIMED_LOG"
                    echo "$TX_HASH" >>"$AIRDROP_CLAIMED_TXS"
                    echo "   Sent. Transaction is $TX_HASH"
                    break
                fi
            else
                echo "   Gas estimation failure! (Please check remaining tokens in the Airdrop contract)"
            fi
            echo "   Transaction NOT sent! Trying again in 60 seconds"
            sleep 60
        done
    fi
    echo -n "4. Calling put_airdrop"
    INDICES=$(jq -c 'map(.[0])' "$AIRDROP_CLAIMED_LOG" | jq -cn '[inputs]' | jq -c add | sed -e 's/"//g' -e 's/,/;/g' -e 's/^\[/vec {/' -e 's/\]$/}/')
    # It is ok the following fails, because we'll always try again with all indices!
    icx --pem "$PEM_FILE" https://ic0.app update --candid airdrop.did "$AIRDROP_CANISTER_ID" put_airdrop "($INDICES)"
    echo "   Sleep now. Resume in $INTERVAL_SECS seconds.."
    sleep "$INTERVAL_SECS"
done
