# Medical Crowdfunding Smart Contract

A decentralized medical crowdfunding platform built on Cardano that allows patients to create fundraising campaigns and claim funds using authentication tokens.

## Overview

This project implements a medical crowdfunding system with two main components:
- **Hospital Authentication**: Hospitals must first receive authentication tokens from organisation or admin after register
- **Patient Authentucation**: Patients receive admin tokens from hospital give them access to create campaign in platform
- **Campaign Management**: Hospitals can create campaigns, receive donations, and claim funds

## How It Works

### Core Flow

1. **Registration Phase**
   - Admin mints hospital authentication tokens (e.g., "HospitalNameHOSPITAL")
   - Admin mints patient authentication tokens (e.g., "PatientNamePATIENT")

2. **Campaign Creation**
   - patients creates a campaign by locking ADA in a smart contract
   - Campaign includes a datum specifying the authorized hospital and active status

3. **Donations**
   - Anyone can donate ADA to an active campaign
   - Donations are locked in the same smart contract address

4. **Fund Claiming**
   - Only the authorized hospital (with valid auth token) can claim funds
   - Hospital must sign the transaction and provide their auth token

### Validator Logic

The validator enforces three key rules:

1. **Hospital Registration**: 
   - Requires admin token in transaction inputs
   - Mints exactly one token with name pattern: `{hospital_name}HOSPITAL`
   - Admin token must be in a wallet (not script)

2. **Patient Registration**:
   - Requires admin token in transaction inputs
   - Mints exactly one token with name pattern: `{patient_name}PATIENT`
   - Admin token must be in a wallet (not script)

3. **Campaign Spending**:
   - Campaign must be active (datum check)
   - Hospital must have matching auth token
   - Hospital must sign the transaction
   - Both marker UTxO and donation UTxO are spent together

## Onchain Stack

### Technology
- **Language**: Aiken
- **Plutus Version**: V3
- **Validators**: 2 main validators

### Validators

#### 1. Hospital Auth Validator (`hospital.ak`)
- **Purpose**: Controls minting/burning of hospital authentication tokens
- **Functions**:
  - `mint`: Mints hospital tokens when admin token is present
  - `burn`: Allows anyone to burn their own tokens

#### 2. Patient Campaign Validator (`patients.ak`)
- **Purpose**: Manages campaign funds and patient token minting
- **Functions**:
  - `spend`: Validates fund claiming by authorized hospitals
  - `mint`: Mints patient authentication tokens
  - `burn`: Allows burning of patient tokens

### Project Structure
```
onchain/aiken/
├── validators/
│   ├── hospital.ak          # Hospital authentication minting policy
│   └── patients.ak          # Campaign spending + patient minting
├── lib/
│   └── utils.ak            # Shared utilities
└── plutus.json             # Compiled validator CBOR
```

### Building Onchain

```bash
cd onchain/aiken
aiken build
```

This generates `plutus.json` with compiled validator code.

## Offchain Stack

### Technology
- **Language**: TypeScript
- **SDK**: Mesh SDK (@meshsdk/core)
- **Provider**: Blockfrost

### Main Class: `medicalCrowdfundingContract`

A single class that provides all transaction building methods:

```typescript
const contract = new medicalCrowdfundingContract({
  admin_token: {policyId: "", name: ""}
  network: 0,              // 0 = testnet, 1 = mainnet
  wallet: wallet,          // IWallet instance
  fetcher: provider,       // IFetcher instance
  submitter: provider,     // ISubmitter instance
  evaluator: provider,     // IEvaluator instance (optional)
});
```

### Available Methods

1. **`registerHospital(hospitalName: string)`**
   - Mints a hospital authentication token
   - Returns unsigned transaction

2. **`registerPatient(patientName: string, wallet: IWallet)`**
   - Mints a patient authentication token
   - Returns transaction hash

3. **`createCampaign(hospitalName: string, initialFunding: string)`**
   - Creates a new campaign with initial funding
   - Returns campaign address and transaction hash

4. **`donateToCampaign(donationAmount: string)`**
   - Donates ADA to an active campaign
   - Returns transaction hash

