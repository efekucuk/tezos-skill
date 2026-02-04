// Simple DAO Contract Example
// Demonstrates governance patterns on Tezos

type proposal_id = nat

type proposal = {
  description: string;
  target: address;
  amount: tez;
  executed: bool;
  votes_for: nat;
  votes_against: nat;
  deadline: timestamp;
}

type vote = For | Against

type storage = {
  proposals: (proposal_id, proposal) big_map;
  votes: (proposal_id * address, vote) big_map;
  voting_power: (address, nat) big_map;
  next_proposal_id: proposal_id;
  quorum: nat;  // minimum votes needed
  voting_period: int;  // seconds
}

type action =
| Create_proposal of string * address * tez
| Vote of proposal_id * vote
| Execute of proposal_id
| Delegate_voting_power of address * nat

// Helper: get voting power
let get_voting_power (addr, storage : address * storage) : nat =
  match Big_map.find_opt addr storage.voting_power with
  | None -> 0n
  | Some power -> power

// Helper: check if already voted
let has_voted (proposal_id, voter, storage : proposal_id * address * storage) : bool =
  Big_map.mem (proposal_id, voter) storage.votes

// Create proposal
let create_proposal (description, target, amount, storage : string * address * tez * storage) : operation list * storage =
  let sender = Tezos.get_sender() in
  let power = get_voting_power(sender, storage) in

  // Must have voting power to create proposal
  if power = 0n then
    failwith "NO_VOTING_POWER"
  else
    let proposal_id = storage.next_proposal_id in
    let deadline = Tezos.get_now() + storage.voting_period in
    let proposal = {
      description = description;
      target = target;
      amount = amount;
      executed = false;
      votes_for = 0n;
      votes_against = 0n;
      deadline = deadline;
    } in
    let storage = {storage with
      proposals = Big_map.add proposal_id proposal storage.proposals;
      next_proposal_id = proposal_id + 1n;
    } in
    [], storage

// Vote on proposal
let vote (proposal_id, vote, storage : proposal_id * vote * storage) : operation list * storage =
  let sender = Tezos.get_sender() in
  let power = get_voting_power(sender, storage) in

  // Must have voting power
  if power = 0n then
    failwith "NO_VOTING_POWER"
  // Cannot vote twice
  else if has_voted(proposal_id, sender, storage) then
    failwith "ALREADY_VOTED"
  else
    match Big_map.find_opt proposal_id storage.proposals with
    | None -> failwith "PROPOSAL_NOT_FOUND"
    | Some proposal ->
      // Check deadline
      if Tezos.get_now() > proposal.deadline then
        failwith "VOTING_ENDED"
      else
        // Record vote
        let storage = {storage with
          votes = Big_map.add (proposal_id, sender) vote storage.votes
        } in
        // Update vote count
        let proposal = match vote with
          | For -> {proposal with votes_for = proposal.votes_for + power}
          | Against -> {proposal with votes_against = proposal.votes_against + power}
        in
        let storage = {storage with
          proposals = Big_map.update proposal_id (Some proposal) storage.proposals
        } in
        [], storage

// Execute proposal
let execute (proposal_id, storage : proposal_id * storage) : operation list * storage =
  match Big_map.find_opt proposal_id storage.proposals with
  | None -> failwith "PROPOSAL_NOT_FOUND"
  | Some proposal ->
    // Check if already executed
    if proposal.executed then
      failwith "ALREADY_EXECUTED"
    // Check if voting ended
    else if Tezos.get_now() <= proposal.deadline then
      failwith "VOTING_NOT_ENDED"
    // Check if passed (votes_for > votes_against and meets quorum)
    else if proposal.votes_for <= proposal.votes_against then
      failwith "PROPOSAL_REJECTED"
    else if proposal.votes_for < storage.quorum then
      failwith "QUORUM_NOT_REACHED"
    else
      // Execute: send funds to target
      let contract = match Tezos.get_contract_opt(proposal.target) with
        | None -> failwith "INVALID_TARGET"
        | Some c -> c
      in
      let op = Tezos.transaction () proposal.amount contract in
      // Mark as executed
      let proposal = {proposal with executed = true} in
      let storage = {storage with
        proposals = Big_map.update proposal_id (Some proposal) storage.proposals
      } in
      [op], storage

// Delegate voting power
let delegate_voting_power (to_, amount, storage : address * nat * storage) : operation list * storage =
  let sender = Tezos.get_sender() in
  let sender_power = get_voting_power(sender, storage) in

  if amount > sender_power then
    failwith "INSUFFICIENT_VOTING_POWER"
  else
    let to_power = get_voting_power(to_, storage) in
    let storage = {storage with
      voting_power = Big_map.update sender (Some (sender_power - amount)) storage.voting_power;
    } in
    let storage = {storage with
      voting_power = Big_map.update to_ (Some (to_power + amount)) storage.voting_power;
    } in
    [], storage

// Main entry point
let main (action, storage : action * storage) : operation list * storage =
  match action with
  | Create_proposal (desc, target, amount) -> create_proposal(desc, target, amount, storage)
  | Vote (proposal_id, vote) -> vote(proposal_id, vote, storage)
  | Execute proposal_id -> execute(proposal_id, storage)
  | Delegate_voting_power (to_, amount) -> delegate_voting_power(to_, amount, storage)
