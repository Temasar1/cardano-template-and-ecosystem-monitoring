use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray.{concat}
use cardano/address.{VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}

pub type AssetClass {
  policy: ByteArray,
  name: ByteArray,
}

pub type CampaignDatum {
  authorized_hospital: ByteArray,
  campaign_active: Bool,
}

pub type CampaignRedeemer {
  ClaimByHospital
}

pub type PatientAuthRedeemer {
  MintAuth { patient_name: ByteArray }
  BurnAuth
}

validator patient_campaign(
  admin_token: AssetClass,
  hospital_auth_policy: ByteArray,
) {
  spend(
    _datum: Option<Data>,
    _redeemer: CampaignRedeemer,
    utxo: OutputReference,
    self: Transaction,
  ) {
    let Transaction { inputs, extra_signatories, .. } = self
    
    expect Some(spent_input) =
      list.find(inputs, fn(input) { input.output_reference == utxo })

    // Find marker UTxO with datum at same address as spent UTxO
    expect Some(marker) =
      list.find(
        inputs,
        fn(input) {
          // Must be at same script address
          input.output.address == spent_input.output.address &&
          // Must have inline datum
          when input.output.datum is {
            InlineDatum(_) -> True
            _ -> False
          }
        },
      )

    // Extract campaign datum
    expect InlineDatum(datum_data) = marker.output.datum
    expect datum: CampaignDatum = datum_data

    // Find hospital wallet with auth token
    expect Some(hospital) =
      list.find(
        inputs,
        fn(input) {
          when input.output.address.payment_credential is {
            VerificationKey(_) -> {
              let tokens =
                assets.tokens(input.output.value, hospital_auth_policy)
              dict.size(tokens) > 0
            }
            _ -> False
          }
        },
      )

    // Check hospital authorization
    let hospital_tokens =
      assets.tokens(hospital.output.value, hospital_auth_policy)
    let authorized =
      list.any(
        dict.keys(hospital_tokens),
        fn(token) { token == datum.authorized_hospital },
      )

    // Check hospital signature
    let hospital_cred =
      when hospital.output.address.payment_credential is {
        VerificationKey(cred) -> cred
        _ -> #""
      }
    let signed = list.has(extra_signatories, hospital_cred)

    // All checks must pass
    datum.campaign_active && authorized && signed
  }

  mint(redeemer: PatientAuthRedeemer, auth_policy: PolicyId, self: Transaction) {
    let Transaction { inputs, mint, .. } = self

    // Extract all tokens being minted/burned from this policy
    let minted_tokens =
      mint
        |> tokens(auth_policy)
        |> dict.to_pairs()

    when redeemer is {
      MintAuth { patient_name } -> {
        // Construct token name: {patient_name}PATIENT
        let expected_token_name = concat(concat(patient_name, "PATIENT"), "")

        // CHECK 1: Exactly one token with correct name is being minted
        let must_mint_one_token = {
          expect [Pair(token_name, amount)] = minted_tokens
          token_name == expected_token_name && amount == 1
        }

        // CHECK 2: Admin token must be present in inputs
        let must_have_admin_token = {
          expect Some(admin_input) =
            list.find(
              inputs,
              fn(input) {
                quantity_of(
                  input.output.value,
                  admin_token.policy,
                  admin_token.name,
                ) > 0
              },
            )

          // Admin token must be in a wallet (not a script)
          when admin_input.output.address.payment_credential is {
            VerificationKey(_) -> True
            _ -> False
          }
        }

        and {
          must_mint_one_token?,
          must_have_admin_token?,
        }
      }

      BurnAuth ->
        // Anyone can burn authentication tokens
        // Check that all minted amounts are negative (burning)
        list.all(
          minted_tokens,
          fn(pair) {
            let Pair(_token_name, amount) = pair
            amount < 0
          },
        )
    }
  }

  else(_) {
    fail
  }
}