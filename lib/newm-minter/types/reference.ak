use aiken/bytearray
use aiken/transaction/credential.{PoolId}
use assist/types/hashes.{PublicKeyHash, ValidatorHash}
use assist/types/wallet.{Wallet}

pub type Staking {
  pool_id: PoolId,
  reward_wallet: Wallet,
}

fn has_valid_staking(staking: Staking) -> Bool {
  and {
    wallet.is_valid(staking.reward_wallet),
    bytearray.length(staking.pool_id) == 28,
  }
}

pub type Keepers {
  pkhs: List<PublicKeyHash>,
  threshold: Int,
}

/// All keepers must have valid length public key hashes. There must be at
/// at least one keeper and the threshold must be logical with respect to the
/// list of keepers.
///
fn has_valid_keepers(keepers: Keepers) -> Bool {
  do_has_valid_keepers(keepers.pkhs, 0, keepers.threshold)
}

fn do_has_valid_keepers(
  keepers: List<PublicKeyHash>,
  counter: Int,
  threshold: Int,
) -> Bool {
  when keepers is {
    [] -> and {
        // some amount of keepers must exist
        counter > 0,
        // must be equal or greater than threshold
        counter >= threshold,
      }
    [pkh, ..pkhs] ->
      if bytearray.length(pkh) == 28 {
        // valid length count it
        do_has_valid_keepers(pkhs, counter + 1, threshold)
      } else {
        // not a valid pkh
        False
      }
  }
}

pub type Contracts {
  storage: ValidatorHash,
  stake: ValidatorHash,
}

/// All the contract validator hashes must be length 28 or empty.
fn has_valid_contracts(contracts: Contracts) -> Bool {
  and {
    bytearray.length(contracts.storage) == 28,
    or {
      bytearray.is_empty(contracts.stake),
      bytearray.length(contracts.stake) == 28,
    },
  }
}

/// The reference data to be used inside other contracts.
pub type ReferenceDatum {
  hot_key: PublicKeyHash,
  keepers: Keepers,
  staking: Staking,
  contracts: Contracts,
}

pub fn valid_datum_update(datum: ReferenceDatum) -> Bool {
  and {
    // hot key needs to be valid length
    (bytearray.length(datum.hot_key) == 28)?,
    // keepers are logical and valid
    has_valid_keepers(datum.keepers)?,
    // can't have a invalid reward wallet
    has_valid_staking(datum.staking)?,
    // contracts either exist or dont
    has_valid_contracts(datum.contracts)?,
  }
}
