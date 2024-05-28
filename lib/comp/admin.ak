use aiken/time.{PosixTime}
use aiken/transaction.{Datum, InlineDatum}
use aiken/transaction/value.{AssetName, PolicyId}
use comp/utils.{Auth}

pub type AdminDatum {
  admin_price: Int,
  user_price: Int,
  ticket_policy_id: PolicyId,
  end_date: PosixTime,
  reward_rates: RewardRates,
  approved_votes: List<AssetName>,
  rejected_votes: List<AssetName>,
}

pub type AdminRedeemer {
  AModApprove { auth: Auth, is_approve: Bool }
  ACollectRewards
  AClaimRewards { asset_name: AssetName, role: ClaimRole }
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

pub type ClaimRole {
  User
  Voter
}

pub fn find_datum(datum: Datum) -> AdminDatum {
  expect InlineDatum(datum_raw) = datum
  expect datum: AdminDatum = datum_raw
  datum
}
