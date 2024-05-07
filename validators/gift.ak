use aiken/dict
use aiken/list
use aiken/transaction.{OutputReference, ScriptContext, Transaction} as tx
use aiken/transaction/value
use vote/gift.{Action, Admin, Burn, Mint, Moderator, Pricing, User, Vote}
use vote/tester/gift.{GiftTestConfig} as gift_tester

validator(token_name: ByteArray, utxo_ref: OutputReference, pricing: Pricing) {
  fn gift_card(rdmr: Action, ctx: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = ctx

    expect tx.Mint(policy_id) = purpose

    let Transaction { inputs, mint, .. } = transaction

    expect [(asset_name, amount)] =
      mint
        |> value.from_minted_value
        |> value.tokens(policy_id)
        |> dict.to_list()

    when rdmr is {
      Mint(role) -> {
        expect Some(receiver_output) =
          ctx.transaction.outputs
            |> list.find(fn(out) { out.address == pricing.receiver_address })

        let expected_price =
          when role is {
            Admin -> pricing.admin
            Moderator -> pricing.moderator
            Vote -> pricing.vote
            User -> pricing.user
          }

        expect Some(_input) =
          list.find(inputs, fn(input) { input.output_reference == utxo_ref })

        and {
          amount == 1,
          asset_name == token_name,
          value.lovelace_of(receiver_output.value) == expected_price,
        }
      }
      Burn -> amount == -1 && asset_name == token_name
    }
  }
}

validator(token_name: ByteArray, policy_id: ByteArray) {
  fn redeem(_d: Data, _r: Data, ctx: ScriptContext) -> Bool {
    let ScriptContext { transaction, .. } = ctx

    let Transaction { mint, .. } = transaction

    expect [(asset_name, amount)] =
      mint
        |> value.from_minted_value
        |> value.tokens(policy_id)
        |> dict.to_list()

    amount == -1 && asset_name == token_name
  }
}

test gift_card_success() {
  let gift_config = gift_tester.generate_gift_config()
  let gift_context = gift_tester.context_from_gift_config(gift_config)

  gift_card(
    gift_config.token_name,
    gift_config.utxo_ref,
    gift_config.pricing,
    gift_config.redeemer,
    gift_context,
  )
}
