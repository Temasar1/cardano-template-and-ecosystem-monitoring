import { BlockfrostProvider, MeshWallet } from "@meshsdk/core";
import "dotenv/config";
import { medicalCrowdfundingContract } from "./offchain";

// Setup provider and wallet
const seed_phrase = process.env.SEED_PHRASE?.split(" ");
if (!seed_phrase) {
  throw new Error("SEED_PHRASE is not set in .env file");
}
const blockfrost_project_id = process.env.BLOCKFROST_PROJECT_ID;
if (!blockfrost_project_id) {
  throw new Error("BLOCKFROST_PROJECT_ID is not set in .env file");
}

const provider = new BlockfrostProvider(blockfrost_project_id);
const wallet = new MeshWallet({
  networkId: 0, // 0 for testnet, 1 for mainnet
  fetcher: provider,
  submitter: provider,
  key: {
    words: seed_phrase,
    type: "mnemonic",
  },
});

const admin_token = { policy: "a8d770ae253e4818feb0a5f55dc29d85d86061feee7cc31347276322", name: "aidPod-admin" };
// Initialize the contract
const contract = new medicalCrowdfundingContract({
  admin_token: admin_token,
  network: 0, // 0 for testnet, 1 for mainnet
  wallet: wallet,
  fetcher: provider,
  submitter: provider,
  evaluator: provider,
});

// Test functions
async function testRegisterHospital() {
  console.log("\n=== Testing registerHospital ===");
  try {
    const result = await contract.registerHospital("TestHospital");
    console.log("Hospital registration successful!");
    console.log("transaction hash:", result.txHash);
  } catch (error) {
    console.error("Error registering hospital:", error);
  }
}   

async function testRegisterPatient() {
  console.log("\n=== Testing registerPatient ===");
  try {
    const result = await contract.registerPatient("TestPatient", wallet);
    console.log("Patient registration successful!");
    console.log("Transaction hash:", result.txHash);
  } catch (error) {
    console.error("Error registering patient:", error);
  }
}

async function testCreateCampaign() {
  console.log("\n=== Testing createCampaign ===");
  try {
    const result = await contract.createCampaign("TestHospital", "1500000");
    console.log("Campaign created successfully!");
    console.log("Transaction hash:", result.txHash);
    console.log("Campaign address:", result.campaignAddress);
    console.log("Authorized hospital:", result.authorizedHospital);
  } catch (error) {
    console.error("Error creating campaign:", error);
  }
}

async function testDonateToCampaign() {
  console.log("\n=== Testing donateToCampaign ===");
  try {
    const result = await contract.donateToCampaign("15000000"); // 1 ADA
    console.log("Donation successful!");
    console.log("Transaction hash:", result.txHash);
    console.log("Donation amount:", result.donationAmount);
  } catch (error) {
    console.error("Error donating to campaign:", error);
  }
}

async function testClaimCampaignFunds() {
  console.log("\n=== Testing claimCampaignFunds ===");
  try {
    // Replace with actual campaign transaction hash
    const campaignTxHash = "734c24521c593fa02e79d633a3afb6209fdb8fef4b9862eb09181382e98f5423";
    const result = await contract.claimCampaignFunds(campaignTxHash, "TestHospital");
    console.log("Funds claimed successfully!");
    console.log("Transaction hash:", result);
  } catch (error) {
    console.error("Error claiming funds:", error);
  }
}

async function testBurnHospitalToken() {
  console.log("\n=== Testing burnHospitalToken ===");
  try {
    const result = await contract.burnHospitalToken("TestHospital");
    console.log("Hospital token burned successfully!");
    console.log("Transaction hash:", result);
  } catch (error) {
    console.error("Error burning hospital token:", error);
  }
}

async function testBurnPatientToken() {
  console.log("\n=== Testing burnPatientToken ===");
  try {
    const result = await contract.burnPatientToken("TestPatient");
    console.log("Patient token burned successfully!");
    console.log("Transaction hash:", result);
  } catch (error) {
    console.error("Error burning patient token:", error);
  }
}

// Run tests
async function runTests() {
  console.log("Starting medical crowdfunding contract tests...\n");

  // Uncomment the tests you want to run
  //await testRegisterHospital();
  //await testRegisterPatient();
  // await testCreateCampaign();
  //await testDonateToCampaign();
  //await testClaimCampaignFunds();
  // await testBurnHospitalToken();
   //await testBurnPatientToken();

  console.log("\nTests completed!");
}

// Execute tests
runTests().catch(console.error);
