use aiken/math/rational
use aiken/time.{PosixTime}
use aiken/transaction.{Datum, InlineDatum}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use comp/utils.{Auth}

pub type AdminParams {
  reward_rates: RewardRates,
  end_date: PosixTime,
  vote_policy_id: PolicyId,
  admin_price: Int,
  user_price: Int,
}

pub type AdminState {
  ASVoting
  ASRewarding
}

pub type AdminDatum {
  state: AdminState,
  user_address: Address,
  total_approved: Int,
  total_amount: Int,
  ticket_policy_id: PolicyId,
  user_rewards: List<Int>,
  user_asset_names: List<AssetName>,
  user_claimed: List<AssetName>,
  vote_rewards: List<Int>,
  vote_asset_names: List<List<AssetName>>,
  vote_claimed: List<AssetName>,
}

pub type ClaimerRole {
  CRUser { index: Int }
  CRVoter { index: Int }
}

pub type AdminRedeemer {
  ARModApprove
  ARCollectRewards { auth: Auth }
  ARClaimRewards { auth: Auth, asset_name: AssetName, role: ClaimerRole }
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

pub fn find_datum(datum: Datum) -> AdminDatum {
  expect InlineDatum(datum_raw) = datum
  expect datum: AdminDatum = datum_raw
  datum
}

pub fn calculate_rate(total_amount: Int, rate_abs: Int) -> Int {
  expect Some(rate) = rational.new(rate_abs, 100)

  rational.mul(rate, rational.from_int(total_amount)) |> rational.truncate
}
