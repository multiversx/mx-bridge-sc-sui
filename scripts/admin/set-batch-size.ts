import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV } from "@/env";
import { sleep } from "@/mx-bridge-typescript/src/utils";

// --- PARAMS ---
const NEW_BATCH_SIZE = 100;
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

  if (!NEW_BATCH_SIZE) {
    console.error("Error: NEW_BATCH_SIZE not configured");
    console.log(
      "Update the NEW_BATCH_SIZE constant at the top of scripts/set-batch-size.ts"
    );
    process.exit(1);
  }

  console.log(`\nSet Batch Size Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);
  console.log(`BridgeCap: ${DEPLOYMENT.Objects.BridgeCap}`);
  console.log(`New Batch Size: ${NEW_BATCH_SIZE}`);

  console.log("\nSetting batch size...");

  await sleep(1000);

  const result = await SUI_CLIENT.setBatchSize(NEW_BATCH_SIZE);

  await sleep(2000);

  console.log("\nBatch size set successfully!");
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
