use aiken/dict
use aiken/list
use aiken/transaction.{Mint, ScriptContext, Spend, Transaction}
use aiken/transaction/credential
use aiken/transaction/value
use vote/gift.{
  AddVote, Admin, BurnAction, ListVote, MintAction, MintRedeemer, Moderator,
  NftStoreDatum, Pricing, SpendRedeemer, Unlock, User, Vote,
}

validator(pricing: Pricing) {
  fn nft_mint(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    expect Mint(policy_id) = context.purpose

    let script_address = credential.from_script(policy_id)

    when redeemer is {
      MintAction { role, output_reference } -> {
        let receiver_output =
          context.transaction.outputs
            |> gift.find_output_with_address(script_address)

        let receiver_output_lovelace =
          receiver_output.value |> value.lovelace_of

        let correct_output_value =
          receiver_output_lovelace >= when role is {
            Admin -> pricing.admin
            Moderator -> pricing.moderator
            Vote -> pricing.vote
            User -> pricing.user
          }

        let datum = gift.find_datum(receiver_output)

        // Name is being verified by unique_token_minted function
        let correct_output_datum = and {
            datum.role == role,
            datum.votes == [],
          }

        let minted_unique_token =
          context.transaction
            |> gift.unique_token_minted(
                output_reference,
                policy_id,
                datum.asset_name,
              )

        and {
          correct_output_value?,
          correct_output_datum?,
          minted_unique_token?,
        }
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

        expect [(asset_name, amount)] =
          context.transaction.mint
            |> value.from_minted_value
            |> value.tokens(policy_id)
            |> dict.to_list()

        let correct_asset_name = asset_name == datum.asset_name
        let correct_amount = amount == -1

        can_redeem_nft? && script_output_dissapeared? && correct_asset_name? && correct_amount?
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

        let correct_value =
          value.lovelace_of(output.value) >= value.lovelace_of(
            script_input.output.value,
          )

        let correct_datum =
          output_datum == NftStoreDatum { ..datum, is_listed: True }

        can_list_vote_nft? && has_right_role? && correct_datum? && correct_value?
      }
      AddVote(owner_asset_name) -> {
        let can_add_vote_nft =
          context.transaction
            |> gift.permission_redeem_nft(
                policy_id,
                owner_asset_name,
                redeemer.owner,
              )
        let has_right_role = datum.role == Vote
        let nft_is_listed = datum.is_listed == True

        let output =
          context.transaction.outputs
            |> gift.find_output_with_address(script_input.output.address)

        let output_datum = gift.find_datum(output)

        let vote_not_repeated =
          list.find(datum.votes, fn(an) { an == owner_asset_name }) == None

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
          has_right_role?,
          nft_is_listed?,
          vote_not_repeated?,
          correct_value?,
          correct_datum?,
        }
      }
    }
  }
}
