import path from "path";
import { execSync } from "child_process";

import { ADMIN, ENV, SUI_CLIENT } from "@/env";
import {
  sleep,
  getCreatedObjectsIDs,
  readJSONFile,
  newTransactionBlock,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

export async function main() {
  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Deployer: ${deployerAddress}`);

  const pkgPath = path.join(path.resolve(__dirname), "../");

  const { modules, dependencies } = JSON.parse(
    execSync(
      `sui move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${pkgPath}`,
      {
        encoding: "utf-8",
      }
    )
  );

  const tx = newTransactionBlock();
  const [upgradeCap] = tx.publish({ modules, dependencies });

  tx.transferObjects([upgradeCap], tx.pure.address(deployerAddress));

  console.log("Deploying");

  const result = await SUI_CLIENT.sendTransactionReturnResult(tx);
  await sleep(3000);

  console.log("Deployment successful!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("\nSaving deployment details...");

  const objects = getCreatedObjectsIDs(result);

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  const { Package, ...restObjects } = objects;

  const existingDeployments = allDeployments[ENV.DEPLOY_ON]?.deployments || [];
  const deploymentId =
    existingDeployments.length > 0
      ? Math.max(...existingDeployments.map((d: any) => d.id)) + 1
      : 1;
  const createdAt = new Date().toISOString();

  const deploymentData = {
    type: "bridge",
    id: deploymentId,
    active: false,
    digest: result.digest,
    createdAt,
    Package: Package || undefined,
    Objects: restObjects,
    Operators: { Admin: deployerAddress },
  };

  if (!allDeployments[ENV.DEPLOY_ON]) {
    allDeployments[ENV.DEPLOY_ON] = { deployments: [] };
  }
  if (!allDeployments[ENV.DEPLOY_ON].deployments) {
    allDeployments[ENV.DEPLOY_ON].deployments = [];
  }

  allDeployments[ENV.DEPLOY_ON].deployments.push(deploymentData);

  writeJSONFile(allDeployments, filePath);

  console.log("Deployment saved to:", filePath);

  console.log(`\nDeployment ID: ${String(deploymentId)}`);
  console.log(`Network: ${ENV.DEPLOY_ON}`);
  console.log(`Created at: ${new Date(createdAt).toLocaleString()}`);
  console.log(`Package: ${Package || "N/A"}`);

  console.log(`\nTo make this deployment active, run the following command:\n`);
  console.log(`DEPLOYMENT_ID=${deploymentId} npx tsx scripts/mark-active.ts\n`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
