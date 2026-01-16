import { BlockfrostProvider, MeshWallet } from "@meshsdk/core";
import "dotenv/config";

const seed_phrase = process.env.SEED_PHRASE?.split(" ");
if (!seed_phrase) {
  throw new Error("SEED_PHRASE is not set in .env file");
}
const blockfrost_project_id = process.env.BLOCKFROST_PROJECT_ID;
if (!blockfrost_project_id) {
  throw new Error("BLOCKFROST_PROJECT_ID is not set in .env file");
}
export const provider = new BlockfrostProvider(blockfrost_project_id);
export const wallet = new MeshWallet({
  networkId: 0,
  fetcher: provider,
  submitter: provider,
  key: {
    words: seed_phrase,
    type: "mnemonic",
  },
});

