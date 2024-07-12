#!/usr/bin/env bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
network=$(cat ../data/network.sh)

# staking contract
stake_script_path="../../contracts/stake_contract.plutus"

# cip 68 storage contract
storage_script_path="../../contracts/storage_contract.plutus"
storage_script_address=$(${cli} address build --payment-script-file ${storage_script_path} --stake-script-file ${stake_script_path} ${network})

# collat
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# pays for the tx
newm_address=$(cat ../wallets/newm-wallet/payment.addr)
newm_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/newm-wallet/payment.vkey)

pid=$(cat ../../hashes/policy.hash)
tkn=$(cat ../tmp/reference.token)
asset="1 ${pid}.${tkn}"

min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out-inline-datum-file ../data/storage/updated-metadata-datum.json \
    --tx-out="${storage_script_address} + 5000000 + ${asset}" | tr -dc '0-9')

    # --tx-out-datum-embed-file ../data/storage/updated-metadata-datum.json \

script_address_out="${storage_script_address} + ${min_utxo} + ${asset}"
echo "Update OUTPUT: "${script_address_out}
#
# exit
#
# get deleg utxo
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
txin=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/newm_utxo.json)
newm_tx_in=${txin::-8}

# get script utxo
echo -e "\033[0;36m Gathering Script UTxO Information  \033[0m"
${cli} query utxo \
    --address ${storage_script_address} \
    ${network} \
    --out-file ../tmp/script_utxo.json
txns=$(jq length ../tmp/script_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${storage_script_address} \033[0m \n";
   exit;
fi
alltxin=""
txin=$(jq -r --arg alltxin "" --arg policy_id "$pid" --arg name "$tkn" 'to_entries[] | select(.value.value[$policy_id][$name] == 1) | .key | . + $alltxin + " --tx-in"' ../tmp/script_utxo.json)
script_tx_in=${txin::-8}
echo Storage UTxO: $script_tx_in

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
collat_tx_in=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

# script reference utxo
script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/storage-reference-utxo.signed )
data_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/referenceable-tx.signed )

echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${newm_address} \
    --tx-in-collateral ${collat_tx_in} \
    --read-only-tx-in-reference="${data_ref_utxo}#0" \
    --tx-in ${newm_tx_in} \
    --tx-in ${script_tx_in} \
    --spending-tx-in-reference="${script_ref_utxo}#1" \
    --spending-plutus-script-v2 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/storage/update-redeemer.json \
    --tx-out="${script_address_out}" \
    --tx-out-inline-datum-file ../data/storage/updated-metadata-datum.json \
    --required-signer-hash ${newm_pkh} \
    --required-signer-hash ${collat_pkh} \
    ${network})

    # --spending-reference-tx-in-datum-file ../data/storage/updated-metadata-datum.json \
    # --tx-out-datum-embed-file ../data/storage/updated-metadata-datum.json \

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

cp ../data/storage/updated-metadata-datum.json ../data/storage/metadata-datum.json

tx=$(cardano-cli transaction txid --tx-file ../tmp/tx.signed)
echo "Tx Hash:" $tx
