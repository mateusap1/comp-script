use aiken/dict
use aiken/interval
use aiken/list
use aiken/transaction.{Output, ScriptContext, Spend, Transaction}
use aiken/transaction/value
use comp/admin.{
  ARClaimRewards, ARCollectRewards, ARModApprove, ASRewarding, ASVoting,
  AdminDatum, AdminParams, AdminRedeemer, CRUser, CRVoter, RewardRates,
  WinnerRate,
}
use comp/user.{USApproved, USVoted, UserDatum}
use comp/utils

validator(params: AdminParams) {
  fn spend(
    input_datum: AdminDatum,
    redeemer: AdminRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let AdminParams {
      reward_rates,
      end_date,
      vote_policy_id,
      user_price,
      admin_price,
    } = params

    let Transaction {
      reference_inputs,
      inputs,
      outputs,
      validity_range,
      mint,
      ..
    } = context.transaction

    expect [script_input] =
      list.filter(inputs, fn(inp) { inp.output_reference == input_ref })
    let script_address = script_input.output.address

    let AdminDatum { state, user_address, ticket_policy_id, total_approved, .. } =
      input_datum

    let user_inputs =
      utils.inputs_with_asset(
        inputs,
        user_address,
        ticket_policy_id,
        "user-machine",
      )

    let user_outputs =
      utils.outputs_with_asset(
        outputs,
        user_address,
        ticket_policy_id,
        "user-machine",
      )

    let after_end_date = interval.is_entirely_before(validity_range, end_date)

    let script_output =
      utils.find_output_with_asset(
        outputs,
        script_address,
        ticket_policy_id,
        "admin-machine",
      )
    let script_output_datum = admin.find_datum(script_output.datum)

    when redeemer is {
      ARModApprove -> {
        expect [user_output] = user_outputs

        and {
          user.find_datum(user_output.datum).state == USApproved,
          utils.lovelace_geq(script_output.value, script_input.output.value),
          script_output_datum == AdminDatum {
            ..input_datum,
            total_approved: input_datum.total_approved + 1,
          },
        }
      }
      ARCollectRewards(auth) -> {
        let correct_state = state == ASVoting

        let users_num = list.length(user_inputs)
        let total_amount = user_price * users_num + admin_price

        let admin_expected =
          admin.calculate_rate(total_amount, reward_rates.admin)

        let mod_expected =
          admin.calculate_rate(total_amount, reward_rates.moderator)

        let user_amount = total_amount - admin_expected - mod_expected

        let user_datums =
          list.map(user_inputs, fn(inp) { user.find_datum(inp.output.datum) })

        expect Some(fst_dat) = list.head(user_datums)

        let (_, ordered_users) =
          list.foldr(
            user_datums,
            (fst_dat, True),
            fn(dat, acc) {
              let (last_dat, val) = acc

              let valid = and {
                  val,
                  dat.state == USVoted || dat.state == USApproved,
                  list.length(dat.votes) <= list.length(last_dat.votes),
                }

              (dat, valid)
            },
          )

        let all_users_present = list.length(user_inputs) == total_approved

        // Signed by admin and mod output correct
        let admin_authenticated =
          utils.nft_authenticated(
            context.transaction,
            auth,
            ticket_policy_id,
            "admin",
          )

        expect [mod_input] =
          list.filter(
            reference_inputs,
            fn(inp) {
              value.quantity_of(inp.output.value, ticket_policy_id, "mod") == 1
            },
          )

        expect [mod_output] =
          utils.find_outputs_with_address(outputs, mod_input.output.address)

        let mod_received = value.lovelace_of(mod_output.value) >= mod_expected

        let correct_value =
          value.lovelace_of(script_output.value) >= user_amount

        let winners_user_datums = list.slice(user_datums, 0, 2)

        let correct_datum =
          script_output_datum == AdminDatum {
            ..input_datum,
            state: ASRewarding,
            total_amount: total_amount,
            user_rewards: list.map(
              reward_rates.winners,
              fn(rate) { admin.calculate_rate(total_amount, rate.user) },
            ),
            user_asset_names: list.map(
              winners_user_datums,
              fn(dat) { dat.asset_name },
            ),
            vote_rewards: list.map(
              list.zip(winners_user_datums, reward_rates.winners),
              fn(win) {
                let (dat, rate) = win
                admin.calculate_rate(
                  total_amount,
                  rate.vote * list.length(dat.votes),
                )
              },
            ),
            vote_asset_names: list.map(
              winners_user_datums,
              fn(dat) { dat.votes },
            ),
          }

        expect [(an, amt)] =
          mint
            |> value.from_minted_value
            |> value.tokens(ticket_policy_id)
            |> dict.to_list

        let users_destroyed = an == "user-machine" && amt == -total_approved

        and {
          after_end_date?,
          ordered_users?,
          all_users_present?,
          admin_authenticated?,
          mod_received?,
          correct_state?,
          correct_value?,
          correct_datum?,
          users_destroyed?,
        }
      }
      ARClaimRewards { auth, asset_name, role } -> {
        let is_user =
          when role is {
            CRUser(_) -> True
            _ -> False
          }

        let expected_amount =
          when role is {
            CRUser(idx) -> {
              expect Some(amt) = list.at(input_datum.user_rewards, idx)
              amt
            }
            CRVoter(idx) -> {
              expect Some(amt) = list.at(input_datum.vote_rewards, idx)
              amt
            }
          }

        let valid_asset_name =
          when role is {
            CRUser(idx) -> {
              expect Some(an) = list.at(input_datum.user_asset_names, idx)
              an == asset_name
            }
            CRVoter(idx) -> {
              expect Some(ans) = list.at(input_datum.vote_asset_names, idx)
              list.has(ans, asset_name)
            }
          }

        let asset_not_claimed =
          if is_user {
            !list.has(input_datum.user_claimed, asset_name)
          } else {
            !list.has(input_datum.vote_claimed, asset_name)
          }

        let user_authenticatd =
          utils.nft_authenticated(
            context.transaction,
            auth,
            if is_user {
              ticket_policy_id
            } else {
              vote_policy_id
            },
            asset_name,
          )

        let right_output_value =
          value.lovelace_of(script_output.value) >= value.lovelace_of(
            script_input.output.value,
          ) - expected_amount

        let right_output_datum =
          script_output_datum == if is_user {
            AdminDatum {
              ..input_datum,
              user_claimed: list.delete(input_datum.user_claimed, asset_name),
            }
          } else {
            AdminDatum {
              ..input_datum,
              vote_claimed: list.delete(input_datum.vote_claimed, asset_name),
            }
          }

        and {
          valid_asset_name,
          asset_not_claimed,
          user_authenticatd?,
          right_output_value?,
          right_output_datum?,
        }
      }
    }
  }
}
