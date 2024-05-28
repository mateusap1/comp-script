use aiken/dict
use aiken/interval
use aiken/list
use aiken/option
use aiken/transaction.{Mint, Output, ScriptContext, Transaction}
use aiken/transaction/value
use comp/admin.{ADVoting}
use comp/ticket.{TRAddUser, TRBurn, TRInit, TicketParams, TicketRedeemer}
use comp/user.{USAwaiting, UserDatum, UserValidationData}
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
      vote_policy_id,
    } = params

    let Transaction { inputs, outputs, mint, validity_range, .. } =
      context.transaction

    when redeemer is {
      TRInit -> {
        // This enforces that there is one unique script output
        expect [admin_output] =
          utils.find_outputs_with_address(outputs, admin_address)
        let admin_output_datum = admin.find_datum(admin_output.datum)

        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            [("admin", 1), ("mod", 1), ("admin-machine", 1)],
          )

        let admin_output_has_nft =
          value.quantity_of(admin_output.value, policy_id, "admin-machine") == 1

        let admin_output_has_price =
          value.lovelace_of(admin_output.value) >= admin_price

        expect ADVoting { reward_rates, .. } = admin_output_datum

        let admin_output_has_right_datum =
          admin_output_datum == ADVoting {
            user_address,
            admin_price,
            user_price,
            ticket_policy_id: policy_id,
            end_date,
            reward_rates,
            approved_votes: [],
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
      TRAddUser(utxo_refs_map) -> {
        let user_validations =
          list.map(
            utxo_refs_map,
            fn(ref_map) {
              let (utxo_ref, out_idx) = ref_map

              expect Some(output) = list.at(outputs, out_idx)
              let datum = user.find_datum(output.datum)

              UserValidationData {
                asset_name: utils.unique_nft_name(utxo_ref),
                address: output.address,
                value: output.value,
                datum,
              }
            },
          )

        let (utxo_refs, output_indexes) = list.unzip(utxo_refs_map)

        let proof_inputs =
          list.filter(
            inputs,
            fn(inp) { list.has(utxo_refs, inp.output_reference) },
          )

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            [
              ("user-machine", list.length(utxo_refs_map)),
              ..list.map(user_validations, fn(uvd) { (uvd.asset_name, 1) })
            ],
          )

        let (_, output_indexes_not_repeated) =
          list.foldr(
            output_indexes,
            ([], False),
            fn(an, acc) {
              let (ans_acc, flag_acc) = acc
              if list.has(ans_acc, an) {
                (ans_acc, False)
              } else {
                ([an, ..ans_acc], flag_acc)
              }
            },
          )

        // Also enforces that they are unique, you cannot consume the same
        // UTxO twice in the same tx
        let all_utxo_refs_present =
          list.length(proof_inputs) == list.length(utxo_refs)

        let valid_outputs =
          list.all(
            user_validations,
            fn(validation) {
              let UserValidationData { asset_name, address, value: val, datum } =
                validation
              and {
                address == user_address,
                value.lovelace_of(val) >= user_price,
                value.quantity_of(val, policy_id, "user-machine") == 1,
                datum == UserDatum {
                  admin_address,
                  state: USAwaiting,
                  asset_name,
                  ticket_policy_id: policy_id,
                  vote_policy_id,
                  end_date,
                  votes: [],
                },
              }
            },
          )

        and {
          before_end_date?,
          minted_right_nfts?,
          output_indexes_not_repeated,
          all_utxo_refs_present?,
          valid_outputs,
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
