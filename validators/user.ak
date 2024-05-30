use aiken/interval
use aiken/list
use aiken/option
use aiken/transaction.{Output, ScriptContext, Spend, Transaction}
use aiken/transaction/value
use comp/admin.{ASVoting, AdminDatum}
use comp/user.{
  URAddVote, URCollect, URModApprove, USApproved, USAwaiting, USRejected,
  USVoted, UserDatum, UserParams, UserRedeemer,
}
use comp/utils

validator(params: UserParams) {
  fn spend(
    input_datum: UserDatum,
    redeemer: UserRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let UserParams { end_date, vote_policy_id } = params

    let Transaction { inputs, outputs, validity_range, .. } =
      context.transaction

    expect [script_input] =
      list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
    let script_address = script_input.output.address

    let unique_script_input =
      (
        inputs
          |> list.filter(fn(inp) { inp.output.address == script_address })
          |> list.length
      ) == 1

    when redeemer is {
      URModApprove { auth, is_approve } -> {
        let UserDatum { state, ticket_policy_id, .. } = input_datum

        expect [script_output] =
          utils.find_outputs_with_address(outputs, script_address)
        let script_output_datum = user.find_datum(script_output.datum)

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let mod_authenticated =
          utils.nft_authenticated(
            context.transaction,
            auth,
            ticket_policy_id,
            "mod",
          )

        let right_state = state == USAwaiting
        let right_value = and {
            utils.lovelace_geq(script_output.value, script_input.output.value),
            value.quantity_of(
              script_output.value,
              ticket_policy_id,
              "user-machine",
            ) == 1,
          }

        let right_datum =
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
          unique_script_input?,
          mod_authenticated?,
          before_end_date?,
          right_state?,
          right_value?,
          right_datum,
        }
      }
      URAddVote(auth, vote_asset_name) -> {
        expect [script_input] =
          list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
        let script_address = script_input.output.address

        let UserDatum { votes, ticket_policy_id, .. } = input_datum

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

        let right_value =
          utils.lovelace_geq(user_output.value, script_input.output.value)

        let right_datum =
          user_output_datum == UserDatum {
            ..input_datum,
            state: USVoted,
            votes: [vote_asset_name, ..votes],
          }

        let vote_not_repeated =
          votes
            |> list.find(fn(an) { an == vote_asset_name })
            |> option.is_none()

        let vote_authenticated =
          context.transaction
            |> utils.nft_authenticated(auth, vote_policy_id, vote_asset_name)

        and {
          unique_script_input?,
          before_end_date?,
          right_value?,
          right_datum?,
          vote_not_repeated?,
          vote_authenticated?,
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

        let correct_admin_input_state = admin_input_datum.state == ASVoting

        correct_admin_input_state?
      }
    }
  }
}
