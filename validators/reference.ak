use aiken/transaction.{Input, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{Value}
use assist/count
use assist/find
use assist/payout
use assist/signing
use newm_minter/types/reference.{ReferenceDatum}

validator {
  fn params(
    this_datum: ReferenceDatum,
    _redeemer: Void,
    context: ScriptContext,
  ) -> Bool {
    // spending only
    expect Spend(output_reference) = context.purpose
    // tx being validated
    let Transaction { inputs, outputs, extra_signatories, .. } =
      context.transaction
    // this input being spent
    let this_input: Input = find.input_by_ref(inputs, output_reference)
    // this should allow the lovelace to change naturally with the updates
    let that_value: Value = this_input.output.value |> value.without_lovelace
    // this address being spent from
    let this_addr: Address = this_input.output.address
    // that datum going to this address
    expect that_datum: ReferenceDatum =
      find.output_datum_by_addr(outputs, this_addr)
    //
    // That datum can only update logically and only by the keepers in this
    // datum. The value validation is such that the lovelace may change
    // but whatever non-lovelace assets must remain on the UTxO.
    //
    and {
      // send back to script but allow lovelace increase or decrease
      payout.at_least(this_addr, that_value, outputs)?,
      // single script input
      count.inputs_by_addr(inputs, this_addr, 1)?,
      // single script output
      count.outputs_by_addr(outputs, this_addr, 1)?,
      // only keepers can update the data
      signing.verify_multisig(
        extra_signatories,
        this_datum.keepers.pkhs,
        this_datum.keepers.threshold,
      )?,
      // must be a valid datum update
      reference.valid_datum_update(that_datum)?,
    }
  }
}
