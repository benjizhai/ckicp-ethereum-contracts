#!/usr/bin/env bash
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

test -z "$ETH_RPC_URL" && echo "Must set ETH_RPC_URL" && exit 1
test -z "$ETH_FROM" && echo "Must set ETH_FROM" && exit 1
test -z "$AIRDROP_FROM" && echo "Must set AIRDROP_FROM" && exit 1
test -z "$PEM_FILE" && echo "Must set PEM_FILE" && exit 1

# This file is an append-only log that stores a JSON object per line
# to submit airdrop claims to Airdrop ETH contract.
AIRDROP_CLAIMED_LOG="airdrop_claimed.log"

# This file is an append-only log that stores a transaction id per
# line created from the submission of airdrop claims. The number
# of lines should be the same as AIRDROP_CLAIMED_LOG to keep the
# correspondence.
#
# Note that the transaction of the last line may not have been
# finalized. This script will make sure it has either been finalized
# or definitely failed, before continuing.
#
# If the last transaction has failed (i.e. transaction id is not
# included), a new attempt will be made to submit the last claim again.
# This means AIRDROP_CLAIM_LOG may have duplicated lines, which is
# acceptable.
AIRDROP_CLAIMED_TXS="airdrop_claimed.txs"

## Make sure these files exist.
touch "$AIRDROP_CLAIMED_LOG"
touch "$AIRDROP_CLAIMED_TXS"

# How many seconds of sleep before repeating the monitoring process.
INTERVAL_SECS=300

# Max number of transfers allowed in a single call to Airdrop.
MAX_RECORDS_IN_A_BATCH=1

# Airdrop canister
AIRDROP_CANISTER_ID=t7tos-nyaaa-aaaad-aadkq-cai

# Used by printf to generate a file name.
AIRDROP_JSON_PATTERN=airdop_json.%05d

# We assume after these many blocks a transaction is considered to be finalized.
NUM_BLOCKS_PER_EPOCH=32

# Sync the airdrop list by calling get_airdrop method on the Airdrop canister.
#
# 1. It will convert the result to JSON and store in file airdrop_json.XXXXX.
#
# 2. The XXXXX is basically just an ever-incrementing number, but if the
#    result is unchanged since the last one, no such file will be created.
#
# 3. A diff with the already claimed records (derived from AIRDROP_CLAIMED_LOG)
#    is returned as a multiline string (each line is a JSON array
#    [index, address, amount]). Number of lines is capped at BATCH_NAX.
#
# 4. If anything goes wrong, nothing is returned.
function sync_participant_list() {
    # Get latest airdrop list
    # TODO: call get_airdrop
    local LIST
    LIST=$(icx --pem "$PEM_FILE" https://ic0.app update --candid airdrop.did "$AIRDROP_CANISTER_ID" get_airdrop '(0)' | idl2json | jq -c '.Ok|map([."0", ."1", ."2"])')
    echo "DEBUG: LIST=$LIST" >>/dev/stderr
    if [[ -n "$LIST" ]]; then
        # Find the last airdrop list file, if any
        local n=0
        local last_file=/dev/null
        local next_file
        while true; do
            next_file=$(printf "$AIRDROP_JSON_PATTERN" "$n")
            if [[ -s "$next_file" ]]; then
                last_file="$next_file"
                n=$((n + 1))
            else
                break
            fi
        done
        # Compare LIST with last file if known.
        # If different (i.e. with extra appends), save LIST to $next_file.
        local DIFF
        DIFF="$(diff <(jq -c .[] "$last_file") <(jq -c .[] <<<"$LIST"))"
        if [[ -n "$DIFF" ]]; then
            echo "$LIST" >"$next_file"
        else
            next_file="$last_file"
        fi
        # Compare LIST with claimed records, and return new records.
        DIFF="$(diff <(uniq "$AIRDROP_CLAIMED_LOG" | jq -c .[]) <(jq -c .[] "$next_file"))"
        if [[ -n "$DIFF" ]]; then
            # DIFF should be first a 'NaN,N' line, and the rest lines starts with >
            local lines
            lines=$(echo "$DIFF" | wc -l)
            local appends
            appends=$(echo "$DIFF" | grep -c '^> ')
            # echo "DEBUG: $lines $appends" >/dev/stderr
            if [[ "$lines" -eq "$((appends + 1))" && "$(echo "$DIFF" | head -n1)" =~ ^[0-9]*a ]]; then
                # Success! Take MAX_RECORDS_IN_A_BATCH of them
                echo "$DIFF" | tail -n$((lines - 1)) | sed -e 's/^> //' | head -n$MAX_RECORDS_IN_A_BATCH
            else
                echo "ERROR: latest list in ${next_file} is not an increment of $AIRDROP_CLAIMED_LOG" >/dev/stderr
            fi
        fi
    fi
}

while true; do
    # First, wait for the last transaction to be finalized.
    # This makes sure we either have succeeded all past transactions,
    # or we'll re-send the last one (if it is known to have failed)
    # until it becomes successful.
    TX_JSON=$(tail -n1 $AIRDROP_CLAIMED_LOG)
    TX_HASH=$(tail -n1 $AIRDROP_CLAIMED_TXS)
    if [[ -n "$TX_HASH" && -n "$TX_JSON" ]]; then
        echo "0. Checking previous TX $TX_HASH"
        while true; do
            BLOCK=$(seth receipt "$TX_HASH" blockNumber)
            if [[ -z "$BLOCK" ]]; then
                echo "   ERROR: transaction $TX_HASH failed! Need to resend!"
                break
            fi
            LATEST=$(seth block-number)
            CONFIRMATION=$((LATEST - BLOCK))
            echo "   $CONFIRMATION confirmations"
            if [[ "$CONFIRMATION" -gt "$NUM_BLOCKS_PER_EPOCH" ]]; then
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
        echo "DEBUG: INDICES=$INDICES"
        echo "DEBUG: ADDRS=$ADDRS"
        echo "DEBUG: AMOUNTS=$AMOUNTS"
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

    # Note that as long as we successfully obtained a transaction id (i.e. an
    # entry created in each of AIRDROP_CLAIMED_TXS and AIRDROP_CLAIMED_LOG),
    # we consider these claims to be "dropped" (despite that they may still
    # be on-the-way). If the transaction later fails, it will be retried until
    # it becomes successful. Please see Step 0 for more details.
    echo -n "4. Calling put_airdrop"
    INDICES=$(uniq "$AIRDROP_CLAIMED_LOG" | jq -c 'map(.[0])' | jq -cn '[inputs]' | jq -c add | sed -e 's/"//g' -e 's/,/;/g' -e 's/^\[/vec {/' -e 's/\]$/}/')
    # It is ok if the following fails, because we'll try again with all indices
    # in the next iteration to here!
    icx --pem "$PEM_FILE" https://ic0.app update --candid airdrop.did "$AIRDROP_CANISTER_ID" put_airdrop "($INDICES)"
    test "$?" -eq "0" || echo "   Any error above (if any) is safe to ignore!"
    echo "   Sleep now. Resume in $INTERVAL_SECS seconds.."
    sleep "$INTERVAL_SECS"
done
