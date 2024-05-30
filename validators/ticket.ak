use aiken/dict
use aiken/interval
use aiken/list
use aiken/option
use aiken/transaction.{Mint, Output, ScriptContext, Transaction}
use aiken/transaction/value
use comp/admin.{ASVoting, AdminDatum}
use comp/ticket.{TRAddUser, TRBurn, TRInit, TicketParams, TicketRedeemer}
use comp/user.{USAwaiting, UserDatum}
use comp/utils

validator(params: TicketParams) {
  fn mint(redeemer: TicketRedeemer, context: ScriptContext) -> Bool {
    expect Mint(policy_id) = context.purpose

    let TicketParams {
      utxo_ref,
      admin_address,
      user_address,
      admin_price,
      user_price,
      end_date,
    } = params

    let Transaction { inputs, outputs, mint, validity_range, .. } =
      context.transaction

    let minted_sorted =
      utils.sort_assets(
        mint
          |> value.from_minted_value
          |> value.tokens(policy_id)
          |> dict.to_list,
      )

    when redeemer is {
      TRInit -> {
        expect [admin_output] =
          utils.find_outputs_with_address(outputs, admin_address)
        let admin_output_datum = admin.find_datum(admin_output.datum)

        let minted_right_nfts =
          minted_sorted == utils.sort_assets(
            [("admin", 1), ("mod", 1), ("admin-machine", 1)],
          )

        let admin_output_has_nft =
          value.quantity_of(admin_output.value, policy_id, "admin-machine") == 1

        let admin_output_has_price =
          value.lovelace_of(admin_output.value) >= admin_price

        let admin_output_has_right_datum =
          admin_output_datum == AdminDatum {
            state: ASVoting,
            user_address,
            total_approved: 0,
            total_amount: 0,
            ticket_policy_id: policy_id,
            user_rewards: [],
            user_asset_names: [],
            user_claimed: [],
            vote_rewards: [],
            vote_asset_names: [],
            vote_claimed: [],
          }

        let utxo_ref_present =
          inputs
            |> list.find(fn(input) { input.output_reference == utxo_ref })
            |> option.is_some

        and {
          minted_right_nfts?,
          admin_output_has_nft?,
          admin_output_has_price?,
          admin_output_has_right_datum?,
          utxo_ref_present?,
        }
      }
      TRAddUser(utxo_refs) -> {
        let user_outputs =
          utils.outputs_with_asset(
            outputs,
            user_address,
            policy_id,
            "user-machine",
          )
        let all_utxo_refs_have_output =
          list.length(user_outputs) == list.length(utxo_refs)

        let user_datums =
          list.map(user_outputs, fn(out) { user.find_datum(out.datum) })

        let proof_inputs =
          list.filter(
            inputs,
            fn(inp) { list.has(utxo_refs, inp.output_reference) },
          )

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let minted_right_nfts =
          minted_sorted == utils.sort_assets(
            [
              ("user-machine", list.length(utxo_refs)),
              ..list.map(utxo_refs, fn(ref) { (utils.unique_nft_name(ref), 1) })
            ],
          )

        // Also enforces that they are unique, you cannot consume the same
        // UTxO twice in the same tx
        let all_utxo_refs_present =
          list.length(proof_inputs) == list.length(utxo_refs)

        let valid_outputs =
          list.all(
            list.zip(user_outputs, user_datums),
            fn(o) {
              let (out, dat) = o
              and {
                value.lovelace_of(out.value) >= user_price,
                value.quantity_of(out.value, policy_id, dat.asset_name) == 1,
                dat == UserDatum {
                  ..dat,
                  admin_address: admin_address,
                  state: USAwaiting,
                  ticket_policy_id: policy_id,
                  votes: [],
                },
              }
            },
          )
        and {
          before_end_date?,
          minted_right_nfts?,
          all_utxo_refs_have_output?,
          all_utxo_refs_present?,
          valid_outputs?,
        }
      }
      TRBurn -> {
        let amounts =
          mint
            |> value.from_minted_value
            |> value.tokens(policy_id)
            |> dict.values
        list.all(amounts, fn(amt) { amt < 0 })
      }
    }
  }
}
