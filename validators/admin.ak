use aiken/dict
use aiken/interval
use aiken/list
use aiken/math/rational
use aiken/transaction.{Output, ScriptContext, Spend, Transaction}
use aiken/transaction/value
use comp/admin.{
  ADRewards, ADVoting, ARCollectRewards, ARModApprove, AdminDatum, AdminRedeemer,
}
use comp/user.{USApproved, USAwaiting, USRejected, UserDatum}
use comp/utils

validator {
  fn spend(
    input_datum: AdminDatum,
    redeemer: AdminRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let Transaction { inputs, outputs, validity_range, mint, .. } =
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
          vote_policy_id,
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
          vote_policy_id: out_vote_policy_id,
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
        let UserDatum { state, .. } = user_output_datum

        let expected_votes =
          when state is {
            USApproved -> approved_votes + 1
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
            vote_policy_id == out_vote_policy_id,
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
      ARCollectRewards -> {
        expect ADVoting {
          user_address,
          admin_price,
          user_price,
          ticket_policy_id,
          vote_policy_id,
          end_date,
          reward_rates,
          approved_votes,
        } = input_datum

        let total_amount = user_price * approved_votes + admin_price

        expect Some(admin_rate) = rational.new(reward_rates.admin, 100)
        let admin_expected =
          admin_rate
            |> rational.mul(rational.from_int(total_amount))
            |> rational.truncate

        expect Some(mod_rate) = rational.new(reward_rates.moderator, 100)
        let mod_expected =
          mod_rate
            |> rational.mul(rational.from_int(total_amount))
            |> rational.truncate

        let user_amount = total_amount - admin_expected - mod_expected

        let after_end_date =
          interval.is_entirely_before(validity_range, end_date)

        let user_inputs =
          utils.inputs_with_asset(
            inputs,
            user_address,
            ticket_policy_id,
            "user-machine",
          )

        let (fst, snd, trd, all_approved) =
          list.foldr(
            user_inputs,
            (("", [], -1), ("", [], -1), ("", [], -1), True),
            fn(inp, acc) {
              let (inp1, inp2, inp3, all_valid) = acc
              let (_, _, votes1) = inp1
              let (_, _, votes2) = inp2
              let (_, _, votes3) = inp3

              let datum = user.find_datum(inp.output.datum)
              let UserDatum { state, asset_name, votes, .. } = datum
              let vote_num = list.length(votes)

              let correct_state = state == USApproved

              if vote_num > votes1 {
                (
                  (asset_name, votes, vote_num),
                  inp1,
                  inp2,
                  correct_state && all_valid,
                )
              } else if vote_num > votes2 {
                (
                  inp1,
                  (asset_name, votes, vote_num),
                  inp2,
                  correct_state && all_valid,
                )
              } else if vote_num > votes3 {
                (
                  inp1,
                  inp2,
                  (asset_name, votes, vote_num),
                  correct_state && all_valid,
                )
              } else {
                (inp1, inp2, inp3, correct_state && all_valid)
              }
            },
          )

        let all_users_present = list.length(user_inputs) == approved_votes

        expect [admin_input] =
          list.filter(
            inputs,
            fn(inp) {
              value.quantity_of(inp.output.value, ticket_policy_id, "admin") == 1
            },
          )

        expect [admin_output] =
          utils.find_outputs_with_address(outputs, admin_input.output.address)

        let admin_received =
          value.lovelace_of(admin_output.value) >= admin_expected

        expect [mod_input] =
          list.filter(
            inputs,
            fn(inp) {
              value.quantity_of(inp.output.value, ticket_policy_id, "mod") == 1
            },
          )

        expect [mod_output] =
          utils.find_outputs_with_address(outputs, mod_input.output.address)

        let mod_received = value.lovelace_of(mod_output.value) >= mod_expected

        let script_output =
          utils.find_output_with_asset(
            outputs,
            script_address,
            ticket_policy_id,
            "admin-machine",
          )

        let script_output_datum = admin.find_datum(script_output.datum)
        let correct_value =
          value.lovelace_of(script_output.value) >= user_amount

        expect ADRewards {
          total_amount: out_total_amount,
          reward_rates: out_reward_rates,
          vote_policy_id: out_vote_policy_id,
          first: out_first,
          second: out_second,
          third: out_third,
        } = script_output_datum

        let correct_datum = and {
            out_total_amount == total_amount,
            out_reward_rates == reward_rates,
            out_vote_policy_id == vote_policy_id,
            out_first == (fst.1st, fst.2nd),
            out_second == (snd.1st, snd.2nd),
            out_third == (trd.1st, trd.2nd),
          }

        expect [(an, amt)] =
          mint
            |> value.from_minted_value
            |> value.tokens(ticket_policy_id)
            |> dict.to_list

        let users_destroyed = an == "user-machine" && amt == -approved_votes

        and {
          after_end_date?,
          all_approved?,
          all_users_present?,
          admin_received?,
          mod_received?,
          correct_value?,
          correct_datum?,
          users_destroyed?,
        }
      }
      _ -> False
    }
  }
}
