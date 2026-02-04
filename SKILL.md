---
name: tezos
description: expert tezos blockchain development guidance. covers smart contracts, security patterns, gas optimization, and fa1.2/fa2 token standards. for building on tezos l1.
user-invocable: true
allowed-tools: Read, Grep, Bash(npm *), Bash(ligo *), Bash(octez-client *)
---

# tezos blockchain development

expert guidance for building on tezos. smart contracts, security, optimization.

## smart contract languages

### michelson
low-level stack-based language. use for:
- maximum control over execution
- gas optimization critical paths
- direct protocol interaction

characteristics:
- stack-based operations
- strongly typed
- no loops (use recursion)
- explicit failure handling

### ligo
high-level language (cameligo, jsligo). use for:
- most production contracts
- faster development
- better readability

```ligo
// cameligo example
type storage = {
  counter: nat;
  owner: address;
}

type action =
| Increment of nat
| Reset

let main (action, storage : action * storage) : operation list * storage =
  match action with
  | Increment n -> [], {storage with counter = storage.counter + n}
  | Reset -> [], {storage with counter = 0n}
```

### smartpy
python-based. use for:
- rapid prototyping
- python developers
- testing workflows

## security checklist

before deploying any contract:

### 1. reentrancy protection
always update state before external calls:

```ligo
// bad
let call_external (storage : storage) =
  let op = external_call() in
  let storage = {storage with called = true} in
  [op], storage

// good
let call_external (storage : storage) =
  let storage = {storage with called = true} in
  let op = external_call() in
  [op], storage
```

### 2. integer overflow
use appropriate types:
- `nat` for non-negative values
- `mutez` for currency amounts
- check bounds explicitly

```ligo
let add_tokens (amount, storage : nat * storage) : storage =
  if amount > 1000000n then
    failwith "amount too large"
  else
    {storage with balance = storage.balance + amount}
```

### 3. access control
validate sender for privileged operations:

```ligo
let check_admin (storage : storage) : unit =
  if Tezos.get_sender() <> storage.admin then
    failwith "not_admin"
  else ()
```

### 4. entry point validation
validate all parameters at entry boundaries:

```ligo
let validate_address (addr : address) : unit =
  match Tezos.get_contract_opt(addr) with
  | None -> failwith "invalid_address"
  | Some _ -> ()
```

### 5. storage optimization
minimize storage costs:
- use `big_map` for large collections
- pack data when possible
- avoid nested structures
- lazy evaluation patterns

### 6. gas limits
test operations stay within limits:
- simulate before deployment
- break complex ops into steps
- use views for read-only data

## common patterns

### admin pattern

```ligo
type storage = {
  admin: address;
  data: big_map(address, nat);
}

let check_admin (storage : storage) : unit =
  if Tezos.get_sender() <> storage.admin then
    failwith "not_admin"

let update_admin (new_admin, storage : address * storage) : operation list * storage =
  let () = check_admin(storage) in
  [], {storage with admin = new_admin}
```

### pausable pattern

```ligo
type storage = {
  paused: bool;
  // other fields
}

let check_not_paused (storage : storage) : unit =
  if storage.paused then
    failwith "contract_paused"

let pause (storage : storage) : operation list * storage =
  let () = check_admin(storage) in
  [], {storage with paused = true}

let unpause (storage : storage) : operation list * storage =
  let () = check_admin(storage) in
  [], {storage with paused = false}
```

### token transfer pattern

```ligo
let transfer (destination, amount, storage : address * tez * storage) : operation list * storage =
  let contract =
    match Tezos.get_contract_opt(destination) with
    | None -> failwith "invalid_destination"
    | Some c -> c
  in
  let op = Tezos.transaction () amount contract in
  [op], storage
```

### upgradeability pattern

