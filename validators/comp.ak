use aiken/bytearray
use aiken/dict
use aiken/interval
use aiken/list
use aiken/option
use aiken/transaction.{
  Mint, Output, OutputReference, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value
use comp/utils.{
  AddVote, Auth, CollectRewards, CompetitionParams, CreateComp, CreateUser,
  CurationDatum, MintRedeemer, ModApprove, ReviewDatum, ScriptDatum,
  SpendRedeemer, VoteDatum,
}

validator(params: CompetitionParams) {
  fn mint(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    expect Mint(policy_id) = context.purpose

    let script_address = credential.from_script(policy_id)

    let CompetitionParams { admin_price, user_price, utxo_ref, .. } = params

    let Transaction { inputs, outputs, mint, validity_range, .. } =
      context.transaction

    // This enforces that there is one unique script output
    let output = utils.find_output_with_address(outputs, script_address)

    let output_datum = utils.find_datum(output.datum)

    when redeemer is {
      CreateComp -> {
        // Must mint "admin", "admin" and "mod"
        // admin must go to our own address
        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            ["admin", "mod", "admin-machine"],
          )

        let output_has_admin =
          value.quantity_of(output.value, policy_id, "admin-machine") == 1

        let output_has_price = value.lovelace_of(output.value) >= admin_price

        expect CurationDatum { approved_votes, rejected_votes } = output_datum

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
          output_has_admin?,
          output_has_price?,
          output_has_right_datum?,
          utxo_ref_present?,
        }
      }
      CreateUser(utxo_ref_user) -> {
        let before_end_date =
          interval.is_entirely_before(validity_range, params.end_date)

        let user_asset_name = utils.unique_nft_name(utxo_ref_user)

        let minted_right_nfts =
          utils.minted_right_nfts(
            mint,
            policy_id,
            [user_asset_name, "user-machine"],
          )
        let utxo_ref_present_input =
          utils.utxo_ref_present(context.transaction, utxo_ref_user)

        let output_has_admin =
          value.quantity_of(output.value, policy_id, "user-machine") == 1

        let output_has_price = value.lovelace_of(output.value) >= user_price

        expect ReviewDatum { asset_name } = output_datum

        let output_has_right_datum = asset_name == user_asset_name

        and {
          before_end_date?,
          minted_right_nfts?,
          utxo_ref_present_input?,
          output_has_admin?,
          output_has_price?,
          output_has_right_datum?,
        }
      }
    }
  }

  fn spend(
    redeemer: SpendRedeemer,
    _dat: ScriptDatum,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let Transaction { inputs, outputs, mint, validity_range, .. } =
      context.transaction

    expect Some(input) = transaction.find_input(inputs, input_ref)
    let address = input.output.address

    expect Some(first_input) =
      list.find(inputs, fn(inp) { inp.output.address == address })

    let is_first_input = first_input == input

    if !is_first_input {
      // If it is the first script of the inputs, execute, otherwise return true

      True
    } else {
      let policy_id = utils.policy_id_from_address(address)

      when redeemer is {
        ModApprove { auth, is_approve } -> {
          // The following is so we know that we have a unique admin
          // script input and a unique admin script output
          // Also that their datum is CurationDatum
          let admin_input =
            utils.find_input_with_asset(
              inputs,
              address,
              policy_id,
              "admin-machine",
            )
          let admin_input_datum = utils.find_datum(admin_input.output.datum)
          expect CurationDatum {
            approved_votes: admin_input_app,
            rejected_votes: admin_input_rej,
          } = admin_input_datum

          let admin_output =
            utils.find_output_with_asset(
              outputs,
              address,
              policy_id,
              "admin-machine",
            )
          let admin_output_datum = utils.find_datum(admin_output.datum)
          expect CurationDatum {
            approved_votes: admin_output_app,
            rejected_votes: admin_output_rej,
          } = admin_output_datum

          // Let's get the user information now
          let user_input =
            utils.find_input_with_asset(
              inputs,
              address,
              policy_id,
              "user-machine",
            )
          let user_input_datum = utils.find_datum(user_input.output.datum)
          expect ReviewDatum(user_input_asset_name) = user_input_datum

          let user_outputs =
            utils.outputs_with_asset(
              outputs,
              address,
              policy_id,
              "user-machine",
            )

          let before_end_date =
            interval.is_entirely_before(validity_range, params.end_date)

          let admin_input_value = admin_input.output.value
          let admin_output_value = admin_output.value

          let right_admin_value =
            utils.lovelace_geq(admin_input_value, admin_output_value)

          let expected_app_votes =
            if is_approve {
              [user_input_asset_name, ..admin_input_app]
            } else {
              admin_input_app
            }
          let expected_rej_votes =
            if is_approve {
              admin_input_rej
            } else {
              [user_input_asset_name, ..admin_input_rej]
            }

          let right_admin_datum = and {
              admin_output_app == expected_app_votes,
              admin_output_rej == expected_rej_votes,
            }

          let mod_authenticated =
            context.transaction
              |> utils.nft_authenticated(auth, policy_id, "mod")

          let right_user_value =
            when user_outputs is {
              [Output { value: user_output_value, .. }] ->
                is_approve && utils.lovelace_geq(
                  user_output_value,
                  user_input.output.value,
                )
              [] -> {
                // user-machine must be burnt
                expect [(an, -1)] =
                  mint
                    |> value.from_minted_value
                    |> value.tokens(policy_id)
                    |> dict.to_list

                !is_approve && an == "user-machine"
              }
              _ -> False
            }

          let right_user_datum =
            when user_outputs is {
              [Output { datum, .. }] -> {
                let user_output_datum = utils.find_datum(datum)
                expect VoteDatum { asset_name, votes } = user_output_datum
                is_approve && asset_name == user_input_asset_name && votes == []
              }
              [] -> !is_approve
              _ -> False
            }

          and {
            before_end_date?,
            right_admin_value?,
            right_admin_datum?,
            mod_authenticated?,
            right_user_value?,
            right_user_datum,
          }
        }
        AddVote(auth, vote_asset_name) -> {
          let user_input =
            utils.find_input_with_asset(
              inputs,
              address,
              policy_id,
              "user-machine",
            )
          let user_input_datum = utils.find_datum(user_input.output.datum)
          expect VoteDatum {
            asset_name: user_input_asset_name,
            votes: user_input_votes,
          } = user_input_datum

          let user_output =
            utils.find_output_with_asset(
              outputs,
              address,
              policy_id,
              "user-machine",
            )
          let user_output_datum = utils.find_datum(user_output.datum)
          expect VoteDatum {
            asset_name: user_output_asset_name,
            votes: user_output_votes,
          } = user_output_datum

          let before_end_date =
            interval.is_entirely_before(validity_range, params.end_date)

          let right_user_value =
            utils.lovelace_geq(user_output.value, user_input.output.value)

          let right_user_datum = and {
              user_output_asset_name == user_input_asset_name,
              user_output_votes == [vote_asset_name, ..user_input_votes],
            }

          let vote_not_repeated =
            user_input_votes
              |> list.find(fn(an) { an == vote_asset_name })
              |> option.is_none()

          let vote_authenticated =
            context.transaction
              |> utils.nft_authenticated(
                  auth,
                  params.vote_policy_id,
                  vote_asset_name,
                )
          let unique_script_input =
            (
              inputs
                |> list.filter(fn(inp) { inp.output.address == address })
                |> list.length
            ) == 1

          and {
            before_end_date?,
            right_user_value?,
            right_user_datum?,
            vote_not_repeated?,
            vote_authenticated?,
            unique_script_input?,
          }
        }
        CollectRewards -> {
          let admin_input =
            utils.find_input_with_asset(
              inputs,
              address,
              policy_id,
              "admin-machine",
            )
          let admin_input_datum = utils.find_datum(admin_input.output.datum)
          expect CurationDatum { approved_votes, .. } = admin_input_datum

          let expected_users = list.length(approved_votes)
          let total_funds = params.user_price * list.length(approved_votes)

          let end_date_has_passed =
            interval.is_entirely_after(validity_range, params.end_date)

          and {
            end_date_has_passed?,
            every_user_input_present?,
            admin_received_right_reward?,
            mod_received_right_reward?,
            user_winners_received_right_reward?,
            vote_winners_received_right_reward?,
            scripts_dissapeared?,
            tokens_burnt?,
          }
        }
      }
    }
  }
}
