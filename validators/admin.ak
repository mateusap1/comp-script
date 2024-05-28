use aiken/interval
use aiken/list
use aiken/transaction.{Output, ScriptContext, Spend, Transaction}
use aiken/transaction/value
use comp/admin.{ADVoting, ARModApprove, AdminDatum, AdminRedeemer}
use comp/user.{USApproved, USAwaiting, USRejected, UserDatum}
use comp/utils

validator {
  fn spend(
    input_datum: AdminDatum,
    redeemer: AdminRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let Transaction { inputs, outputs, validity_range, .. } =
      context.transaction

    expect [script_input] =
      list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
    let script_address = script_input.output.address
    let script_input_value = script_input.output.value

    when redeemer is {
      ARModApprove { auth } -> {
        expect ADVoting {
          user_address,
          admin_price,
          user_price,
          ticket_policy_id,
          end_date,
          reward_rates,
          approved_votes,
        } = input_datum

        expect [script_output] =
          utils.find_outputs_with_address(outputs, script_address)
        let script_output_value = script_output.value

        let script_output_datum = admin.find_datum(script_output.datum)
        expect ADVoting {
          user_address: out_user_address,
          admin_price: out_admin_price,
          user_price: out_user_price,
          ticket_policy_id: out_ticket_policy_id,
          end_date: out_end_date,
          reward_rates: out_reward_rates,
          approved_votes: out_approved_votes,
        } = script_output_datum

        let user_input =
          utils.find_input_with_asset(
            inputs,
            user_address,
            ticket_policy_id,
            "user-machine",
          )
        let user_input_datum = user.find_datum(user_input.output.datum)

        let correct_user_input_state = user_input_datum.state == USAwaiting

        let user_output =
          utils.find_output_with_asset(
            outputs,
            user_address,
            ticket_policy_id,
            "user-machine",
          )
        let user_output_datum = user.find_datum(user_output.datum)
        let UserDatum { asset_name, state, .. } = user_output_datum

        let expected_votes =
          when state is {
            USApproved ->
              [asset_name, ..approved_votes]
            USRejected -> approved_votes
            USAwaiting -> fail @"Wrong state"
          }

        let before_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let right_script_value = and {
            utils.lovelace_geq(script_input_value, script_output_value),
            value.quantity_of(
              script_output_value,
              ticket_policy_id,
              "admin-machine",
            ) == 1,
          }

        let right_script_datum = and {
            user_address == out_user_address,
            admin_price == out_admin_price,
            user_price == out_user_price,
            ticket_policy_id == out_ticket_policy_id,
            end_date == out_end_date,
            reward_rates == out_reward_rates,
            expected_votes == out_approved_votes,
          }

        let mod_authenticated =
          utils.nft_authenticated(
            context.transaction,
            auth,
            ticket_policy_id,
            "mod",
          )

        and {
          correct_user_input_state?,
          before_end_date?,
          right_script_value?,
          right_script_datum?,
          mod_authenticated?,
        }
      }
      _ -> False
    }
  }
}
