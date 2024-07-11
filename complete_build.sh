#!/usr/bin/env bash
set -e

function cat_file_or_empty() {
  if [ -e "$1" ]; then
    cat "$1"
  else
    echo ""
  fi
}

# create directories if dont exist
mkdir -p contracts
mkdir -p hashes
mkdir -p certs

# remove old files
rm contracts/* || true
rm hashes/* || true
rm certs/* || true
rm -fr build/ || true

# build out the entire script
echo -e "\033[1;34m Building Contracts \033[0m"

# remove all traces
aiken build --trace-level silent --filter-traces user-defined

# keep the traces
# aiken build --trace-level verbose --filter-traces all

# the reference token
pid=$(jq -r '.starterPid' config.json)
tkn=$(jq -r '.starterTkn' config.json)

# cbor representation
pid_cbor=$(python3 -c "import cbor2;hex_string='${pid}';data = bytes.fromhex(hex_string);encoded = cbor2.dumps(data);print(encoded.hex())")
tkn_cbor=$(python3 -c "import cbor2;hex_string='${tkn}';data = bytes.fromhex(hex_string);encoded = cbor2.dumps(data);print(encoded.hex())")

echo -e "\033[1;33m Convert Reference Contract \033[0m"
aiken blueprint apply -o plutus.json -v reference.params "${pid_cbor}"
aiken blueprint apply -o plutus.json -v reference.params "${tkn_cbor}"
aiken blueprint convert -v reference.params > contracts/reference_contract.plutus
cardano-cli transaction policyid --script-file contracts/reference_contract.plutus > hashes/reference_contract.hash

# reference hash
ref=$(cat hashes/reference_contract.hash)

# cbor representation
ref_cbor=$(python3 -c "import cbor2;hex_string='${ref}';data = bytes.fromhex(hex_string);encoded = cbor2.dumps(data);print(encoded.hex())")

# The pool to stake at
poolId=$(jq -r '.poolId' config.json)

# build the stake contract
echo -e "\033[1;33m Convert Staking Contract \033[0m"
aiken blueprint apply -o plutus.json -v staking.params "${pid_cbor}"
aiken blueprint apply -o plutus.json -v staking.params "${tkn_cbor}"
aiken blueprint apply -o plutus.json -v staking.params "${ref_cbor}"
aiken blueprint convert -v staking.params > contracts/stake_contract.plutus
cardano-cli transaction policyid --script-file contracts/stake_contract.plutus > hashes/stake.hash
cardano-cli stake-address registration-certificate --stake-script-file contracts/stake_contract.plutus --out-file certs/stake.cert
cardano-cli stake-address delegation-certificate --stake-script-file contracts/stake_contract.plutus --stake-pool-id ${poolId} --out-file certs/deleg.cert

echo -e "\033[1;33m Convert CIP68 Storage Contract \033[0m"
aiken blueprint apply -o plutus.json -v storage.params "${pid_cbor}"
aiken blueprint apply -o plutus.json -v storage.params "${tkn_cbor}"
aiken blueprint apply -o plutus.json -v storage.params "${ref_cbor}"
aiken blueprint convert -v storage.params > contracts/storage_contract.plutus
cardano-cli transaction policyid --script-file contracts/storage_contract.plutus > hashes/storage.hash

echo -e "\033[1;33m Convert Minting Contract \033[0m"
aiken blueprint apply -o plutus.json -v minter.params "${pid_cbor}"
aiken blueprint apply -o plutus.json -v minter.params "${tkn_cbor}"
aiken blueprint apply -o plutus.json -v minter.params "${ref_cbor}"
aiken blueprint convert -v minter.params > contracts/mint_contract.plutus
cardano-cli transaction policyid --script-file contracts/mint_contract.plutus > hashes/policy.hash

###############################################################################
############## DATUM AND REDEEMER STUFF #######################################
###############################################################################
echo -e "\033[1;33m Updating Reference Datum \033[0m"

# keepers
pkh1=$(cat_file_or_empty ./scripts/wallets/keeper1-wallet/payment.hash)
pkh2=$(cat_file_or_empty ./scripts/wallets/keeper2-wallet/payment.hash)
pkh3=$(cat_file_or_empty ./scripts/wallets/keeper3-wallet/payment.hash)
pkhs="[{\"bytes\": \"$pkh1\"}, {\"bytes\": \"$pkh2\"}, {\"bytes\": \"$pkh3\"}]"
thres=2

# pool stuff
rewardPkh=$(cat_file_or_empty ./scripts/wallets/reward-wallet/payment.hash)
rewardSc=""

# validator hashes
storageHash=$(cat hashes/storage.hash)
stakeHash=$(cat hashes/stake.hash)

# newm hot key
hotKey=$(jq -r '.hotKey' config.json)

cp ./scripts/data/reference/reference-datum.json ./scripts/data/reference/backup-reference-datum.json

# update reference data
jq \
--arg hotKey "$hotKey" \
--argjson pkhs "$pkhs" \
--argjson thres "$thres" \
--arg poolId "$poolId" \
--arg rewardPkh "$rewardPkh" \
--arg rewardSc "$rewardSc" \
--arg storageHash "$storageHash" \
--arg stakeHash "$stakeHash" \
'.fields[0].bytes=$hotKey | 
.fields[1].fields[0].list |= ($pkhs | .[0:length]) | 
.fields[1].fields[1].int=$thres | 
.fields[2].fields[0].bytes=$poolId |
.fields[2].fields[1].fields[0].bytes=$rewardPkh |
.fields[2].fields[1].fields[1].bytes=$rewardSc |
.fields[3].fields[0].bytes=$storageHash |
.fields[3].fields[1].bytes=$stakeHash
' \
./scripts/data/reference/reference-datum.json | sponge ./scripts/data/reference/reference-datum.json

# Update Staking Redeemer
echo -e "\033[1;33m Updating Stake Redeemer \033[0m"
stakeHash=$(cat_file_or_empty ./hashes/stake.hash)
jq \
--arg stakeHash "$stakeHash" \
'.fields[0].bytes=$stakeHash' \
./scripts/data/staking/delegate-redeemer.json | sponge ./scripts/data/staking/delegate-redeemer.json

backup="./scripts/data/reference/backup-reference-datum.json"
frontup="./scripts/data/reference/reference-datum.json"

# Get the SHA-256 hash values of the files using sha256sum and command substitution
hash1=$(sha256sum "$backup" | awk '{ print $1 }')
hash2=$(sha256sum "$frontup" | awk '{ print $1 }')

# Check if the hash values are equal using string comparison in an if statement
if [ "$hash1" = "$hash2" ]; then
  echo -e "\033[1;46mNo Datum Changes Required.\033[0m"
else
  echo -e "\033[1;43mA Datum Update Is Required.\033[0m"
fi

# end of build
echo -e "\033[1;32m Building Complete! \033[0m"