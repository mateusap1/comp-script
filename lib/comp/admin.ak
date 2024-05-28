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
    vote_policy_id: PolicyId,
    end_date: PosixTime,
    reward_rates: RewardRates,
    approved_votes: Int,
  }
  ADRewards {
    total_amount: Int,
    reward_rates: RewardRates,
    ticket_policy_id: PolicyId,
    vote_policy_id: PolicyId,
    first: (Option<AssetName>, List<AssetName>),
    second: (Option<AssetName>, List<AssetName>),
    third: (Option<AssetName>, List<AssetName>),
  }
}

pub type ClaimerRole {
  CRFirstUser
  CRFirstVoter { index: Int }

  CRSecondUser
  CRSecondVoter { index: Int }

  CRThirdUser
  CRThirdVoter { index: Int }
}

pub type AdminRedeemer {
  ARModApprove { auth: Auth }
  ARCollectRewards
  ARClaimRewards { auth: Auth, role: ClaimerRole }
}

pub type WinnerRate {
  user: Int,
  vote: Int,
}

pub type RewardRates {
  admin: Int,
  moderator: Int,
  first: WinnerRate,
  second: WinnerRate,
  third: WinnerRate,
}

pub fn find_datum(datum: Datum) -> AdminDatum {
  expect InlineDatum(datum_raw) = datum
  expect datum: AdminDatum = datum_raw
  datum
}
