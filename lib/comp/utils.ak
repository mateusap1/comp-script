use aiken/bytearray
use aiken/dict
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/option
use aiken/time.{PosixTime}
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKey, VerificationKeyCredential,
}
use aiken/transaction/value.{AssetName, MintedValue, PolicyId}

pub type MintRedeemer {
  CreateComp
  CreateUser { utxo_ref: OutputReference }
}

pub type Auth {
  key: Hash<Blake2b_224, VerificationKey>,
  nft_ref: OutputReference,
}

pub type SpendRedeemer {
  AdminModApprove { auth: Auth, positive: Bool, user_nft_ref: OutputReference }
  AdminRewardDistribute
  UserModApprove { auth: Auth, positive: Bool, source_nft_ref: OutputReference }
  UserAddVote { auth: Auth }
  UserRewardDistribute
}

pub type CompetitionParams {
  utxo_ref: OutputReference,
  admin_price: Int,
  user_price: Int,
  vote_policy_id: PolicyId,
  end_date: PosixTime,
  reward_rates: RewardRates,
}

pub type WinnerRate {
  user: Int,
  vote: Int,
}

pub type RewardRates {
  admin: Int,
  moderator: Int,
  winners: List<WinnerRate>,
}

pub type Datum {
  AdminDatum {
    approved_votes: List<AssetName>,
    rejected_votes: List<AssetName>,
  }
  AwaitDatum { asset_name: AssetName }
  VoteDatum { asset_name: AssetName, votes: List<AssetName> }
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

pub fn find_datum(script_output: Output) -> Datum {
  expect InlineDatum(datum_raw) = script_output.datum
  expect datum: Datum = datum_raw
  datum
}

pub fn minted_right_nfts(
  mint: MintedValue,
  policy_id: PolicyId,
  expected_asset_names: List<AssetName>,
) -> Bool {
  let (minted_assets, minted_amounts) =
    mint
      |> value.from_minted_value
      |> value.tokens(policy_id)
      |> dict.to_list
      |> list.unzip

  let correct_names =
    list.sort(minted_assets, bytearray.compare) == list.sort(
      expected_asset_names,
      bytearray.compare,
    )

  let correct_amounts = list.all(minted_amounts, fn(an) { an == 1 })

  correct_names? && correct_amounts?
}

pub fn unique_nft_name(out_ref: OutputReference) {
  out_ref.transaction_id.hash
    |> bytearray.slice(0, 30)
    |> bytearray.push(out_ref.output_index)
}

pub fn permission_redeem_nft(
  tx: Transaction,
  redeem_policy_id: PolicyId,
  redeem_nft: AssetName,
  owner: Hash<Blake2b_224, VerificationKey>,
) -> Bool {
  // Find reference input from the supposed owner of the redeemer NFT
  expect Some(ref_from_owner) =
    tx.reference_inputs
      |> list.find(
          fn(input) {
            when input.output.address.payment_credential is {
              VerificationKeyCredential(credential) -> credential == owner
              _ -> False
            }
          },
        )

  // Assert that the redeem NFT is present in the reference UTxO
  let nft_present_in_reference =
    (
      ref_from_owner.output.value
        |> value.quantity_of(redeem_policy_id, redeem_nft)
    ) == 1

  // Make sure the owner of the redeem NFT actually signed this transaction
  let signed_by_owner = tx.extra_signatories |> list.has(owner)

  nft_present_in_reference && signed_by_owner
}

pub fn utxo_ref_present(tx: Transaction, utxo_ref: OutputReference) {
  let utxo_ref_index_one_byte = utxo_ref.output_index < 256

  let utxo_ref_present_input =
    tx.inputs |> transaction.find_input(utxo_ref) |> option.is_some()

  utxo_ref_index_one_byte? && utxo_ref_present_input?
}

pub fn unique_token_minted(
  tx: Transaction,
  output_reference: OutputReference,
  policy_id: PolicyId,
  assert_asset_name: AssetName,
) -> Bool {
  expect [(mint_asset_name, mint_amount)] =
    tx.mint
      |> value.from_minted_value
      |> value.tokens(policy_id)
      |> dict.to_list()

  let output_reference_index_one_byte = output_reference.output_index < 256

  let output_reference_present_input =
    when tx.inputs |> transaction.find_input(output_reference) is {
      Some(_) -> True
      _ -> False
    }

  let expected_asset_name =
    output_reference.transaction_id.hash
      |> bytearray.slice(0, 30)
      |> bytearray.push(output_reference.output_index)

  let correct_asset_name = and {
      expected_asset_name == mint_asset_name,
      expected_asset_name == assert_asset_name,
    }
  let correct_amount = mint_amount == 1

  and {
    output_reference_index_one_byte,
    output_reference_present_input,
    correct_asset_name,
    correct_amount,
  }
}

pub fn find_output_with_address(
  outputs: List<Output>,
  address: Address,
) -> Output {
  expect [script_output] =
    outputs |> list.filter(fn(out) { out.address == address })

  script_output
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
