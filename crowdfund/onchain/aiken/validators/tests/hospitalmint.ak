use aiken/collection/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/primitive/bytearray
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{
   Input, Mint, NoDatum, Output, OutputReference, Transaction,
}
use hospital.{AssetClass, HospitalAuthRedeemer}

// ==============================================================================================
// Mock Data
// ==============================================================================================

const admin_policy = #"aabbcc"

const admin_token_name = "ADMIN"

const auth_policy = #"ddeeff"

const hospital_name = "StJohns"

const transaction_id_1 =
  #"0000000000000000000000000000000000000000000000000000000000000001"

const transaction_id_2 =
  #"0000000000000000000000000000000000000000000000000000000000000002"

const admin_credential = #"1111111111111111111111111111111111111111111111111111"

const script_credential =
  #"2222222222222222222222222222222222222222222222222222"

// ==============================================================================================
// MintAuth Tests
// ==============================================================================================

type MintTestOptions {
  hospital_name: ByteArray,
  mint_amount: Int,
  includes_admin_token: Bool,
  admin_in_wallet: Bool,
  mints_correct_token_name: Bool,
  mints_multiple_tokens: Bool,
}

fn default_mint_options() {
  MintTestOptions {
    hospital_name,
    mint_amount: 1,
    includes_admin_token: True,
    admin_in_wallet: True,
    mints_correct_token_name: True,
    mints_multiple_tokens: False,
  }
}

fn mint_auth(options: MintTestOptions) -> Bool {
  let min_ada = from_lovelace(2_000_000)
  let admin_token = AssetClass { policy: admin_policy, name: admin_token_name }
  let redeemer =
    HospitalAuthRedeemer.MintAuth { hospital_name: options.hospital_name }

  // Admin input address
  let admin_address =
    if options.admin_in_wallet {
      Address {
        payment_credential: VerificationKey(admin_credential),
        stake_credential: None,
      }
    } else {
      Address {
        payment_credential: Script(script_credential),
        stake_credential: None,
      }
    }

  // Admin input
  let admin_input = {
    let output =
      Output {
        address: admin_address,
        value: if options.includes_admin_token {
          min_ada
            |> add(admin_policy, admin_token_name, 1)
        } else {
          min_ada
        },
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_1, output_index: 0 }
    Input { output_reference, output }
  }

  // Construct expected token name
  let expected_token_name =
    bytearray.concat(bytearray.concat(options.hospital_name, "HOSPITAL"), "")

  // Mint value
  let mint_value =
    if options.mints_multiple_tokens {
      from_asset(auth_policy, expected_token_name, options.mint_amount)
        |> add(auth_policy, "EXTRA_TOKEN", 1)
    } else if options.mints_correct_token_name {
      from_asset(auth_policy, expected_token_name, options.mint_amount)
    } else {
      from_asset(auth_policy, "WRONG_TOKEN", options.mint_amount)
    }

  // Receiver output
  let receiver_output =
    Output {
      address: admin_address,
      value: min_ada
        |> add(auth_policy, expected_token_name, options.mint_amount),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      inputs: [admin_input],
      reference_inputs: [],
      outputs: [receiver_output],
      fee: 5_000,
      mint: mint_value,
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound { bound_type: Finite(0), is_inclusive: True },
        upper_bound: IntervalBound {
          bound_type: Finite(100_000),
          is_inclusive: True,
        },
      },
      extra_signatories: [],
      redeemers: [
        Pair(
          Mint(auth_policy),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
      ],
      datums: dict.empty,
      id: transaction_id_2,
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  hospital.hospital_auth.mint(admin_token, redeemer, auth_policy, tx)
}

test mint_auth_ok() {
  mint_auth(default_mint_options())
}

test mint_with_different_hospital_name() {
  mint_auth(MintTestOptions { ..default_mint_options(), hospital_name: "Mayo" })
}

test mint_without_admin_token() fail {
  mint_auth(
    MintTestOptions { ..default_mint_options(), includes_admin_token: False },
  )
}

test mint_with_admin_in_script() fail {
  mint_auth(
    MintTestOptions { ..default_mint_options(), admin_in_wallet: False },
  )
}

test mint_wrong_token_name() fail {
  mint_auth(
    MintTestOptions {
      ..default_mint_options(),
      mints_correct_token_name: False,
    },
  )
}

test mint_multiple_tokens() fail {
  mint_auth(
    MintTestOptions { ..default_mint_options(), mints_multiple_tokens: True },
  )
}

test mint_zero_amount() fail {
  mint_auth(MintTestOptions { ..default_mint_options(), mint_amount: 0 })
}

test mint_negative_amount() fail {
  mint_auth(MintTestOptions { ..default_mint_options(), mint_amount: -1 })
}

test mint_two_tokens() fail {
  mint_auth(MintTestOptions { ..default_mint_options(), mint_amount: 2 })
}

// ==============================================================================================
// BurnAuth Tests
// ==============================================================================================

type BurnTestOptions {
  burn_amount: Int,
  burns_multiple_tokens: Bool,
  includes_positive_amount: Bool,
}

fn default_burn_options() {
  BurnTestOptions {
    burn_amount: -1,
    burns_multiple_tokens: False,
    includes_positive_amount: False,
  }
}

fn burn_auth(options: BurnTestOptions) -> Bool {
  let min_ada = from_lovelace(2_000_000)
  let admin_token = AssetClass { policy: admin_policy, name: admin_token_name }
  let redeemer = HospitalAuthRedeemer.BurnAuth

  let user_address =
    Address {
      payment_credential: VerificationKey(admin_credential),
      stake_credential: None,
    }

  // User input with tokens to burn
  let user_input = {
    let output =
      Output {
        address: user_address,
        value: min_ada
          |> add(
              auth_policy,
              bytearray.concat(bytearray.concat(hospital_name, "HOSPITAL"), ""),
              1,
            ),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_1, output_index: 0 }
    Input { output_reference, output }
  }

  // Burn value
  let token_name =
    bytearray.concat(bytearray.concat(hospital_name, "HOSPITAL"), "")
  let burn_value =
    if options.burns_multiple_tokens {
      from_asset(auth_policy, token_name, options.burn_amount)
        |> add(auth_policy, "ANOTHER_TOKEN", -1)
    } else if options.includes_positive_amount {
      from_asset(auth_policy, token_name, 1)
    } else {
      from_asset(auth_policy, token_name, options.burn_amount)
    }

  let tx =
    Transaction {
      inputs: [user_input],
      reference_inputs: [],
      outputs: [],
      fee: 5_000,
      mint: burn_value,
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound { bound_type: Finite(0), is_inclusive: True },
        upper_bound: IntervalBound {
          bound_type: Finite(100_000),
          is_inclusive: True,
        },
      },
      extra_signatories: [],
      redeemers: [
        Pair(
          Mint(auth_policy),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
      ],
      datums: dict.empty,
      id: transaction_id_2,
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  hospital.hospital_auth.mint(admin_token, redeemer, auth_policy, tx)
}

test burn_auth_ok() {
  burn_auth(default_burn_options())
}

test burn_multiple_tokens() {
  burn_auth(
    BurnTestOptions { ..default_burn_options(), burns_multiple_tokens: True },
  )
}

test burn_many_tokens() {
  burn_auth(BurnTestOptions { ..default_burn_options(), burn_amount: -5 })
}

test burn_with_positive_amount() fail {
  burn_auth(
    BurnTestOptions { ..default_burn_options(), includes_positive_amount: True },
  )
}
