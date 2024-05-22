use aiken/bytearray
use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{Mint, OutputReference, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value
use comp/utils.{
  AdminDatum, AdminModApprove, Auth, AwaitDatum, CompetitionParams, CreateComp,
  CreateUser, Datum, MintRedeemer, SpendRedeemer, UserAddVote, UserModApprove,
  VoteDatum,
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

  fn spend(
    redeemer: SpendRedeemer,
    input_datum: Datum,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(input_ref) = context.purpose

    let CompetitionParams { admin_price, user_price, .. } = params

    let Transaction { inputs, reference_inputs, outputs, extra_signatories, .. } =
      context.transaction

    expect Some(input) = transaction.find_input(inputs, input_ref)

    let address = input.output.address
    let policy_id = utils.policy_id_from_address(address)

    when redeemer is {
      AdminModApprove { auth, positive, user_nft_ref } -> {
        let output =
          utils.find_output_with_asset(
            outputs,
            address,
            policy_id,
            "source-machine",
          )
        let output_datum = utils.find_datum(output)

        // Check the auth
        let Auth { key, nft_ref } = auth

        expect Some(auth_input) =
          transaction.find_input(reference_inputs, nft_ref)

        let mod_authenticated = and {
            value.quantity_of(auth_input.output.value, policy_id, "mod") == 1,
            list.has(extra_signatories, key),
          }

        // Make sure user is valid
        expect Some(user_input) = transaction.find_input(inputs, user_nft_ref)

        let user_datum = utils.find_datum(user_input.output)
        expect AwaitDatum(user_asset_name) = user_datum

        let valid_user =
          value.quantity_of(user_input.output.value, policy_id, "user-machine") == 1

        let right_output_lovelace =
          value.lovelace_of(output.value) >= value.lovelace_of(
            input.output.value,
          )

        expect AdminDatum {
          approved_votes: inp_app_votes,
          rejected_votes: inp_rej_votes,
        } = input_datum

        expect AdminDatum {
          approved_votes: out_app_votes,
          rejected_votes: out_rej_votes,
        } = output_datum

        let right_output_datum =
          if positive {
            and {
              out_app_votes == [user_asset_name, ..inp_app_votes],
              out_rej_votes == inp_rej_votes,
            }
          } else {
            and {
              out_app_votes == inp_app_votes,
              out_rej_votes == [user_asset_name, ..inp_rej_votes],
            }
          }

        and {
          mod_authenticated?,
          valid_user?,
          right_output_lovelace?,
          right_output_datum?,
        }
      }
      UserModApprove { auth, positive, source_nft_ref } -> {
        // Check the auth
        let Auth { key, nft_ref } = auth

        expect Some(auth_input) =
          transaction.find_input(reference_inputs, nft_ref)

        let mod_authenticated = and {
            value.quantity_of(auth_input.output.value, policy_id, "mod") == 1,
            list.has(extra_signatories, key),
          }

        // Make sure source is valid
        expect Some(source_input) =
          transaction.find_input(inputs, source_nft_ref)

        let valid_source =
          value.quantity_of(
            source_input.output.value,
            policy_id,
            "source-machine",
          ) == 1

        let right_output =
          if positive {
            let output =
              utils.find_output_with_asset(
                outputs,
                address,
                policy_id,
                "user-machine",
              )
            let output_datum = utils.find_datum(output)

            expect AwaitDatum { asset_name: inp_an } = input_datum
            expect VoteDatum { asset_name: out_an, votes: out_votes } =
              output_datum

            and {
              value.lovelace_of(output.value) >= value.lovelace_of(
                input.output.value,
              ),
              out_an == inp_an,
              out_votes == [],
            }
          } else {
            utils.outputs_with_asset(
              outputs,
              address,
              policy_id,
              "user-machine",
            ) == []
          }
        and {
          mod_authenticated?,
          valid_source?,
          right_output?,
        }
      }
      UserAddVote(auth) -> {
        // Check the auth
        let Auth { key, nft_ref } = auth

        expect Some(auth_input) =
          transaction.find_input(reference_inputs, nft_ref)

        let votes =
          auth_input.output.value
            |> value.tokens(policy_id)

        let vote_assets = votes |> dict.keys

        let vote_power =
          votes
            |> dict.values
            |> list.length

        let vote_authenticated = and {
            vote_power > 0,
            list.has(extra_signatories, key),
          }

        let output =
          utils.find_output_with_asset(
            outputs,
            address,
            policy_id,
            "user-machine",
          )
        let valid_lovelace =
          value.lovelace_of(output.value) >= value.lovelace_of(
            input.output.value,
          )

        let output_datum = utils.find_datum(output)

        expect VoteDatum { asset_name: inp_an, votes: inp_votes } = input_datum
        expect VoteDatum { asset_name: out_an, votes: out_votes } = output_datum

        let valid_datum = and {
            inp_an == out_an,
            out_votes == list.concat(vote_assets, inp_votes),
          }

        and {
          vote_authenticated?,
          valid_lovelace?,
          valid_datum?,
        }
      }
      _ -> False
    }
  }
}
