import path from "path";
import { readJSONFile, writeJSONFile } from "@/mx-bridge-typescript/src/utils";
import { ENV } from "@/env";

/**
 * Mark a specific deployment as active/official for the current network
 * Usage: DEPLOYMENT_ID=2 npx tsx scripts/mark-active.ts
 */
async function main() {
  const deploymentId = parseInt(process.env.DEPLOYMENT_ID || "0", 10);
  const network = ENV.DEPLOY_ON;

  if (!deploymentId) {
    console.error("Error: DEPLOYMENT_ID environment variable is required");
    console.log("\nUsage: DEPLOYMENT_ID=2 npx tsx scripts/mark-active.ts");
    process.exit(1);
  }

  if (!network) {
    console.error("Error: DEPLOY_ON environment variable is required");
    process.exit(1);
  }

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  const networkData = allDeployments[network];
  if (!networkData || !networkData.deployments) {
    console.error(`No deployments found for network: ${network}`);
    process.exit(1);
  }

  const deployments = networkData.deployments;
  const deployment = deployments.find((d: any) => d.id === deploymentId);

  if (!deployment) {
    console.error(`Deployment #${deploymentId} not found on ${network}`);
    console.log("\nAvailable deployments:");
    deployments.forEach((d: any) => {
      const activeMarker = d.active ? " [ACTIVE]" : "";
      console.log(`  - #${d.id} (${d.createdAt})${activeMarker}`);
    });
    process.exit(1);
  }

  deployments.forEach((d: any) => {
    d.active = false;
  });

  deployment.active = true;

  writeJSONFile(allDeployments, filePath);

  console.log("\nACTIVE DEPLOYMENT UPDATED");
  console.log(`Deployment ID: ${deploymentId}`);
  console.log(`Network: ${network}`);
  console.log(`Created: ${new Date(deployment.createdAt).toLocaleString()}`);
  console.log(`Package: ${deployment.Package || "N/A"}\n`);
  console.log(
    `\nThis deployment is now marked as the official/active deployment for ${network}.`
  );
  console.log(
    `Scripts using DEPLOYMENT_ID=active will now use this deployment.\n`
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
