use assist/types/hashes.{ValidatorHash}

pub type WithdrawRedeemer {
  Withdraw
  Delegate(ValidatorHash)
}
