import path from "path";
import { execSync } from "child_process";
import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV } from "@/env";
import {
  getCreatedObjectsIDs,
  newTransactionBlock,
  readJSONFile,
  sleep,
  UpgradePolicy,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

async function main() {
  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Deployer: ${deployerAddress}`);

  if (!DEPLOYMENT.Objects?.UpgradeCap) {
    console.error("Error: No active deployment found or UpgradeCap missing");
    console.log(
      "Make sure you have deployed the package first and have an active deployment."
    );
    console.log("\nTo deploy: npx tsx scripts/deploy.ts");
    console.log(
      "To set active deployment: DEPLOYMENT_ID=<id> npx tsx scripts/mark-active.ts"
    );
    process.exit(1);
  }

  const pkgPath = path.join(path.resolve(__dirname), "../");

  const { modules, dependencies, digest } = JSON.parse(
    execSync(
      `sui move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${pkgPath}`,
      {
        encoding: "utf-8",
      }
    )
  );

  const tx = newTransactionBlock();
  const cap = tx.object(DEPLOYMENT.Objects.UpgradeCap);

  const ticket = tx.moveCall({
    target: "0x2::package::authorize_upgrade",
    arguments: [
      cap,
      tx.pure.u8(UpgradePolicy.COMPATIBLE),
      tx.pure.vector("u8", digest),
    ],
  });

  const receipt = tx.upgrade({
    modules,
    dependencies,
    package: DEPLOYMENT.Package,
    ticket,
  });

  tx.moveCall({
    target: "0x2::package::commit_upgrade",
    arguments: [cap, receipt],
  });

  tx.setSender(deployerAddress);

  const result = await SUI_CLIENT.sendTransactionReturnResult(tx);

  await sleep(3000);

  console.log("Upgrade successful!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("Saving upgrade details...");
  await sleep(2000);

  const objects = getCreatedObjectsIDs(result);

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

  const newPackageId = objects.Package;
  if (!newPackageId) {
    console.error("Error: No new package ID found in upgrade result");
    process.exit(1);
  }

  const oldPackageId = targetDeployment.Package;
  targetDeployment.Package = newPackageId;
  targetDeployment.lastUpgrade = {
    previousPackage: oldPackageId,
    upgradedAt: new Date().toISOString(),
    digest: result.digest,
  };

  writeJSONFile(allDeployments, filePath);

  console.log("Upgrade details saved.");

  console.log(`Deployment ID: ${DEPLOYMENT.id}`);
  console.log(`Old Package: ${oldPackageId}`);
  console.log(`New Package: ${newPackageId}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
