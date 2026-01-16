use aiken/collection/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{add, from_lovelace, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
}
use patients.{AssetClass, CampaignDatum, ClaimByHospital}

// ==============================================================================================
// Mock Data
// ==============================================================================================

const admin_policy = #"aabbcc"

const admin_token_name = "ADMIN"

const hospital_auth_policy = #"ddeeff"

const hospital_token_name = "StJohnsHOSPITAL"

const transaction_id_1 = #"0000000000000000000000000000000000000000000000000000000000000001"

const transaction_id_2 = #"0000000000000000000000000000000000000000000000000000000000000002"

const transaction_id_3 = #"0000000000000000000000000000000000000000000000000000000000000003"

const hospital_credential = #"1111111111111111111111111111111111111111111111111111"

const patient_script_credential = #"2222222222222222222222222222222222222222222222222222"

// ==============================================================================================
// Spend Validator Tests
// ==============================================================================================

type SpendTestOptions {
  campaign_active: Bool,
  has_hospital_token: Bool,
  hospital_token_matches: Bool,
  hospital_signs: Bool,
  includes_marker: Bool,
  hospital_in_wallet: Bool,
  marker_same_address: Bool,
}

fn default_spend_options() {
  SpendTestOptions {
    campaign_active: True,
    has_hospital_token: True,
    hospital_token_matches: True,
    hospital_signs: True,
    includes_marker: True,
    hospital_in_wallet: True,
    marker_same_address: True,
  }
}

