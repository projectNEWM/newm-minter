# Project NEWM's Fractional Minting Contract

Fractionalization refers to the process of dividing the ownership of the streaming rights of a piece of art into 100 million pieces. The resulting fractionals are given to the artist, who has the freedom to sell or trade them as they wish, or they can be sold on the NEWM Market, with the proceeds going directly to the artist.

## Getting Aiken

Please refer to the official documentation for [installation instructions](https://aiken-lang.org/installation-instructions).

### Assist library

Project NEWM uses the [Assist Library](https://github.com/logicalmechanism/assist),  collection of specialized Aiken functions designed for quick smart contracts development on Cardano. Documentation for the Assist Library can be viewed [here](https://www.logicalmechanism.io/docs/index.html).

## Build

Set up the `config.json` file with the correct starter token information, NEWM hot key, and pool ID. These values are used inside the `complete_build.sh` script to compile the contracts. The build script will automatically generate the correct datums and redeemers required for the happy path.

## Happy Path Setup

The `scripts` folder assumes there will be test wallets inside the `wallets`folder. Use this code block below to auto-generate the required wallets used on the happy path.

```bash
./create_wallet.sh wallets/artist-wallet
./create_wallet.sh wallets/collat-wallet
./create_wallet.sh wallets/reference-wallet
./create_wallet.sh wallets/keeper1-wallet
./create_wallet.sh wallets/keeper2-wallet
./create_wallet.sh wallets/keeper3-wallet
./create_wallet.sh wallets/newm-wallet
./create_wallet.sh wallets/reward-wallet
./create_wallet.sh wallets/starter-wallet
```

First, create the reference scripts with `00_createScriptReferences.sh` found in the scripts folder. This script will use funds held in the reference-wallet to store the smart contracts on UTxOs.

Next, we need to create the data reference UTxO using the `01_createReferenceUTxO.sh` script inside the `reference` subfolder. This script will use the starter-wallet to send the starter token defined in `config.json` into the data reference contract. The starter token acts as a pointer for the other contracts to correctly identify the true reference data. The `reference` folder contains test scripts for updating data on the data UTxO. These scripts require a valid n-out-of-m multisig with the set of keeper wallets held on a datum in the data reference contract. The `keeper*-wallet` wallets do not need funds as they are just signing the transaction. The update scripts assume the `newm-wallet` will pay for the transaction fees.

After the reference data contract has been set up, register and delegate the stake key inside the `staking` subfolder. The staking contract will delegate the ada value inside the cip68 storage and sale contract to a specific pool defined in the `config.json` file. The test scripts in the `staking` folder assume that the `newm-wallet` will pay for the transaction fee.

After the reference data contract has been set up, register and delegate the staking contract inside the `staking` subfolder. The staking contract will delegate the ADA value inside the storage contract to a specific pool defined in the `config.json` file. The test scripts in the `staking` folder assume that the `newm-wallet` will pay for the transaction fee.

At this point fractional tokens may be minted.

## Minting

Inside the `mint` subfolder are files for managing minting and burning fractional tokens. A pair of tokens are minted each time the mint validator is executed: 1 reference token is sent to the storage contract and 100 million fractionals are sent to the artist-wallet. During minting, both tokens must exist inside the same transaction, but burning allows either just some amount of fractionals, the reference, or both to be burned. Burning validation requires the valid multisig defined in the data reference contract.
