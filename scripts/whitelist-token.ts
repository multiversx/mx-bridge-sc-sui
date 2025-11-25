import path from "path";
import fs from "fs";
import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV, CONFIG } from "@/env";
import { sleep, readJSONFile } from "@/mx-bridge-typescript/src/utils";

// --- CONFIGURATION ---
const TOKEN_TYPE = CONFIG.Coin_types.reward;
const MIN_AMOUNT = "1";
const MAX_AMOUNT = "1000000000000000";
const IS_NATIVE = true;
const IS_LOCKED = false;
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
      "Update the TOKEN_TYPE constant at the top of scripts/whitelist-token.ts"
    );
    console.log(
      "You can use CONFIG.Coin_types.reward, CONFIG.Coin_types.deposit_normal, or CONFIG.Coin_types.deposit_boosted"
    );
    process.exit(1);
  }

  console.log(`\nToken Whitelisting Configuration:`);
  console.log(`Package: ${DEPLOYMENT.Package}`);
  console.log(`BridgeSafe: ${DEPLOYMENT.Objects.BridgeSafe}`);
  console.log(`Token Type: ${TOKEN_TYPE}`);
  console.log(`Min Amount: ${MIN_AMOUNT}`);
  console.log(`Max Amount: ${MAX_AMOUNT}`);
  console.log(`Is Native: ${IS_NATIVE}`);
  console.log(`Is Locked: ${IS_LOCKED}`);

  console.log("\nWhitelisting token...");

  await sleep(1000);

  const result = await SUI_CLIENT.whitelistToken(
    TOKEN_TYPE,
    MIN_AMOUNT,
    MAX_AMOUNT,
    IS_NATIVE,
    IS_LOCKED
  );

  await sleep(2000);

  console.log("\nToken whitelisted successfully!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("\nSaving whitelist details...");

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

  targetDeployment.whitelistedTokens[TOKEN_TYPE] = {
    minAmount: MIN_AMOUNT,
    maxAmount: MAX_AMOUNT,
    isNative: IS_NATIVE,
    isLocked: IS_LOCKED,
    initializedSupply:
      targetDeployment.whitelistedTokens[TOKEN_TYPE]?.initializedSupply || "0",
  };

  fs.writeFileSync(filePath, JSON.stringify(allDeployments, null, 2), "utf-8");

  console.log("\nWhitelist details saved to deployment.json");
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}

export { main };
