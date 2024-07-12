#!/usr/bin/env bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
network=$(cat ../data/network.sh)

# get params
${cli} query protocol-parameters ${network} --out-file ../tmp/protocol.json

# who will pay for the tx
newm_address=$(cat ../wallets/newm-wallet/payment.addr)

stakeAddressDeposit=$(cat ../tmp/protocol.json | jq -r '.stakeAddressDeposit')

echo stakeAddressDeposit : $stakeAddressDeposit
#
# exit
#
echo -e "\033[0;36m Gathering Payee UTxO Information  \033[0m"
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
newm_tx_in=${txin::-8}

echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${newm_address} \
    --tx-in ${newm_tx_in} \
    --certificate ../../certs/stake.cert \
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