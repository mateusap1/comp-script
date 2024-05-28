use aiken/interval
use aiken/list
use aiken/option
use aiken/transaction.{Output, ScriptContext, Spend, Transaction}
use aiken/transaction/value
use comp/admin.{ADRewards, ADVoting}
use comp/user.{
  URAddVote, URCollect, URModApprove, USApproved, USAwaiting, USRejected,
  UserDatum, UserRedeemer,
}
use comp/utils

validator {
  fn spend(
    input_datum: UserDatum,
    redeemer: UserRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let Transaction { inputs, outputs, validity_range, .. } =
      context.transaction

    when redeemer is {
      URModApprove { is_approve } -> {
        expect [script_input] =
          list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
        let script_address = script_input.output.address

        let UserDatum { admin_address, state, ticket_policy_id, end_date, .. } =
          input_datum

        expect [script_output] =
          utils.find_outputs_with_address(outputs, script_address)
        let script_output_datum = user.find_datum(script_output.datum)

        let admin_input_is_present =
          (
            inputs
              |> utils.inputs_with_asset(
                  admin_address,
                  ticket_policy_id,
                  "admin-machine",
                )
              |> list.length
          ) == 1

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let right_user_state = state == USAwaiting
        let right_user_value = and {
            utils.lovelace_geq(script_output.value, script_input.output.value),
            value.quantity_of(
              script_output.value,
              ticket_policy_id,
              "user-machine",
            ) == 1,
          }

        let right_user_datum =
          if is_approve {
            script_output_datum == UserDatum {
              ..input_datum,
              state: USApproved,
            }
          } else {
            script_output_datum == UserDatum {
              ..input_datum,
              state: USRejected,
            }
          }

        and {
          admin_input_is_present?,
          before_end_date?,
          right_user_state?,
          right_user_value?,
          right_user_datum,
        }
      }
      URAddVote(auth, vote_asset_name) -> {
        expect [script_input] =
          list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
        let script_address = script_input.output.address

        let UserDatum { votes, ticket_policy_id, vote_policy_id, end_date, .. } =
          input_datum

        let user_output =
          utils.find_output_with_asset(
            outputs,
            script_address,
            ticket_policy_id,
            "user-machine",
          )
        let user_output_datum = user.find_datum(user_output.datum)

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let right_user_value =
          utils.lovelace_geq(user_output.value, script_input.output.value)

        let right_user_datum =
          user_output_datum == UserDatum {
            ..input_datum,
            votes: [vote_asset_name, ..votes],
          }

        let vote_not_repeated =
          votes
            |> list.find(fn(an) { an == vote_asset_name })
            |> option.is_none()

        let vote_authenticated =
          context.transaction
            |> utils.nft_authenticated(auth, vote_policy_id, vote_asset_name)
        let unique_script_input =
          (
            inputs
              |> list.filter(fn(inp) { inp.output.address == script_address })
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
      URCollect -> {
        let UserDatum { admin_address, ticket_policy_id, .. } = input_datum

        expect [admin_input] =
          utils.inputs_with_asset(
            inputs,
            admin_address,
            ticket_policy_id,
            "admin-machine",
          )
        let admin_input_datum = admin.find_datum(admin_input.output.datum)

        expect [admin_output] =
          utils.outputs_with_asset(
            outputs,
            admin_address,
            ticket_policy_id,
            "admin-machine",
          )
        let admin_output_datum = admin.find_datum(admin_output.datum)

        let correct_admin_input_state =
          when admin_input_datum is {
            ADVoting { .. } -> True
            _ -> False
          }

        let correct_admin_output_state =
          when admin_output_datum is {
            ADRewards { .. } -> True
            _ -> False
          }

        correct_admin_input_state? && correct_admin_output_state?
      }
    }
  }
}
