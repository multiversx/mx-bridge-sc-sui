import path from "path";
import fs from "fs";
import { execSync } from "child_process";
import { ADMIN, SUI_CLIENT, ENV, suiClient } from "@/env";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  sleep,
  getCreatedObjectsIDs,
  readJSONFile,
  validateTransactionSuccess,
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

  const tx = new Transaction();
  const [upgradeCap] = tx.publish({ modules, dependencies });

  tx.transferObjects([upgradeCap], tx.pure.address(deployerAddress));

  console.log("Deploying");
  await sleep(3000);

  const result = await suiClient.signAndExecuteTransaction({
    signer: ADMIN as unknown as Ed25519Keypair,
    transaction: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });

  validateTransactionSuccess(result);

  await sleep(3000);

  console.log("Deployment successful!");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("Saving deployment details...");

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
    id: deploymentId,
    createdAt,
    active: false,
    Package: Package || undefined,
    Objects: restObjects,
    Operators: { Admin: deployerAddress },
    digest: result.digest,
  };

  if (!allDeployments[ENV.DEPLOY_ON]) {
    allDeployments[ENV.DEPLOY_ON] = { deployments: [] };
  }
  if (!allDeployments[ENV.DEPLOY_ON].deployments) {
    allDeployments[ENV.DEPLOY_ON].deployments = [];
  }

  allDeployments[ENV.DEPLOY_ON].deployments.push(deploymentData);

  fs.writeFileSync(filePath, JSON.stringify(allDeployments, null, 2), "utf-8"); // TODO

  console.log("Deployment saved to:", filePath);

  console.log(`\nDeployment ID: ${String(deploymentId)}`);
  console.log(`Network: ${ENV.DEPLOY_ON}`);
  console.log(`Created at: ${new Date(createdAt).toLocaleString()}`);
  console.log(`Package: ${Package || "N/A"}`);

  console.log(`\nTo make this deployment active, run the following command:\n`);
  console.log(
    `ENVIRONMENT_ID=${deploymentId} npx tsx scripts/mark-active.ts\n`
  );

  return result;
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
