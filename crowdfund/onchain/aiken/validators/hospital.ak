use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray.{concat}
use cardano/address.{VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Transaction}

// Admin token that controls hospital authentication minting
pub type AssetClass {
  policy: ByteArray,
  name: ByteArray,
}

// Redeemer for minting hospital authentication tokens
pub type HospitalAuthRedeemer {
  MintAuth { hospital_name: ByteArray }
  BurnAuth
}

validator hospital_auth(admin_token: AssetClass) {
  mint(
    redeemer: HospitalAuthRedeemer,
    auth_policy: PolicyId,
    self: Transaction,
  ) {
    let Transaction { inputs, mint, .. } = self

    // Extract all tokens being minted/burned from this policy
    let minted_tokens =
      mint
        |> tokens(auth_policy)
        |> dict.to_pairs()

    when redeemer is {
      MintAuth { hospital_name } -> {
        // Construct token name: HOSPITAL_AUTH_{hospital_name}
        let expected_token_name =
          concat(
            concat(hospital_name, "HOSPITAL"),
            "",
          )

        // Check that exactly one token with correct name is being minted
        let must_mint_one_token = {
          expect [Pair(token_name, amount)] = minted_tokens
          token_name == expected_token_name && amount == 1
        }

        // Check that admin token is present in inputs
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

      BurnAuth -> {
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
  }

  else(_) {
    fail
  }
}