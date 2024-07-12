#!/usr/bin/env bash
set -e

#
rm tmp/tx.signed || true
export CARDANO_NODE_SOCKET_PATH=$(cat ./data/path_to_socket.sh)
cli=$(cat ./data/path_to_cli.sh)
network=$(cat ./data/network.sh)

# Addresses
sender_path="wallets/artist-wallet/"
sender_address=$(cat ${sender_path}payment.addr)
# receiver_address=$(cat wallets/seller-wallet/payment.addr)
# receiver_address=${sender_address}
receiver_address="addr_test1qrvnxkaylr4upwxfxctpxpcumj0fl6fdujdc72j8sgpraa9l4gu9er4t0w7udjvt2pqngddn6q4h8h3uv38p8p9cq82qav4lmp"

#
# exit
#
echo -e "\033[0;36m Gathering UTxO Information  \033[0m"
${cli} query utxo \
    ${network} \
    --address ${sender_address} \
    --out-file tmp/sender_utxo.json

txns=$(jq length tmp/sender_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${sender_address} \033[0m \n";
   exit;
fi
alltxin=""
txin=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' tmp/sender_utxo.json)
seller_tx_in=${txin::-8}

echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file tmp/tx.draft \
    --change-address ${receiver_address} \
    --tx-in ${seller_tx_in} \
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
    --signing-key-file ${sender_path}payment.skey \
    --tx-body-file tmp/tx.draft \
    --out-file tmp/tx.signed \
    ${network}
#
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    ${network} \
    --tx-file tmp/tx.signed

tx=$(cardano-cli transaction txid --tx-file tmp/tx.signed)
echo "Tx Hash:" $tx