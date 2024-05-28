use aiken/time.{PosixTime}
use aiken/transaction.{Datum, InlineDatum}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use comp/utils.{Auth}

pub type AdminDatum {
  ADVoting {
    user_address: Address,
    admin_price: Int,
    user_price: Int,
    ticket_policy_id: PolicyId,
    end_date: PosixTime,
    reward_rates: RewardRates,
    approved_votes: List<AssetName>,
  }
  ADRewards {
    user_distribution: List<(AssetName, Int)>,
    vote_distribution: List<(AssetName, Int)>,
  }
}

pub type AdminRedeemer {
  ARModApprove { auth: Auth }
  ARCollectRewards
  ARClaimRewards { asset_name: AssetName }
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
