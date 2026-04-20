import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV } from "@/env";
import { sleep } from "@/mx-bridge-typescript/src/utils";

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

  console.log(`\nUnpause Bridge Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`Bridge: ${DEPLOYMENT.Objects.Bridge}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);

  console.log("\nUnpausing bridge...");

  await sleep(1000);

  const result = await SUI_CLIENT.unpauseBridge();

  await sleep(2000);

  console.log("\nBridge unpaused successfully!");
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
