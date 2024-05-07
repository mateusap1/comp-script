use aiken/transaction.{
  Input, NoDatum, Output, OutputReference, ScriptContext, Transaction,
  TransactionId,
} as transaction
use aiken/transaction/credential
use aiken/transaction/value.{PolicyId, Value}
use vote/gift.{Action, Admin, Mint, Pricing}

pub type GiftTestConfig {
  policy_id: PolicyId,
  token_name: ByteArray,
  utxo_ref: OutputReference,
  pricing: Pricing,
  redeemer: Action,
  mint: Value,
  outputs: List<Output>,
}

pub fn generate_gift_config() -> GiftTestConfig {
  let policy_id = #"a0"
  let token_name = "token"
  let sample_utxo_ref =
    OutputReference { transaction_id: TransactionId(#"b0"), output_index: 0 }
  let pricing =
    Pricing {
      receiver_address: credential.from_verification_key(#"c0"),
      admin: 1_000_000,
      moderator: 2_000_000,
      vote: 3_000_000,
      user: 4_000_000,
    }
  let redeemer = Mint(Admin)
  let mint = value.from_asset(policy_id, token_name, 1)
  let outputs =
    [
      Output {
        address: pricing.receiver_address,
        value: value.from_lovelace(1_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    ]

  GiftTestConfig {
    policy_id,
    token_name,
    utxo_ref: sample_utxo_ref,
    pricing,
    redeemer,
    mint,
    outputs,
  }
}

pub fn context_from_gift_config(gift_config: GiftTestConfig) -> ScriptContext {
  let transaction =
    transaction.placeholder()
      |> fn(transaction) {
          Transaction {
            ..transaction,
            inputs: [
              Input {
                output_reference: gift_config.utxo_ref,
                output: Output {
                  address: credential.from_verification_key(""),
                  value: value.zero(),
                  datum: NoDatum,
                  reference_script: None,
                },
              },
            ],
            outputs: gift_config.outputs,
            mint: gift_config.mint |> value.to_minted_value,
          }
        }
  ScriptContext {
    purpose: transaction.Mint(gift_config.policy_id),
    transaction,
  }
}
