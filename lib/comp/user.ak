use aiken/time.{PosixTime}
use aiken/transaction.{Datum, InlineDatum}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use comp/utils.{Auth}

pub type UserDatum {
  is_rejected: Bool,
  asset_name: AssetName,
  ticket_policy_id: PolicyId,
  end_date: PosixTime,
  votes: List<AssetName>,
}

pub type UserRedeemer {
  UModApprove { auth: Auth, is_approve: Bool }
  UAddVote { auth: Auth, vote_asset_name: AssetName }
  UCollect
}

pub fn find_datum(datum: Datum) -> UserDatum {
  expect InlineDatum(datum_raw) = datum
  expect datum: UserDatum = datum_raw
  datum
}

pub type UserValidationData {
  asset_name: AssetName,
  address: Address,
  value: Value,
  datum: UserDatum,
}
