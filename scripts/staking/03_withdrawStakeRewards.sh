#!/usr/bin/env bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
network=$(cat ../data/network.sh)

# staking contract
stake_script_path="../../contracts/stake_contract.plutus"
stake_address=$(${cli} stake-address build --stake-script-file ${stake_script_path} ${network})

echo "Stake Address: " $stake_address

# collat
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# reward fee payer
newm_address=$(cat ../wallets/newm-wallet/payment.addr)

# rewarder
reward_address=$(cat ../wallets/reward-wallet/payment.addr)

# find rewards
rewardBalance=$(${cli} query stake-address-info \
    ${network} \
    --address ${stake_address} | jq -r ".[0].rewardAccountBalance")
echo rewardBalance: $rewardBalance

if [ "$rewardBalance" -eq 0 ]; then
   echo -e "\n \033[0;31m No Rewards Found At ${stake_address} \033[0m \n";
   exit;
fi

withdrawalString="${stake_address}+${rewardBalance}"
echo "Withdraw: " $withdrawalString
#
# exit
#
echo -e "\033[0;36m Gathering UTxO Information  \033[0m"
${cli} query utxo \
    ${network} \
    --address ${newm_address} \
    --out-file ../tmp/newm_utxo.json

txns=$(jq length ../tmp/newm_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${newm_address} \033[0m \n";
   exit;
fi
alltxin=""
txin=$(jq -r --arg alltxin "" 'to_entries[] | select(.value.value | length < 2) | .key | . + $alltxin + " --tx-in"' ../tmp/newm_utxo.json)
seller_tx_in=${txin::-8}

# collat info
echo -e "\033[0;36m Gathering Collateral UTxO Information  \033[0m"
${cli} query utxo \
    ${network} \
    --address ${collat_address} \
    --out-file ../tmp/collat_utxo.json

txns=$(jq length ../tmp/collat_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${collat_address} \033[0m \n";
   exit;
fi
collat_utxo=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/stake-reference-utxo.signed)
data_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/referenceable-tx.signed )

echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${newm_address} \
    --read-only-tx-in-reference="${data_ref_utxo}#0" \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${seller_tx_in} \
    --withdrawal ${withdrawalString} \
    --withdrawal-tx-in-reference="${script_ref_utxo}#1" \
    --withdrawal-plutus-script-v2 \
    --withdrawal-reference-tx-in-redeemer-file ../data/staking/withdraw-redeemer.json \
    --tx-out="${reward_address}+${rewardBalance}" \
    --required-signer-hash ${collat_pkh} \
    ${network})

IFS=':' read -ra VALUE <<< "${fee}"
IFS=' ' read -ra fee <<< "${VALUE[1]}"
fee=${fee[1]}
echo -e "\033[1;32m Fee: \033[0m" $fee
#
# exit
#
echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ../wallets/newm-wallet/payment.skey \
    --signing-key-file ../wallets/collat-wallet/payment.skey \
    --tx-body-file ../tmp/tx.draft \
    --out-file ../tmp/tx.signed \
    ${network}
#
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    ${network} \
    --tx-file ../tmp/tx.signed

tx=$(cardano-cli transaction txid --tx-file ../tmp/tx.signed)
echo "Tx Hash:" $tx