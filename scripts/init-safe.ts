import path from "path";
import { DEPLOYMENT, ENV, CONFIG, SUI_CLIENT } from "@/env";
import {
  sleep,
  getCreatedObjectsIDs,
  readJSONFile,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

async function main() {
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

  if (!CONFIG.Capabilities.fromCoinCap) {
    console.error("Error: FromCoinCap not found in deployment");
    console.log(
      "Make sure FromCoinCap object exists in your deployment Objects."
    );
    process.exit(1);
  }

  const fromCoinCap = CONFIG.Capabilities.fromCoinCap;

  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`FromCoinCap: ${fromCoinCap}`);

  console.log("Initializing safe...");

  const result = await SUI_CLIENT.initializeSafe(fromCoinCap);
  await sleep(2000);

  console.log("Safe initialization successful!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("\nSaving safe initialization details...");

  const objects = getCreatedObjectsIDs(result);

  Object.assign(DEPLOYMENT.Objects, objects);

  const deploymentFilePath = path.join(__dirname, "../deployment.json");
  const allDeployments = readJSONFile(deploymentFilePath);

  const deploymentIndex = allDeployments[ENV.DEPLOY_ON].deployments.findIndex(
    (d: any) => d.id === DEPLOYMENT.id
  );

  if (deploymentIndex !== -1) {
    allDeployments[ENV.DEPLOY_ON].deployments[deploymentIndex] = DEPLOYMENT;
    writeJSONFile(allDeployments, deploymentFilePath);
  }

  console.log("\nSafe initialization details saved to deployment.json");
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}

export { main };