```ligo
type storage = {
  logic_contract: address;
  data: big_map(string, bytes);
}

let delegate_call (params, storage : bytes * storage) : operation list * storage =
  let contract =
    match Tezos.get_entrypoint_opt "%execute" storage.logic_contract with
    | None -> failwith "logic_contract_invalid"
    | Some c -> c
  in
  let op = Tezos.transaction params 0mutez contract in
  [op], storage
```

## token standards (tzip)

### fa1.2 (tzip-7)
fungible tokens only. simple, gas-efficient.

entry points:
- `transfer` - move tokens between accounts
- `approve` - allow third-party transfers
- `getBalance` - query balance (view)
- `getAllowance` - query approval (view)
- `getTotalSupply` - total supply (view)

```ligo
type transfer_param = {
  from_: address;
  to_: address;
  value: nat;
}

let transfer (params, storage : transfer_param * storage) : operation list * storage =
  let sender = Tezos.get_sender() in
  // check balance
  let from_balance =
    match Big_map.find_opt params.from_ storage.ledger with
    | None -> 0n
    | Some b -> b
  in
  if from_balance < params.value then
    failwith "insufficient_balance"
  // update balances
  ...
```

### fa2 (tzip-12)
multi-token standard. supports fungible + nfts.

entry points:
- `transfer` - move tokens (supports batch)
- `balance_of` - query balances (callback pattern)
- `update_operators` - manage transfer permissions

```ligo
type transfer_destination = {
  to_: address;
  token_id: nat;
  amount: nat;
}

type transfer = {
  from_: address;
  txs: transfer_destination list;
}

let transfer (transfers, storage : transfer list * storage) : operation list * storage =
  let process_transfer (storage, transfer : storage * transfer) =
    List.fold_left
      (fun (storage, tx) ->
        // validate and update balances
        validate_transfer(transfer.from_, tx, storage);
        update_balances(transfer.from_, tx, storage))
      storage
      transfer.txs
  in
  let storage = List.fold_left process_transfer storage transfers in
  [], storage
```

### fa2.1
enhanced with ticket support for better composability.

## gas optimization techniques

### 1. minimize storage reads
cache frequently accessed values:

```ligo
// bad - multiple reads
let process (storage : storage) =
  if storage.config.enabled then
    if storage.config.rate > 0n then
      storage.config.rate * 2n

// good - single read
let process (storage : storage) =
  let config = storage.config in
  if config.enabled then
    if config.rate > 0n then
      config.rate * 2n
```

### 2. use views for read-only operations
no gas cost for view calls:

```ligo
[@view]
let get_balance (owner, storage : address * storage) : nat =
  match Big_map.find_opt owner storage.ledger with
  | None -> 0n
  | Some balance -> balance
```

### 3. batch operations
combine multiple ops:

```ligo
// instead of multiple calls
transfer(addr1, 100n);
transfer(addr2, 200n);
transfer(addr3, 300n);

// batch
batch_transfer([
  {to_: addr1, amount: 100n};
  {to_: addr2, amount: 200n};
  {to_: addr3, amount: 300n};
])
```

### 4. optimize data structures
use appropriate collections:

```ligo
// bad - map in storage (expensive)
type storage = {
  users: (address, user_data) map;
}

// good - big_map in storage (efficient)
type storage = {
  users: (address, user_data) big_map;
}
```

### 5. pack data efficiently

```ligo
let store_metadata (data, storage : metadata * storage) : storage =
  let packed = Bytes.pack(data) in
  {storage with metadata = packed}
```

## networks

### mainnet
production deployments only. costs real xtz.
- rpc: `https://mainnet.api.tez.ie`
- explorer: https://tzkt.io
- always test on shadownet first

### shadownet
primary testnet. use for all development.
- rpc: `https://rpc.shadownet.teztnets.com`
- faucet: https://faucet.shadownet.teztnets.com
- explorer: https://shadownet.tzkt.io
- similar to mainnet, long-running

