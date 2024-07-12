#!/usr/bin/env bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
network=$(cat ../data/network.sh)

# get current params
${cli} query protocol-parameters ${network} --out-file ../tmp/protocol.json

# staked smart contract address
script_path="../../contracts/reference_contract.plutus"
script_address=$(${cli} address build --payment-script-file ${script_path} ${network})

# seller info
starter_address=$(cat ../wallets/starter-wallet/payment.addr)

# change address
change_address=$(jq -r '.starterChangeAddr' ../../config.json)

# asset to trade
policy_id=$(jq -r '.starterPid' ../../config.json)
token_name=$(jq -r '.starterTkn' ../../config.json)
asset="1 ${policy_id}.${token_name}"

min_value=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out-inline-datum-file ../data/reference/reference-datum.json \
    --tx-out="${script_address} + 5000000 + ${asset}" | tr -dc '0-9')

script_address_out="${script_address} + ${min_value} + ${asset}"
echo "Script OUTPUT: "${script_address_out}
#
# exit
#
echo -e "\033[0;36m Gathering UTxO Information  \033[0m"
# get utxo
${cli} query utxo \
    ${network} \
    --address ${starter_address} \
    --out-file ../tmp/starter_utxo.json

# transaction variables
txns=$(jq length ../tmp/starter_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${starter_address} \033[0m \n";
   exit;
fi
alltxin=""
txin=$(jq -r --arg alltxin "" --arg policy_id "$policy_id" --arg token_name "$token_name" 'to_entries[] | select((.value.value | length < 2) or .value.value[$policy_id][$token_name] == 1) | .key | . + $alltxin + " --tx-in"' ../tmp/starter_utxo.json)
starter_tx_in=${txin::-8}

echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${change_address} \
    --tx-in ${starter_tx_in} \
    --tx-out="${script_address_out}" \
    --tx-out-inline-datum-file ../data/reference/reference-datum.json \
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
    --signing-key-file ../wallets/starter-wallet/payment.skey \
    --tx-body-file ../tmp/tx.draft \
    --out-file ../tmp/referenceable-tx.signed \
    ${network}
#
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    ${network} \
    --tx-file ../tmp/referenceable-tx.signed

tx=$(cardano-cli transaction txid --tx-file ../tmp/referenceable-tx.signed)
echo "Tx Hash:" $tx