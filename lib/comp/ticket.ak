use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Address}

pub type TicketRedeemer {
  TRInit
  TRAddUser { utxo_refs: List<(OutputReference, Int)> }
  TRBurn
}

pub type TicketParams {
  utxo_ref: OutputReference,
  admin_address: Address,
  user_address: Address,
  end_date: Int,
  admin_price: Int,
  user_price: Int,
}
