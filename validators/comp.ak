use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{Mint, OutputReference, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value
use comp/utils.{
  AdminDatum, AwaitDatum, CompetitionParams, CreateComp, CreateUser,
  MintRedeemer, VoteDatum,
}

validator(params: CompetitionParams) {
  fn mint(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    expect Mint(policy_id) = context.purpose
    let script_address = credential.from_script(policy_id)

    let CompetitionParams { admin_price, user_price, utxo_ref, .. } = params

    let Transaction { inputs, outputs, mint, .. } = context.transaction

    // This enforces that there is one unique script output
    let output = utils.find_output_with_address(outputs, script_address)

    let output_datum = utils.find_datum(output)

    when redeemer is {
      CreateComp -> {
        // Must mint "source", "admin" and "mod"
        // Source must go to our own address
        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            ["admin", "mod", "source-machine"],
          )

        let output_has_source =
          value.quantity_of(output.value, policy_id, "source-machine") == 1

        let output_has_price = value.lovelace_of(output.value) >= admin_price

        expect AdminDatum { approved_votes, rejected_votes } = output_datum

        let output_has_right_datum = and {
            approved_votes == [],
            rejected_votes == [],
          }

        let utxo_ref_present =
          inputs
            |> list.find(fn(input) { input.output_reference == utxo_ref })
            |> option.is_some

        and {
          minted_right_nfts?,
          output_has_source?,
          output_has_price?,
          output_has_right_datum?,
          utxo_ref_present?,
        }
      }
      CreateUser(utxo_ref_user) -> {
        let user_asset_name = utils.unique_nft_name(utxo_ref_user)

        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            [user_asset_name, "user-machine"],
          )
        let utxo_ref_present_input =
          utils.utxo_ref_present(context.transaction, utxo_ref_user)

        let output_has_source =
          value.quantity_of(output.value, policy_id, "user-machine") == 1

        let output_has_price = value.lovelace_of(output.value) >= user_price

        expect AwaitDatum { asset_name } = output_datum

        let output_has_right_datum = asset_name == user_asset_name

        and {
          minted_right_nfts?,
          utxo_ref_present_input?,
          output_has_source?,
          output_has_price?,
          output_has_right_datum?,
        }
      }
    }
  }
}
