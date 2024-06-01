use aiken/transaction.{Input, Mint, ScriptContext, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/addresses
use assist/data
use assist/find
use assist/minting
use assist/payout
use assist/signing
use assist/types/cip68.{CIP68}
use assist/types/hashes.{TxHash, ValidatorHash}
use assist/values
use newm_minter/types/minter.{BurnTokens, MintRedeemer, MintTokens}
use newm_minter/types/reference.{ReferenceDatum}
use newm_minter/util

validator(
  starter_pid: PolicyId,
  starter_tkn: AssetName,
  ref_hash: ValidatorHash,
) {
  fn params(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    // can only mint
    expect Mint(currency_symbol) = context.purpose
    // can either mint or burn
    when redeemer is {
      // mint 1 reference and 100M fractionals
      MintTokens -> {
        // the transaction being validated
        let Transaction {
          inputs,
          outputs,
          reference_inputs,
          extra_signatories,
          mint,
          datums,
          ..
        } = context.transaction
        // data reference stuff
        let ref_addr: Address = credential.from_script(ref_hash)
        let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
        // Get the reference datum
        expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
        // get tx info
        let first_index: Int = find.first_input_index(inputs)
        let first_tx_hash: TxHash = find.first_input_txid(inputs)
        // use the ref prefix
        let reference_tkn: AssetName =
          values.unique_token_name(first_tx_hash, first_index, cip68.prefix_100)
        // use the rft prefix
        let fractions_tkn: AssetName =
          values.unique_token_name(first_tx_hash, first_index, cip68.prefix_444)
        let mint_list: List<(PolicyId, AssetName, Int)> =
          mint
            |> value.from_minted_value()
            |> value.flatten()
        // the cip 68 storage contract
        let storage_addr: Address =
          addresses.create_script_address(
            ref_datum.contracts.storage,
            ref_datum.contracts.stake,
          )
        expect _: CIP68 = util.output_datum(outputs, storage_addr, datums)
        //
        // Mint the reference token and 100M fractionals. The reference token
        // must go to the cip 68 storage contract with a CIP68 valid datum. The
        // fractionals do not have a destination validation. The act of minting
        // must be signed off with the hot key.
        //
        and {
          // send at least the reference token to the storage contract
          payout.at_least(
            storage_addr,
            value.from_asset(currency_symbol, reference_tkn, 1),
            outputs,
          )?,
          // hot key must sign
          signing.verify_sig(extra_signatories, ref_datum.hot_key)?,
          // prevent roll over double nft attack
          (first_index < 256)?,
          // must mint 1 reference token
          minting.exact(mint_list, currency_symbol, reference_tkn, 1)?,
          // must mint 100 M fractions
          minting.exact(mint_list, currency_symbol, fractions_tkn, 100_000_000)?,
          // data reference must be holding correct token
          values.prove_exact_nft(
            ref_input.output.value,
            starter_pid,
            starter_tkn,
          )?,
        }
      }
      // burn 1 reference or 100M fractionals or both
      BurnTokens { burn_amt } -> {
        let Transaction { reference_inputs, extra_signatories, mint, .. } =
          context.transaction
        // data reference stuff
        let ref_addr: Address = credential.from_script(ref_hash)
        let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
        // Get the reference datum
        expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
        // get tx info
        let mint_list: List<(PolicyId, AssetName, Int)> =
          mint
            |> value.from_minted_value()
            |> value.flatten()
        //
        // Burn the reference token or the fractionals or both at the 
        // same time. The act of burning must be signed off with the keeper
        // multisig.
        //
        and {
          // burn amount must be negative or zero
          (burn_amt <= 0)?,
          // has to be a multisig action
          signing.verify_multisig(
            extra_signatories,
            ref_datum.keepers.pkhs,
            ref_datum.keepers.threshold,
          )?,
          // one ref token or any amount of fractions or both
          or {
            // burn only 1 ref token
            minting.by_prefix(mint_list, currency_symbol, cip68.prefix_100, -1)?,
            // burn any amount of the fractions
            minting.by_prefix(
              mint_list,
              currency_symbol,
              cip68.prefix_444,
              burn_amt,
            )?,
          }?,
          // data reference must be holding correct token
          values.prove_exact_nft(
            ref_input.output.value,
            starter_pid,
            starter_tkn,
          )?,
        }
      }
    }
  }
}
