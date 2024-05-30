use aiken/time.{PosixTime}
use aiken/transaction.{Datum, InlineDatum}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use comp/utils.{Auth}

pub type UserParams {
  end_date: PosixTime,
  vote_policy_id: PolicyId,
}

pub type UserState {
  USRejected
  USApproved
  USAwaiting
  USVoted
}

pub type UserDatum {
  admin_address: Address,
  ticket_policy_id: PolicyId,
  state: UserState,
  asset_name: AssetName,
  votes: List<AssetName>,
}

pub type UserRedeemer {
  URModApprove { auth: Auth, is_approve: Bool }
  URAddVote { auth: Auth, vote_asset_name: AssetName }
  URCollect
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
