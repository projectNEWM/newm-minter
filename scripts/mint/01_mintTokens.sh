#!/usr/bin/env bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
testnet_magic=$(cat ../data/testnet.magic)

# get params
${cli} query protocol-parameters --testnet-magic ${testnet_magic} --out-file ../tmp/protocol.json

# staking contract
stake_script_path="../../contracts/stake_contract.plutus"

# cip 68 contract
storage_script_path="../../contracts/storage_contract.plutus"
storage_script_address=$(${cli} address build --payment-script-file ${storage_script_path} --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})

# pays for tx
newm_address=$(cat ../wallets/newm-wallet/payment.addr)
newm_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/newm-wallet/payment.vkey)

# collateral
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# recieves the tokens
receiver_address=$(cat ../wallets/artist-wallet/payment.addr)
receiver_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/artist-wallet/payment.vkey)

# the minting script policy
policy_id=$(cat ../../hashes/policy.hash)

echo -e "\033[0;36m Gathering NEWM UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${newm_address} \
    --out-file ../tmp/newm_utxo.json

txns=$(jq length ../tmp/newm_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${newm_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/newm_utxo.json)
newm_tx_in=${TXIN::-8}

echo "NEWM UTxO:" $newm_tx_in
first_utxo=$(jq -r 'keys[0]' ../tmp/newm_utxo.json)
string=${first_utxo}
IFS='#' read -ra array <<< "$string"

prefix_100="000643b0"
prefix_444="001bc280"

ref_name=$(python3 -c "import sys; sys.path.append('../../lib/py/'); from getTokenName import token_name; token_name('${array[0]}', ${array[1]}, '${prefix_100}')")
frac_name=$(python3 -c "import sys; sys.path.append('../../lib/py/'); from getTokenName import token_name; token_name('${array[0]}', ${array[1]}, '${prefix_444}')")

echo -n $ref_name > ../tmp/reference.token
echo -n $frac_name > ../tmp/fraction.token


reference_asset="1 ${policy_id}.${ref_name}"
fraction_asset="100000000 ${policy_id}.${frac_name}"

mint_asset="1 ${policy_id}.${ref_name} + 100000000 ${policy_id}.${frac_name}"

# echo Minting: ${mint_asset}

min_ada=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out-inline-datum-file ../data/storage/empty.metadata-datum.json \
    --tx-out="${storage_script_address} + 5000000 + ${reference_asset}" | tr -dc '0-9')
reference_address_out="${storage_script_address} + ${min_ada} + ${reference_asset}"

# --tx-out-datum-embed-file ../data/storage/empty.metadata-datum.json \

min_ada=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out="${receiver_address} + 5000000 + ${fraction_asset}" | tr -dc '0-9')
fraction_address_out="${receiver_address} + ${min_ada} + ${fraction_asset}"

echo "Reference Mint OUTPUT:" ${reference_address_out}
echo "Fraction Mint OUTPUT:" ${fraction_address_out}
#
# exit
#
echo -e "\033[0;36m Gathering Collateral UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${collat_address} \
    --out-file ../tmp/collat_utxo.json
txns=$(jq length ../tmp/collat_utxo.json)
if [ "${txns}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${collat_address} \033[0m \n";
   exit;
fi
collat_utxo=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/mint-reference-utxo.signed)
data_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/referenceable-tx.signed )

# Add metadata to this build function for nfts with data
echo -e "\033[0;36m Building Tx \033[0m"
fee=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${newm_address} \
    --tx-in-collateral="${collat_utxo}" \
    --read-only-tx-in-reference="${data_ref_utxo}#0" \
    --tx-in ${newm_tx_in} \
    --tx-out="${reference_address_out}" \
    --tx-out-inline-datum-file ../data/storage/empty.metadata-datum.json \
    --tx-out="${fraction_address_out}" \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${newm_pkh} \
    --mint="${mint_asset}" \
    --mint-tx-in-reference="${script_ref_utxo}#1" \
    --mint-plutus-script-v2 \
    --policy-id="${policy_id}" \
    --mint-reference-tx-in-redeemer-file ../data/mint/mint-redeemer.json \
    --testnet-magic ${testnet_magic})

    # --tx-out-datum-embed-file ../data/storage/empty.metadata-datum.json \

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
    --testnet-magic ${testnet_magic}
#    
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ../tmp/tx.signed

tx=$(cardano-cli transaction txid --tx-file ../tmp/tx.signed)
echo "Tx Hash:" $tx