fn test_spend(options: SpendTestOptions) -> Bool {
  let min_ada = from_lovelace(2_000_000)
  let admin_token = AssetClass { policy: admin_policy, name: admin_token_name }
  let redeemer = ClaimByHospital

  let campaign_script_address =
    Address {
      payment_credential: Script(patient_script_credential),
      stake_credential: None,
    }

  let different_script_address =
    Address {
      payment_credential: Script(#"9999999999999999999999999999999999999999999999999999"),
      stake_credential: None,
    }

  let hospital_address =
    if options.hospital_in_wallet {
      Address {
        payment_credential: VerificationKey(hospital_credential),
        stake_credential: None,
      }
    } else {
      Address {
        payment_credential: Script(hospital_credential),
        stake_credential: None,
      }
    }

  // Campaign marker UTxO with datum
  let marker_datum =
    CampaignDatum {
      authorized_hospital: hospital_token_name,
      campaign_active: options.campaign_active,
    }

  let marker_input = {
    let output =
      Output {
        address: if options.marker_same_address {
          campaign_script_address
        } else {
          different_script_address
        },
        value: min_ada,
        datum: InlineDatum(marker_datum),
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_1, output_index: 0 }
    Input { output_reference, output }
  }

  // Donation UTxO being spent (no datum)
  let donation_input = {
    let output =
      Output {
        address: campaign_script_address,
        value: from_lovelace(1_000_000_000),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_2, output_index: 0 }
    Input { output_reference, output }
  }

  // Hospital wallet input with auth token
  let hospital_input = {
    let output =
      Output {
        address: hospital_address,
        value: if options.has_hospital_token {
          if options.hospital_token_matches {
            min_ada
              |> add(hospital_auth_policy, hospital_token_name, 1)
          } else {
            min_ada
              |> add(hospital_auth_policy, "WrongTokenName", 1)
          }
        } else {
          min_ada
        },
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_3, output_index: 0 }
    Input { output_reference, output }
  }

  // Hospital receives claimed funds
  let hospital_output =
    Output {
      address: hospital_address,
      value: from_lovelace(1_000_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      inputs: if options.includes_marker {
        [marker_input, donation_input, hospital_input]
      } else {
        [donation_input, hospital_input]
      },
      reference_inputs: [],
      outputs: [hospital_output],
      fee: 5_000,
      mint: zero,
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(0),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(100_000),
          is_inclusive: True,
        },
      },
      extra_signatories: if options.hospital_signs {
        [hospital_credential]
      } else {
        []
      },
      redeemers: [
        Pair(
          Spend(donation_input.output_reference),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
      ],
      datums: dict.empty,
      id: transaction_id_3,
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  patients.patient_campaign.spend(
    admin_token,
    hospital_auth_policy,
    None,
    redeemer,
    donation_input.output_reference,
    tx,
  )
}

// ==============================================================================================
// Success Tests
// ==============================================================================================

test spend_claim_ok() {
  test_spend(default_spend_options())
}

// ==============================================================================================
// Failure Tests - Campaign State
// ==============================================================================================

test spend_inactive_campaign() fail {
  test_spend(
    SpendTestOptions { ..default_spend_options(), campaign_active: False },
  )
}

// ==============================================================================================
// Failure Tests - Hospital Authorization
// ==============================================================================================

test spend_no_hospital_token() fail {
  test_spend(
    SpendTestOptions { ..default_spend_options(), has_hospital_token: False },
  )
}

test spend_wrong_hospital_token() fail {
  test_spend(
    SpendTestOptions {
      ..default_spend_options(),
      hospital_token_matches: False,
    },
  )
}

test spend_no_hospital_signature() fail {
  test_spend(SpendTestOptions { ..default_spend_options(), hospital_signs: False })
}

test spend_hospital_not_wallet() fail {
  test_spend(
    SpendTestOptions { ..default_spend_options(), hospital_in_wallet: False },
  )
}

// ==============================================================================================
// Failure Tests - Marker Requirements
// ==============================================================================================

test spend_no_marker_utxo() fail {
  test_spend(
    SpendTestOptions { ..default_spend_options(), includes_marker: False },
  )
}

test spend_marker_different_address() fail {
  test_spend(
    SpendTestOptions { ..default_spend_options(), marker_same_address: False },
  )
}

// ==============================================================================================
// Multiple Donation Claims
// ==============================================================================================

fn test_multiple_donations() -> Bool {
  let min_ada = from_lovelace(2_000_000)
  let admin_token = AssetClass { policy: admin_policy, name: admin_token_name }
  let redeemer = ClaimByHospital

  let campaign_script_address =
    Address {
      payment_credential: Script(patient_script_credential),
      stake_credential: None,
    }

  let hospital_address =
    Address {
      payment_credential: VerificationKey(hospital_credential),
      stake_credential: None,
    }

  // Marker with datum
  let marker_datum =
    CampaignDatum {
      authorized_hospital: hospital_token_name,
      campaign_active: True,
    }

  let marker_input = {
    let output =
      Output {
        address: campaign_script_address,
        value: min_ada,
        datum: InlineDatum(marker_datum),
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_1, output_index: 0 }
    Input { output_reference, output }
  }

  // First donation
  let donation_1 = {
    let output =
      Output {
        address: campaign_script_address,
        value: from_lovelace(1_000_000_000),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_2, output_index: 0 }
    Input { output_reference, output }
  }

  // Second donation
  let donation_2 = {
    let output =
      Output {
        address: campaign_script_address,
        value: from_lovelace(500_000_000),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_2, output_index: 1 }
    Input { output_reference, output }
  }

  // Hospital input
  let hospital_input = {
    let output =
      Output {
        address: hospital_address,
        value: min_ada
          |> add(hospital_auth_policy, hospital_token_name, 1),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_3, output_index: 0 }
    Input { output_reference, output }
  }

  // Hospital receives all funds
  let hospital_output =
    Output {
      address: hospital_address,
      value: from_lovelace(1_500_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      inputs: [marker_input, donation_1, donation_2, hospital_input],
      reference_inputs: [],
      outputs: [hospital_output],
      fee: 5_000,
      mint: zero,
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(0),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(100_000),
          is_inclusive: True,
        },
      },
      extra_signatories: [hospital_credential],
      redeemers: [
        Pair(
          Spend(donation_1.output_reference),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
        Pair(
          Spend(donation_2.output_reference),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
      ],
      datums: dict.empty,
      id: transaction_id_3,
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  // Both donations must validate
  let result1 =
    patients.patient_campaign.spend(
      admin_token,
      hospital_auth_policy,
      None,
      redeemer,
      donation_1.output_reference,
      tx,
    )

  let result2 =
    patients.patient_campaign.spend(
      admin_token,
      hospital_auth_policy,
      None,
      redeemer,
      donation_2.output_reference,
      tx,
    )

  result1 && result2
}

test spend_multiple_donations_ok() {
  test_multiple_donations()
}

// ==============================================================================================
// Partial Claims
// ==============================================================================================

fn test_partial_claim() -> Bool {
  let min_ada = from_lovelace(2_000_000)
  let admin_token = AssetClass { policy: admin_policy, name: admin_token_name }
  let redeemer = ClaimByHospital

  let campaign_script_address =
    Address {
      payment_credential: Script(patient_script_credential),
      stake_credential: None,
    }

  let hospital_address =
    Address {
      payment_credential: VerificationKey(hospital_credential),
      stake_credential: None,
    }

  let marker_datum =
    CampaignDatum {
      authorized_hospital: hospital_token_name,
      campaign_active: True,
    }

  let marker_input = {
    let output =
      Output {
        address: campaign_script_address,
        value: min_ada,
        datum: InlineDatum(marker_datum),
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_1, output_index: 0 }
    Input { output_reference, output }
  }

  // Only claiming one donation, leaving others for later
  let donation_1 = {
    let output =
      Output {
        address: campaign_script_address,
        value: from_lovelace(1_000_000_000),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_2, output_index: 0 }
    Input { output_reference, output }
  }

  let hospital_input = {
    let output =
      Output {
        address: hospital_address,
        value: min_ada
          |> add(hospital_auth_policy, hospital_token_name, 1),
        datum: NoDatum,
        reference_script: None,
      }
    let output_reference =
      OutputReference { transaction_id: transaction_id_3, output_index: 0 }
    Input { output_reference, output }
  }

  let hospital_output =
    Output {
      address: hospital_address,
      value: from_lovelace(1_000_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      inputs: [marker_input, donation_1, hospital_input],
      reference_inputs: [],
      outputs: [hospital_output],
      fee: 5_000,
      mint: zero,
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(0),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(100_000),
          is_inclusive: True,
        },
      },
      extra_signatories: [hospital_credential],
      redeemers: [
        Pair(
          Spend(donation_1.output_reference),
          {
            let redeemer_data: Data = redeemer
            redeemer_data
          },
        ),
      ],
      datums: dict.empty,
      id: transaction_id_3,
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  patients.patient_campaign.spend(
    admin_token,
    hospital_auth_policy,
    None,
    redeemer,
    donation_1.output_reference,
    tx,
  )
}

test spend_partial_claim_ok() {
  test_partial_claim()
}