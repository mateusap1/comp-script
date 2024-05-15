use aiken/dict
use aiken/list
use aiken/transaction.{Mint, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{ScriptCredential}
use aiken/transaction/value
use vote/gift.{
  AddVote, Approve, BurnAction, ListVote, MintAction, MintRedeemer, Moderator,
  NftStoreDatum, Pricing, SpendRedeemer, Unlock, User, Vote,
}

validator(pricing: Pricing) {
  fn nft_mint(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    expect Mint(policy_id) = context.purpose

    let script_address = credential.from_script(policy_id)

    when redeemer is {
      MintAction { mints, index_output_range } -> {
        // Make sure start_output_index is greater than zero
        let (start_index, end_index) = index_output_range

        // First let's get the script outputs
        let (script_outputs, _) =
          context.transaction.outputs
            |> list.foldr(
                ([], 0),
                fn(output, acc) {
                  let (outputs_acc, idx) = acc
                  if and {
                    idx >= start_index,
                    idx <= end_index,
                    output.address == script_address,
                  } {
                    ([output, ..outputs_acc], idx + 1)
                  } else {
                    (outputs_acc, idx + 1)
                  }
                },
              )

        let mints_length = list.length(mints)
        let correct_num_outputs = list.length(script_outputs) == mints_length

        let minted_value = context.transaction.mint |> value.from_minted_value

        let correct_num_mints =
          ( minted_value |> value.tokens(policy_id) |> dict.size ) == mints_length + 1

        let correct_num_mints_valid =
          value.quantity_of(minted_value, policy_id, "valid") == mints_length

        let correct_tokens =
          list.zip(mints, script_outputs)
            |> list.all(
                fn(token_data) {
                  gift.validate_token(
                    pricing,
                    context.transaction,
                    policy_id,
                    token_data.1st,
                    token_data.2nd,
                  )
                },
              )

        correct_num_outputs? && correct_num_mints? && correct_num_mints_valid? && correct_tokens?
      }
      BurnAction -> {
        expect [(_, mint_amount)] =
          context.transaction.mint
            |> value.from_minted_value
            |> value.tokens(policy_id)
            |> dict.to_list()
        mint_amount < 0
      }
    }
  }

  fn nft_redeem(
    datum: NftStoreDatum,
    redeemer: SpendRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(script_input_reference) = context.purpose

    expect Some(script_input) =
      context.transaction.inputs
        |> transaction.find_input(script_input_reference)

    let script_address = script_input.output.address
    let policy_id = gift.policy_id_from_address(script_address)

    when redeemer.action is {
      Unlock -> {
        let can_redeem_nft =
          context.transaction
            |> gift.permission_redeem_nft(
                policy_id,
                datum.asset_name,
                redeemer.owner,
              )

        let script_output_dissapeared =
          context.transaction.outputs
            |> list.all(fn(out) { out.address != script_address })

        let minted_value = context.transaction.mint |> value.from_minted_value

        let correct_num_burns =
          ( minted_value |> value.tokens(policy_id) |> dict.size ) == 2

        let correct_burn_nft =
          ( minted_value |> value.quantity_of(policy_id, datum.asset_name) ) == -1

        let correct_burn_valid_token =
          ( minted_value |> value.quantity_of(policy_id, "valid") ) == -1

        and {
          can_redeem_nft?,
          script_output_dissapeared?,
          correct_num_burns?,
          correct_burn_nft?,
          correct_burn_valid_token?,
        }
      }
      ListVote -> {
        let can_list_vote_nft =
          context.transaction
            |> gift.permission_redeem_nft(
                policy_id,
                datum.asset_name,
                redeemer.owner,
              )
        let has_right_role = datum.role == User

        let output =
          context.transaction.outputs
            |> gift.find_output_with_address(script_input.output.address)

        let output_datum = gift.find_datum(output)

        let valid_script_input =
          value.quantity_of(script_input.output.value, policy_id, "valid") == 1

        let valid_script_output =
          value.quantity_of(output.value, policy_id, "valid") == 1

        let correct_value =
          value.lovelace_of(output.value) >= value.lovelace_of(
            script_input.output.value,
          )

        let correct_datum =
          output_datum == NftStoreDatum { ..datum, is_listed: True }

        and {
          can_list_vote_nft?,
          has_right_role?,
          valid_script_input?,
          valid_script_output?,
          correct_datum?,
          correct_value?,
        }
      }

      AddVote(owner_asset_name) -> {
        let can_add_vote_nft =
          context.transaction
            |> gift.permission_redeem_nft(
                policy_id,
                owner_asset_name,
                redeemer.owner,
              )

        let not_voting_himself = datum.asset_name != owner_asset_name

        expect Some(owner_script_reference) =
          context.transaction.reference_inputs
            |> list.find(
                fn(input) {
                  when input.output.address.payment_credential is {
                    ScriptCredential(credential) -> credential == policy_id
                    _ -> False
                  }
                },
              )

        let owner_script_reference_datum =
          gift.find_datum(owner_script_reference.output)

        let correct_owner_reference =
          owner_script_reference_datum.asset_name == owner_asset_name

        let has_right_role = owner_script_reference_datum.role == Vote
        let nft_is_listed = datum.is_listed == True

        let output =
          context.transaction.outputs
            |> gift.find_output_with_address(script_input.output.address)

        let output_datum = gift.find_datum(output)

        let vote_not_repeated =
          list.find(datum.votes, fn(an) { an == owner_asset_name }) == None

        let valid_script_input =
          value.quantity_of(
            owner_script_reference.output.value,
            policy_id,
            "valid",
          ) == 1

        let valid_script_output =
          value.quantity_of(output.value, policy_id, "valid") == 1

        let correct_value =
          value.lovelace_of(output.value) >= value.lovelace_of(
            script_input.output.value,
          )

        let correct_datum =
          output_datum == NftStoreDatum {
            ..datum,
            votes: [owner_asset_name, ..datum.votes],
          }

        and {
          can_add_vote_nft?,
          not_voting_himself?,
          correct_owner_reference?,
          valid_script_input?,
          valid_script_output?,
          has_right_role?,
          nft_is_listed?,
          vote_not_repeated?,
          correct_value?,
          correct_datum?,
        }
      }
      Approve(owner_asset_name) -> {
        let vote_nft_present =
          context.transaction
            |> gift.permission_redeem_nft(
                policy_id,
                owner_asset_name,
                redeemer.owner,
              )

        expect Some(owner_script_reference) =
          context.transaction.reference_inputs
            |> list.find(
                fn(input) {
                  when input.output.address.payment_credential is {
                    ScriptCredential(credential) -> credential == policy_id
                    _ -> False
                  }
                },
              )

        let owner_script_reference_datum =
          gift.find_datum(owner_script_reference.output)

        let correct_owner_reference =
          owner_script_reference_datum.asset_name == owner_asset_name

        let has_right_role = owner_script_reference_datum.role == Moderator
        let nft_is_listed = datum.is_listed == True
        let nft_is_not_approved = datum.is_approved == False

        let output =
          context.transaction.outputs
            |> gift.find_output_with_address(script_input.output.address)

        let output_datum = gift.find_datum(output)

        let valid_script_input =
          value.quantity_of(
            owner_script_reference.output.value,
            policy_id,
            "valid",
          ) == 1

        let valid_script_output =
          value.quantity_of(output.value, policy_id, "valid") == 1

        let correct_value =
          value.lovelace_of(output.value) >= value.lovelace_of(
            script_input.output.value,
          )

        let correct_datum =
          output_datum == NftStoreDatum { ..datum, is_approved: True }

        and {
          vote_nft_present?,
          correct_owner_reference?,
          has_right_role?,
          nft_is_listed?,
          nft_is_not_approved?,
          valid_script_input?,
          valid_script_output?,
          correct_value?,
          correct_datum?,
        }
      }
    }
  }
}
