use aiken/transaction.{Input, Publish, ScriptContext, Transaction, WithdrawFrom}
use aiken/transaction/certificate.{Certificate, CredentialDelegation}
use aiken/transaction/credential.{Address, Inline, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/addresses
use assist/data
use assist/find
use assist/payout
use assist/signing
use assist/types/hashes.{ValidatorHash}
use assist/values
use newm_minter/types/reference.{ReferenceDatum}
use newm_minter/types/staking.{Delegate, Withdraw, WithdrawRedeemer}

validator(
  starter_pid: PolicyId,
  starter_tkn: AssetName,
  ref_hash: ValidatorHash,
) {
  fn params(redeemer: WithdrawRedeemer, context: ScriptContext) -> Bool {
    // the purpose can only be withdrawing and publishing
    when context.purpose is {
      // can withdraw from stake credential
      WithdrawFrom(stake_credential) ->
        when redeemer is {
          // can only withdraw
          Withdraw -> {
            let Transaction { outputs, reference_inputs, withdrawals, .. } =
              context.transaction
            // get reference utxo
            let ref_addr: Address = credential.from_script(ref_hash)
            let ref_input: Input =
              find.input_by_addr(reference_inputs, ref_addr)
            // get the reference datum
            expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
            let reward_addr: Address =
              addresses.from_wallet(ref_datum.staking.reward_wallet)
            // if no reward is found error
            let reward: Int =
              find.stake_reward_by_sc(withdrawals, stake_credential)
            //
            // Send at least the staking reward to the reward wallet. This can
            // be done by anyone since the Lovelace can only go to the reward
            // wallet and can not be stolen.
            //
            and {
              // data reference must hold correct token
              values.prove_exact_nft(
                ref_input.output.value,
                starter_pid,
                starter_tkn,
              )?,
              // an at least here allows for small rewards to be withdrawn
              payout.at_least(reward_addr, value.from_lovelace(reward), outputs)?,
            }
          }
          // other redeemers fail here
          _ -> False
        }
      // can only publish a cert
      Publish(certificate) ->
        when redeemer is {
          // only delegate to secific pool
          Delegate(sd) -> {
            let Transaction { reference_inputs, extra_signatories, .. } =
              context.transaction
            // get reference utxo
            let ref_addr: Address = credential.from_script(ref_hash)
            let ref_input: Input =
              find.input_by_addr(reference_inputs, ref_addr)
            // get the reference datum
            expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
            let new_delegation: Certificate =
              CredentialDelegation {
                delegator: Inline(ScriptCredential(sd)),
                delegatee: ref_datum.staking.pool_id,
              }
            //
            // A valid keeper multisig is required to change the staking
            // delegation.
            //
            and {
              // data reference must hold correct token
              values.prove_exact_nft(
                ref_input.output.value,
                starter_pid,
                starter_tkn,
              )?,
              // The only cert is for new delegation
              (certificate == new_delegation)?,
              // only keepers can update the data
              signing.verify_multisig(
                extra_signatories,
                ref_datum.keepers.pkhs,
                ref_datum.keepers.threshold,
              )?,
            }
          }
          // other redeemers fail here
          _ -> False
        }
      // other purposes fail here
      _ -> False
    }
  }
}
