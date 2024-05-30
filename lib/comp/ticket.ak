use aiken/time.{PosixTime}
use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Address}

pub type TicketRedeemer {
  TRInit
  TRAddUser { utxo_refs: List<OutputReference> }
  TRBurn
}

pub type TicketParams {
  utxo_ref: OutputReference,
  admin_address: Address,
  user_address: Address,
  end_date: PosixTime,
  admin_price: Int,
  user_price: Int,
}