5. **`claimCampaignFunds(campaignTxHash: string, hospitalName: string)`**
   - Hospital claims funds from campaign
   - Requires hospital auth token and signature
   - Returns transaction hash

6. **`burnHospitalToken(hospitalName: string)`**
   - Burns a hospital authentication token
   - Returns transaction hash

7. **`burnPatientToken(patientName: string)`**
   - Burns a patient authentication token
   - Returns transaction hash

### Project Structure
```
offchain/
├── offchain.ts            # Main contract class
├── index.ts               # Test examples
├── src/lib/
│   ├── config.ts         # Configuration
│   └── utils.ts          # Utilities
└── package.json
```

## Deployment

### Prerequisites

1. **Node.js** (v18+)
2. **Aiken** compiler
3. **Blockfrost API Key** (testnet or mainnet)
4. **Wallet with seed phrase**

### Step 1: Build Onchain Validators

```bash
cd onchain/aiken
aiken build
```

This creates `plutus.json` with compiled validator code.

### Step 2: Setup Offchain Environment

```bash
cd offchain
npm install
```

Create a `.env` file:
```env
SEED_PHRASE="your twelve word seed phrase here"
BLOCKFROST_PROJECT_ID="your_blockfrost_project_id"
```

### Step 3: Initialize Contract

```typescript
import { BlockfrostProvider, MeshWallet } from "@meshsdk/core";
import { medicalCrowdfundingContract } from "./offchain";

// Setup provider
const provider = new BlockfrostProvider(process.env.BLOCKFROST_PROJECT_ID!);

// Setup wallet
const wallet = new MeshWallet({
  networkId: 0, // 0 = testnet, 1 = mainnet
  fetcher: provider,
  submitter: provider,
  evaluator: provider,
  key: {
    words: process.env.SEED_PHRASE!.split(" "),
    type: "mnemonic",
  },
});

// Initialize contract
const contract = new medicalCrowdfundingContract({
  network: 0,
  wallet: wallet,
  fetcher: provider,
  submitter: provider,
  evaluator: provider,
});
```

### Step 4: Deploy Workflow

1. **Register Hospital** (requires admin token)
   ```typescript
   await contract.registerHospital("MyHospital");
   ```

2. **Create Campaign**
   ```typescript
   const result = await contract.createCampaign("MyHospital", "2000000");
   // Save result.campaignAddress for donations
   ```

3. **Donate to Campaign**
   ```typescript
   await contract.donateToCampaign("1000000"); // 1 ADA
   ```

4. **Claim Funds** (by authorized hospital)
   ```typescript
   await contract.claimCampaignFunds(campaignTxHash, "MyHospital");
   ```

### Testing

Run the test suite:

```bash
cd offchain
npm run dev
```

Or edit `index.ts` to uncomment specific tests.

## Configuration

### Admin Token
The system uses an admin token to control registration:
- **Policy ID**: `a8d770ae253e4818feb0a5f55dc29d85d86061feee7cc31347276322`
- **Token Name**: `aidPod-admin` (hex encoded)

You must have this token in your wallet to register hospitals or patients.

### Network
- **Testnet**: `network: 0`
- **Mainnet**: `network: 1`

## Security Considerations

1. **Admin Token**: Keep the admin token secure - it controls all registrations
2. **Hospital Tokens**: Only authorized hospitals can claim funds
3. **Campaign Status**: Only active campaigns can receive donations
4. **Signatures**: Hospital must sign transactions to claim funds

## Project Structure

```
crowdfund/
├── onchain/
│   └── aiken/              # Aiken validators
│       ├── validators/     # Smart contract validators
│       └── plutus.json     # Compiled validators
├── offchain/               # TypeScript SDK
│   ├── offchain.ts         # Main contract class
│   └── index.ts            # Test examples
└── README.md               # This file
```

## Resources

- [Aiken Documentation](https://aiken-lang.org)
- [Mesh SDK Documentation](https://meshjs.dev)
- [Blockfrost API](https://blockfrost.io)
