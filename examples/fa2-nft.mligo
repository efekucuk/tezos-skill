// FA2 NFT Contract Example
// Simple NFT implementation following TZIP-12

type token_id = nat

type token_metadata = {
  token_id: token_id;
  token_info: (string, bytes) map;
}

type transfer_destination = {
  to_: address;
  token_id: token_id;
  amount: nat;
}

type transfer = {
  from_: address;
  txs: transfer_destination list;
}

type balance_of_request = {
  owner: address;
  token_id: token_id;
}

type balance_of_response = {
  request: balance_of_request;
  balance: nat;
}

type operator_param = {
  owner: address;
  operator: address;
  token_id: token_id;
}

type storage = {
  ledger: (address * token_id, nat) big_map;
  operators: (address * address * token_id, unit) big_map;
  token_metadata: (token_id, token_metadata) big_map;
  next_token_id: token_id;
  admin: address;
}

type action =
| Transfer of transfer list
| Balance_of of balance_of_request list * (balance_of_response list contract)
| Update_operators of operator_param list
| Mint of address * (string, bytes) map

// Helper: check if operator is authorized
let is_operator (owner, operator, token_id, storage : address * address * token_id * storage) : bool =
  owner = operator ||
  Big_map.mem (owner, operator, token_id) storage.operators

// Helper: get balance
let get_balance (owner, token_id, storage : address * token_id * storage) : nat =
  match Big_map.find_opt (owner, token_id) storage.ledger with
  | None -> 0n
  | Some balance -> balance

// Helper: update balance
let update_balance (owner, token_id, amount, storage : address * token_id * nat * storage) : storage =
  {storage with ledger = Big_map.update (owner, token_id) (Some amount) storage.ledger}

// Transfer implementation
let transfer (transfers, storage : transfer list * storage) : operation list * storage =
  let process_transfer (storage, transfer : storage * transfer) =
    let sender = Tezos.get_sender() in
    List.fold_left
      (fun (storage, tx) ->
        // For NFTs, amount must be 0 or 1
        if tx.amount <> 0n && tx.amount <> 1n then
          failwith "NFT_INVALID_AMOUNT"
        else if tx.amount = 0n then
          storage
        else
          // Check authorization
          if not is_operator(transfer.from_, sender, tx.token_id, storage) then
            failwith "FA2_NOT_OPERATOR"
          // Check balance
          else if get_balance(transfer.from_, tx.token_id, storage) < tx.amount then
            failwith "FA2_INSUFFICIENT_BALANCE"
          // Transfer
          else
            let storage = update_balance(transfer.from_, tx.token_id, 0n, storage) in
            update_balance(tx.to_, tx.token_id, tx.amount, storage))
      storage
      transfer.txs
  in
  let storage = List.fold_left process_transfer storage transfers in
  [], storage

// Balance_of implementation
let balance_of (requests, callback, storage : balance_of_request list * (balance_of_response list contract) * storage) : operation list * storage =
  let responses = List.map
    (fun (request : balance_of_request) ->
      let balance = get_balance(request.owner, request.token_id, storage) in
      {request = request; balance = balance})
    requests
  in
  let op = Tezos.transaction responses 0mutez callback in
  [op], storage

// Update_operators implementation
let update_operators (updates, storage : operator_param list * storage) : operation list * storage =
  let sender = Tezos.get_sender() in
  let process_update (storage, update : storage * operator_param) =
    if sender <> update.owner then
      failwith "FA2_NOT_OWNER"
    else
      {storage with operators = Big_map.update (update.owner, update.operator, update.token_id) (Some ()) storage.operators}
  in
  let storage = List.fold_left process_update storage updates in
  [], storage

// Mint implementation (admin only)
let mint (to_, metadata, storage : address * (string, bytes) map * storage) : operation list * storage =
  if Tezos.get_sender() <> storage.admin then
    failwith "NOT_ADMIN"
  else
    let token_id = storage.next_token_id in
    let token_meta = {
      token_id = token_id;
      token_info = metadata;
    } in
    let storage = {storage with
      next_token_id = token_id + 1n;
      token_metadata = Big_map.add token_id token_meta storage.token_metadata;
      ledger = Big_map.add (to_, token_id) 1n storage.ledger;
    } in
    [], storage

// Main entry point
let main (action, storage : action * storage) : operation list * storage =
  match action with
  | Transfer transfers -> transfer(transfers, storage)
  | Balance_of (requests, callback) -> balance_of(requests, callback, storage)
  | Update_operators updates -> update_operators(updates, storage)
  | Mint (to_, metadata) -> mint(to_, metadata, storage)
