use aiken/transaction/credential.{Address}

pub type Role {
  Admin
  Moderator
  Vote
  User
}

pub type Pricing {
  receiver_address: Address,
  admin: Int,
  moderator: Int,
  vote: Int,
  user: Int,
}

pub type Action {
  Mint { role: Role }
  Burn
}
