// use aiken/bytearray
// use aiken/dict
// use aiken/interval
// use aiken/list
// use aiken/option
// use aiken/transaction.{Mint, Output, ScriptContext, Spend, Transaction}
// use aiken/transaction/credential
// use aiken/transaction/value

// validator(params: CompetitionParams) {
//   fn spend(
//     input_datum: ScriptDatum,
//     redeemer: SpendRedeemer,
//     context: ScriptContext,
//   ) -> Bool {
//     expect Spend(input_ref) = context.purpose

//     let Transaction { inputs, outputs, validity_range, .. } =
//       context.transaction

//     expect Some(input) = transaction.find_input(inputs, input_ref)
//     let address = input.output.address

//     expect Some(first_input) =
//       list.find(inputs, fn(inp) { inp.output.address == address })

//     let is_first_input = first_input == input

//     if !is_first_input {
//       // If it is the first script of the inputs, execute, otherwise return true

//       True
//     } else {
//       let policy_id = utils.policy_id_from_address(address)

//       when redeemer is {
//         ModApprove { auth, is_approve } -> {
//           // The following is so we know that we have a unique admin
//           // script input and a unique admin script output
//           // Also that their datum is CurationDatum
//           let admin_input =
//             utils.find_input_with_asset(
//               inputs,
//               address,
//               policy_id,
//               "admin-machine",
//             )
//           let admin_input_datum = utils.find_datum(admin_input.output.datum)
//           expect CurationDatum {
//             approved_votes: admin_input_app,
//             rejected_votes: admin_input_rej,
//           } = admin_input_datum

//           let admin_output =
//             utils.find_output_with_asset(
//               outputs,
//               address,
//               policy_id,
//               "admin-machine",
//             )
//           let admin_output_datum = utils.find_datum(admin_output.datum)
//           expect CurationDatum {
//             approved_votes: admin_output_app,
//             rejected_votes: admin_output_rej,
//           } = admin_output_datum

//           // Let's get the user information now
//           let user_input =
//             utils.find_input_with_asset(
//               inputs,
//               address,
//               policy_id,
//               "user-machine",
//             )
//           let user_input_datum = utils.find_datum(user_input.output.datum)
//           expect ReviewDatum(user_input_asset_name) = user_input_datum

//           let user_outputs =
//             utils.outputs_with_asset(
//               outputs,
//               address,
//               policy_id,
//               "user-machine",
//             )

//           let before_end_date =
//             interval.is_entirely_before(validity_range, params.end_date)

//           let admin_input_value = admin_input.output.value
//           let admin_output_value = admin_output.value

//           let right_admin_value =
//             utils.lovelace_geq(admin_input_value, admin_output_value)

//           let expected_app_votes =
//             if is_approve {
//               [user_input_asset_name, ..admin_input_app]
//             } else {
//               admin_input_app
//             }
//           let expected_rej_votes =
//             if is_approve {
//               admin_input_rej
//             } else {
//               [user_input_asset_name, ..admin_input_rej]
//             }

//           let right_admin_datum = and {
//               admin_output_app == expected_app_votes,
//               admin_output_rej == expected_rej_votes,
//             }

//           let mod_authenticated =
//             context.transaction
//               |> utils.nft_authenticated(auth, policy_id, "mod")

//           let right_user_value =
//             when user_outputs is {
//               [Output { value: user_output_value, .. }] ->
//                 utils.lovelace_geq(user_output_value, user_input.output.value)
//               _ -> False
//             }

//           let right_user_datum =
//             when user_outputs is {
//               [Output { datum, .. }] -> {
//                 let user_output_datum = utils.find_datum(datum)
//                 if is_approve {
//                   expect VoteDatum { asset_name, votes } = user_output_datum
//                   asset_name == user_input_asset_name && votes == []
//                 } else {
//                   expect RejectDatum { asset_name } = user_output_datum
//                   asset_name == user_input_asset_name
//                 }
//               }
//               _ -> False
//             }

//           and {
//             before_end_date?,
//             right_admin_value?,
//             right_admin_datum?,
//             mod_authenticated?,
//             right_user_value?,
//             right_user_datum,
//           }
//         }
//         AddVote(auth, vote_asset_name) -> {
//           let user_input =
//             utils.find_input_with_asset(
//               inputs,
//               address,
//               policy_id,
//               "user-machine",
//             )
//           let user_input_datum = utils.find_datum(user_input.output.datum)
//           expect VoteDatum {
//             asset_name: user_input_asset_name,
//             votes: user_input_votes,
//           } = user_input_datum

//           let user_output =
//             utils.find_output_with_asset(
//               outputs,
//               address,
//               policy_id,
//               "user-machine",
//             )
//           let user_output_datum = utils.find_datum(user_output.datum)
//           expect VoteDatum {
//             asset_name: user_output_asset_name,
//             votes: user_output_votes,
//           } = user_output_datum

//           let before_end_date =
//             interval.is_entirely_before(validity_range, params.end_date)

//           let right_user_value =
//             utils.lovelace_geq(user_output.value, user_input.output.value)

//           let right_user_datum = and {
//               user_output_asset_name == user_input_asset_name,
//               user_output_votes == [vote_asset_name, ..user_input_votes],
//             }

//           let vote_not_repeated =
//             user_input_votes
//               |> list.find(fn(an) { an == vote_asset_name })
//               |> option.is_none()

//           let vote_authenticated =
//             context.transaction
//               |> utils.nft_authenticated(
//                   auth,
//                   params.vote_policy_id,
//                   vote_asset_name,
//                 )
//           let unique_script_input =
//             (
//               inputs
//                 |> list.filter(fn(inp) { inp.output.address == address })
//                 |> list.length
//             ) == 1

//           and {
//             before_end_date?,
//             right_user_value?,
//             right_user_datum?,
//             vote_not_repeated?,
//             vote_authenticated?,
//             unique_script_input?,
//           }
//         }
//         _ -> False
//       }
//     }
//   }
// }
