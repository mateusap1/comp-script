use aiken/time.{PosixTime}
use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{PolicyId}

pub type TicketRedeemer {
  TRInit
  TRAddUser { utxo_refs: List<(OutputReference, Int)> }
  TRBurn
}

pub type TicketParams {
  utxo_ref: OutputReference,
  admin_address: Address,
  user_address: Address,
  end_date: PosixTime,
  vote_policy_id: PolicyId,
  admin_price: Int,
  user_price: Int,
}
