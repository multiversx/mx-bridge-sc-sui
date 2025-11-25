import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV } from "@/env";
import { sleep } from "@/mx-bridge-typescript/src/utils";

// --- CONFIGURATION ---
const TIMEOUT_MS = "60000"; // Set your desired timeout in milliseconds (e.g., 60000 = 60 seconds)
// ----------------------

async function main() {
  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Deployer: ${deployerAddress}`);

  if (!DEPLOYMENT.Package) {
    console.error("Error: No active deployment found");
    console.log(
      "Make sure you have deployed the package first and have an active deployment."
    );
    console.log("\nTo deploy: npx tsx scripts/deploy.ts");
    console.log(
      "To set active deployment: DEPLOYMENT_ID=<id> npx tsx scripts/mark-active.ts"
    );
    process.exit(1);
  }

  if (!SUI_CLIENT) {
    console.error("Error: SUI_CLIENT not initialized");
    process.exit(1);
  }

  if (!TIMEOUT_MS) {
    console.error("Error: TIMEOUT_MS not configured");
    console.log(
      "Update the TIMEOUT_MS constant at the top of scripts/set-batch-timeout.ts"
    );
    process.exit(1);
  }

  console.log(`\nSet Batch Timeout Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);
  console.log(`BridgeCap: ${DEPLOYMENT.Objects.BridgeCap}`);
  console.log(`Timeout: ${TIMEOUT_MS} ms`);

  console.log("\nSetting batch timeout...");

  await sleep(1000);

  const result = await SUI_CLIENT.setBatchTimeout(TIMEOUT_MS);

  await sleep(2000);

  console.log("\nBatch timeout set successfully!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}

export { main };
