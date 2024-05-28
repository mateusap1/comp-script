use aiken/bytearray
use aiken/dict
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/option
use aiken/transaction.{
  Input, Output, OutputReference, Transaction, TransactionId,
}
use aiken/transaction/credential.{Address, ScriptCredential, VerificationKey}
use aiken/transaction/value.{AssetName, MintedValue, PolicyId, Value}

pub type ValidationData<d> {
  address: Address,
  value: Value,
  datum: d,
}

pub type Auth {
  key: Hash<Blake2b_224, VerificationKey>,
  nft_ref: OutputReference,
}

pub fn address_from_policy_id(policy_id: PolicyId) -> Address {
  Address {
    payment_credential: ScriptCredential(policy_id),
    stake_credential: None,
  }
}

pub fn policy_id_from_address(address: Address) -> PolicyId {
  expect ScriptCredential(script_hash) = address.payment_credential
  script_hash
}

pub fn lovelace_geq(value_geq: Value, value_less: Value) {
  value.lovelace_of(value_geq) >= value.lovelace_of(value_less)
}

pub fn minted_right_nfts(
  mint: MintedValue,
  policy_id: PolicyId,
  expected_assets: List<(AssetName, Int)>,
) -> Bool {
  let minted_assets: List<(AssetName, Int)> =
    mint
      |> value.from_minted_value
      |> value.tokens(policy_id)
      |> dict.to_list

  let sorted_minted_list =
    list.sort(minted_assets, fn(a1, a2) { bytearray.compare(a1.1st, a2.1st) })
  let sorted_expected_list =
    list.sort(expected_assets, fn(a1, a2) { bytearray.compare(a1.1st, a2.1st) })

  sorted_minted_list == sorted_expected_list
}

pub fn unique_nft_name(out_ref: OutputReference) {
  out_ref.transaction_id.hash
    |> bytearray.slice(0, 30)
    |> bytearray.push(out_ref.output_index)
}

pub fn nft_authenticated(
  tx: Transaction,
  auth: Auth,
  policy_id: PolicyId,
  redeem_name: AssetName,
) -> Bool {
  let Auth { key, nft_ref } = auth

  expect Some(auth_input) = transaction.find_input(tx.reference_inputs, nft_ref)

  and {
    value.quantity_of(auth_input.output.value, policy_id, redeem_name) >= 1,
    list.has(tx.extra_signatories, key),
  }
}

pub fn utxo_ref_present(tx: Transaction, utxo_ref: OutputReference) {
  let utxo_ref_index_one_byte = utxo_ref.output_index < 256

  let utxo_ref_present_input =
    tx.inputs |> transaction.find_input(utxo_ref) |> option.is_some()

  utxo_ref_index_one_byte? && utxo_ref_present_input?
}

pub fn find_outputs_with_address(
  outputs: List<Output>,
  address: Address,
) -> List<Output> {
  list.filter(outputs, fn(out) { out.address == address })
}

pub fn inputs_with_asset(
  inputs: List<Input>,
  address: Address,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> List<Input> {
  inputs
    |> list.filter(fn(inp) { and {
            inp.output.address == address,
            value.quantity_of(inp.output.value, policy_id, asset_name) == 1,
          } })
}

pub fn find_input_with_asset(
  inputs: List<Input>,
  address: Address,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Input {
  expect [script_input] =
    inputs_with_asset(inputs, address, policy_id, asset_name)

  script_input
}

pub fn outputs_with_asset(
  outputs: List<Output>,
  address: Address,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> List<Output> {
  outputs
    |> list.filter(fn(out) { and {
            out.address == address,
            value.quantity_of(out.value, policy_id, asset_name) == 1,
          } })
}

pub fn find_output_with_asset(
  outputs: List<Output>,
  address: Address,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Output {
  expect [script_output] =
    outputs_with_asset(outputs, address, policy_id, asset_name)

  script_output
}
