import path from "path";
import { ADMIN, DEPLOYMENT, ENV, SUI_CLIENT } from "@/env";
import {
  sleep,
  getCreatedObjectsIDs,
  readJSONFile,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

// --- PARAMS ---
const RELAYER_PUBLIC_KEYS = [
  "0x30815d22b6d19ecc6df7f3f87ee9671177fdbf2dafbd79728baf5b75f6fe6f0e",
  "0xdd3105f3a5688568409413d86449b2a8ad0e1021d52846f6eef84f0e07e6d282",
  "0x4522dc62ca8996891787bfbba5222673a33da8f53876742cfa376e3b8ec34b6b",
  "0x23a37497010da8bf45ae139d00f06548ef42256b1bae0480f1c6f97ac9019a90",
  "0xedc03209ddb03f93b7c96a6ce5e0d322de4626d75f01507e02a862d13068b982",
];
const QUORUM = 3;
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

  if (RELAYER_PUBLIC_KEYS.length === 0) {
    console.error("Error: No relayer public keys provided");
    console.log(
      "Update the RELAYER_PUBLIC_KEYS array at the top of scripts/init-bridge.ts"
    );
    process.exit(1);
  }

  if (QUORUM < 3) {
    console.error("Error: Quorum must be at least 3");
    process.exit(1);
  }

  if (QUORUM > RELAYER_PUBLIC_KEYS.length) {
    console.error(
      `Error: Quorum (${QUORUM}) cannot be greater than number of relayers (${RELAYER_PUBLIC_KEYS.length})`
    );
    process.exit(1);
  }

  console.log(`\nBridge Initialization Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);
  console.log(`BridgeCap: ${DEPLOYMENT.Objects.BridgeCap}`);
  console.log(`Number of relayers: ${RELAYER_PUBLIC_KEYS.length}`);
  console.log(`Quorum: ${QUORUM}`);
  console.log(`\nRelayer Public Keys:`);
  RELAYER_PUBLIC_KEYS.forEach((pk: string, i: number) => {
    console.log(`  ${i + 1}. ${pk}`);
  });

  console.log("\nInitializing bridge...");

  const publicKeysBytes = RELAYER_PUBLIC_KEYS.map((pk: string) => {
    const cleanPk = pk.startsWith("0x") ? pk.slice(2) : pk;
    return Array.from(Buffer.from(cleanPk, "hex"));
  });

  const result = await SUI_CLIENT.initializeBridge(
    publicKeysBytes,
    String(QUORUM),
    DEPLOYMENT.Objects.BridgeSafe,
    DEPLOYMENT.Objects.BridgeCap
  );

  await sleep(2000);

  console.log("\nBridge initialization successful!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("\nSaving bridge initialization details...");

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

  console.log("\nBridge initialization details saved to deployment.json");
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}

export { main };
