use aiken/bytearray
use aiken/dict
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, TransactionId,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKey, VerificationKeyCredential,
}
use aiken/transaction/value.{AssetName, PolicyId}

pub type Role {
  Admin
  Moderator
  Vote
  User
}

pub type Pricing {
  admin: Int,
  moderator: Int,
  vote: Int,
  user: Int,
}

pub type MintData {
  role: Role,
  output_reference: OutputReference,
  asset_name: AssetName,
}

pub type MintRedeemer {
  MintAction { mints: List<MintData>, index_output_range: (Int, Int) }
  BurnAction
}

pub type SpendAction {
  ListVote
  AddVote { owner_asset_name: AssetName }
  Review { owner_asset_name: AssetName, approve: Bool }
  Unlock
}

pub type SpendRedeemer {
  owner: Hash<Blake2b_224, VerificationKey>,
  action: SpendAction,
}

pub type NftStoreDatum {
  asset_name: AssetName,
  role: Role,
  is_listed: Bool,
  is_approved: Bool,
  is_rejected: Bool,
  votes: List<AssetName>,
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

pub fn find_datum(script_output: Output) -> NftStoreDatum {
  expect InlineDatum(datum_raw) = script_output.datum
  expect datum: NftStoreDatum = datum_raw
  datum
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

pub fn correct_nft_name_mint(
  tx: Transaction,
  output_reference: OutputReference,
  assert_asset_name: AssetName,
) {
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

  let correct_asset_name = expected_asset_name == assert_asset_name

  and {
    output_reference_index_one_byte,
    output_reference_present_input,
    correct_asset_name,
  }
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

pub fn validate_token(
  pricing: Pricing,
  tx: Transaction,
  policy_id: PolicyId,
  mint_data: MintData,
  script_output: Output,
) -> Bool {
  let MintData { role, output_reference, asset_name } = mint_data

  let correct_mint_nft =
    (
      tx.mint
        |> value.from_minted_value
        |> value.quantity_of(policy_id, asset_name)
    ) == 1

  let script_output_valid_nft_present =
    value.quantity_of(script_output.value, policy_id, "valid") == 1

  let script_output_lovelace = value.lovelace_of(script_output.value)

  let correct_output_value =
    script_output_lovelace >= when role is {
      Admin -> pricing.admin
      Moderator -> pricing.moderator
      Vote -> pricing.vote
      User -> pricing.user
    }

  let datum = find_datum(script_output)

  let correct_output_datum =
    datum == NftStoreDatum {
      role,
      votes: [],
      is_listed: False,
      is_approved: False,
      is_rejected: False,
      asset_name,
    }

  let mint_correct_token =
    tx |> correct_nft_name_mint(output_reference, asset_name)

  and {
    correct_mint_nft?,
    script_output_valid_nft_present?,
    correct_output_value?,
    correct_output_datum?,
    mint_correct_token?,
  }
}
