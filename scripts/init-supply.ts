import path from "path";
import { SUI_CLIENT, DEPLOYMENT, ENV, CONFIG, ADMIN } from "@/env";
import {
  sleep,
  readJSONFile,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

// --- PARAMS ---
const TOKEN_TYPE = CONFIG.Coin_types.reward;
const COIN_AMOUNT = "15000000";
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

  if (!TOKEN_TYPE) {
    console.error("Error: TOKEN_TYPE not configured");
    console.log(
      "Update the TOKEN_TYPE constant at the top of scripts/init-supply.ts"
    );
    process.exit(1);
  }

  if (!COIN_AMOUNT) {
    console.error("Error: COIN_AMOUNT not configured");
    console.log(
      "Update the COIN_AMOUNT constant at the top of scripts/init-supply.ts"
    );
    process.exit(1);
  }

  console.log(`\nToken Supply Initialization Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);
  console.log(`Token Type: ${TOKEN_TYPE}`);
  console.log(`Coin Amount: ${COIN_AMOUNT}`);

  console.log("\nInitializing token supply...");

  await sleep(1000);

  const result = await SUI_CLIENT.initSupply(
    TOKEN_TYPE,
    COIN_AMOUNT,
    deployerAddress
  );

  await sleep(2000);

  console.log("\nToken supply initialized successfully!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("\nUpdating token supply details...");

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  if (!allDeployments[ENV.DEPLOY_ON]?.deployments) {
    console.error("No deployments found to update");
    process.exit(1);
  }

  const targetDeployment = allDeployments[ENV.DEPLOY_ON].deployments.find(
    (d: any) => d.id === DEPLOYMENT.id
  );

  if (!targetDeployment) {
    console.error(`Deployment #${DEPLOYMENT.id} not found in deployment.json`);
    process.exit(1);
  }

  if (!targetDeployment.whitelistedTokens) {
    targetDeployment.whitelistedTokens = {};
  }

  if (!targetDeployment.whitelistedTokens[TOKEN_TYPE]) {
    console.error(`\nError: Token ${TOKEN_TYPE} is not whitelisted yet.`);
    console.log("You must whitelist the token before initializing supply.");
    console.log("\nTo whitelist: npx tsx scripts/whitelist-token.ts");
    process.exit(1);
  }

  const currentSupply = BigInt(
    targetDeployment.whitelistedTokens[TOKEN_TYPE].initializedSupply || "0"
  );
  const newSupply = currentSupply + BigInt(COIN_AMOUNT);

  targetDeployment.whitelistedTokens[TOKEN_TYPE].initializedSupply =
    newSupply.toString();

  writeJSONFile(allDeployments, filePath);

  console.log(
    `\nToken supply updated: ${COIN_AMOUNT} added (total: ${newSupply.toString()})`
  );
  console.log("Supply details saved to deployment.json");
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}

export { main };
