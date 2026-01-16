💻 Off-Chain API
Setup
typescriptimport { Deploy } from "../deploy";
import { provider, wallet } from "../../lib/utils";
import { admin_token } from "../../lib/config";

Hospital Registration
Register Hospital
typescriptconst result = await registerHospital("StJohns");

// Returns:
{
  txHash: "abc123...",
  policyId: "ddeeff...",
  tokenName: "StJohnsHOSPITAL",
  asset: "ddeeff...StJohnsHOSPITAL"
}
Requirements:

Admin token in wallet
Unique hospital name

Burn Hospital Token
typescriptawait burnHospitalToken("StJohns");

Patient Registration
Register Patient
typescriptconst result = await registerPatient("Emmanuel");

// Returns:
{
  txHash: "abc123...",
  policyId: "ff0011...",
  tokenName: "EmmanuelPATIENT",
  asset: "ff0011...EmmanuelPATIENT"
}
Requirements:

Admin token in wallet
Unique patient name

Burn Patient Token
typescriptawait burnPatientToken("Emmanuel");

Campaign Management
Create Campaign
typescriptconst campaign = await createCampaign(
  "StJohns",    // Hospital authorized to claim
  "5000000"     // Initial funding (5 ADA)
);

// Returns:
{
  txHash: "abc123...",
  campaignAddress: "addr_test1wz...",
  authorizedHospital: "StJohns",
  campaignActive: true,
  initialFunding: "5000000"
}
Campaign Structure:
Campaign Address (Script):
├── Marker UTxO
│   ├── Datum: {authorized_hospital, campaign_active}
│   └── Amount: 2+ ADA
└── Donation UTxOs (created later)
    ├── No datum
    └── Amount: Variable ADA

Donate to Campaign
typescriptawait donateToCampaign(
  campaign.campaignAddress,
  "10000000"  // 10 ADA donation
);
Note: Donations don't require datum - just send ADA to campaign address

Hospital Claims Funds
typescriptconst txHash = await claimCampaignFunds(
  "3592bd0c...",  // Campaign/donation tx hash
  "StJohns"       // Hospital name
);
Transaction Flow:
Inputs:
1. Marker UTxO (regular input)
2. Donation UTxO (script spending)
3. Hospital wallet (has StJohnsHOSPITAL token)

Validation:
✓ Marker at same address
✓ Hospital has auth token
✓ Hospital signs

Output:
→ Funds to hospital wallet

🔄 Complete User Flow
1. Admin Setup
typescript// Register hospitals
await registerHospital("StJohns");
await registerHospital("Mayo");

// Register patients  
await registerPatient("Emmanuel");
await registerPatient("JohnDoe");
2. Patient Creates Campaign
typescript// Patient creates fundraising campaign
const campaign = await createCampaign(
  "StJohns",    // Authorized hospital
  "2000000"     // 2 ADA initial
);

// Campaign address: addr_test1wz...
3. Donors Contribute
typescript// Anyone can donate (no special requirements)
await donateToCampaign(campaign.campaignAddress, "5000000");   // 5 ADA
await donateToCampaign(campaign.campaignAddress, "10000000");  // 10 ADA
await donateToCampaign(campaign.campaignAddress, "3000000");   // 3 ADA

// Total raised: 20 ADA
4. Hospital Claims Funds
typescript// Hospital claims when ready
const txHash = await claimCampaignFunds(
  "donation_tx_hash",  // Specific donation to claim
  "StJohns"
);

// Hospital receives ADA for patient treatment