### ghostnet
legacy testnet. being deprecated.
- migrate existing projects to shadownet
- rpc: `https://rpc.ghostnet.teztnets.com`

## testing strategy

### 1. unit tests
test individual entry points:

```bash
ligo run test contract_test.mligo
```

test edge cases:
- zero amounts
- maximum values
- unauthorized access
- invalid parameters

### 2. integration tests
test contract interactions:

```bash
octez-client \
  --endpoint https://rpc.shadownet.teztnets.com \
  transfer 0 from alice to contract \
  --entrypoint mint \
  --arg '{"amount": 1000}'
```

### 3. simulation
dry-run before committing:

```bash
octez-client \
  --endpoint https://rpc.shadownet.teztnets.com \
  transfer 0 from alice to contract \
  --entrypoint transfer \
  --arg '{"from": "tz1...", "to": "tz2...", "amount": 100}' \
  --dry-run
```

### 4. security audit
before mainnet:
- professional audit for high-value contracts
- peer review
- bug bounty program
- formal verification if critical

## common gotchas

### amounts are in mutez
always work in mutez internally:

```ligo
// bad
let amount = 1  // is this xtz or mutez?

// good
let amount = 1_000_000n  // 1 xtz = 1M mutez (explicit)
```

### timestamps are block time
use `Tezos.get_now()`, not system time:

```ligo
let check_deadline (storage : storage) : unit =
  if Tezos.get_now() > storage.deadline then
    failwith "deadline_passed"
```

### no native randomness
use commit-reveal or oracles:

```ligo
// commit phase
let commit (hash, storage : bytes * storage) : storage =
  {storage with commitment = hash}

// reveal phase
let reveal (value, storage : nat * storage) : storage =
  let hash = Crypto.sha256(Bytes.pack(value)) in
  if hash <> storage.commitment then
    failwith "invalid_reveal"
  else
    {storage with random = value}
```

### implicit vs originated accounts
- tz1/tz2/tz3 - implicit accounts (wallets)
- KT1 - originated accounts (contracts)

### entry point names are case-sensitive

```ligo
// these are different
[@entry] let Transfer = ...
[@entry] let transfer = ...
```

## deployment workflow

1. write contract in ligo
2. compile to michelson: `ligo compile contract contract.mligo`
3. test thoroughly on shadownet
4. simulate operations: `octez-client run script ... --trace-stack`
5. originate on shadownet: `octez-client originate contract ...`
6. integration testing
7. security audit
8. deploy to mainnet

## useful commands

### compile contract
```bash
ligo compile contract contract.mligo
```

### compile storage
```bash
ligo compile storage contract.mligo 'initial_storage'
```

### run off-chain test
```bash
ligo run test contract_test.mligo
```

### originate contract
```bash
octez-client originate contract my_contract \
  transferring 0 from alice \
  running contract.tz \
  --init '0' \
  --burn-cap 0.5
```

### call contract
```bash
octez-client transfer 0 from alice to my_contract \
  --entrypoint increment \
  --arg '5'
```

### get storage
```bash
octez-client get contract storage for my_contract
```

## resources

official docs:
- tezos: https://docs.tezos.com
- ligo: https://ligolang.org
- smartpy: https://smartpy.io
- opentezos: https://opentezos.com

explorers:
- tzkt: https://tzkt.io
- better call dev: https://better-call.dev

tools:
- teztnets registry: https://teztnets.com
- faucet: https://faucet.shadownet.teztnets.com

standards:
- fa1.2: https://gitlab.com/tezos/tzip/-/blob/master/proposals/tzip-7/tzip-7.md
- fa2: https://gitlab.com/tezos/tzip/-/blob/master/proposals/tzip-12/tzip-12.md

## when to use this skill

invoke this skill when:
- building tezos smart contracts
- implementing token standards
- optimizing gas usage
- debugging contract issues
- setting up testing infrastructure
- deploying to mainnet/testnet

always prioritize security over development speed.
