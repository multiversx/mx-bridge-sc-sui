import dotenv from "dotenv";
import path from "path";
import fs from "fs";

import {
  readJSONFile,
  writeJSONFile,
} from "./mx-bridge-typescript/src/utils/json";
import {
  getKeyPairFromPvtKey,
  getKeyPairFromSeed,
} from "./mx-bridge-typescript/src/utils/keypair";
import type {
  BridgeDeploymentInfo,
  WalletScheme,
} from "./mx-bridge-typescript/src/clients/sui/types";
import { createClient } from "./mx-bridge-typescript/src/clients/sui/factory";
import { BridgeClient } from "./mx-bridge-typescript/src/clients/sui/BridgeClient";

dotenv.config({ path: path.join(__dirname, ".env") });

export const ENV = {
  DEPLOY_ON: process.env.DEPLOY_ON,
  DEPLOYER_KEY: process.env.DEPLOYER_KEY || "0x",
  DEPLOYER_PHRASE: process.env.DEPLOYER_PHRASE || "0x",
  WALLET_SCHEME: (process.env.WALLET_SCHEME || "ED25519") as WalletScheme,
  DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || "active",
};

console.log(`ENVIVORMENT: ${ENV.DEPLOY_ON}`);

export const CONFIG = readJSONFile(path.join(__dirname, "config.json"))[
  ENV.DEPLOY_ON
];

const deploymentPath = path.join(__dirname, "deployment.json");
if (!fs.existsSync(deploymentPath)) {
  const emptyDeployment = {
    testnet: { deployments: [] },
    mainnet: { deployments: [] },
    devnet: { deployments: [] },
  };
  writeJSONFile(emptyDeployment, deploymentPath);
  console.log("Created empty deployment.json file");
}

let deploymentData: any = {};
try {
  const allDeployments = readJSONFile(deploymentPath);
  const networkData = allDeployments[ENV.DEPLOY_ON] || { deployments: [] };
  const deployments = networkData.deployments || [];

  if (deployments.length === 0) {
    console.warn(`No deployments found for ${ENV.DEPLOY_ON}`);
  } else {
    let selectedDeployment = null;

    // Try to find the requested deployment
    if (ENV.DEPLOYMENT_ID === "active") {
      selectedDeployment = deployments.find((d: any) => d.active === true);
      if (!selectedDeployment) {
        console.warn(
          `No active deployment set for ${ENV.DEPLOY_ON}. Use 'mark-active' script to set one.`
        );
      }
    } else {
      const deploymentId = parseInt(ENV.DEPLOYMENT_ID, 10);
      selectedDeployment = deployments.find((d: any) => d.id === deploymentId);
      if (!selectedDeployment) {
        console.warn(
          `Deployment #${deploymentId} not found on ${ENV.DEPLOY_ON}`
        );
      }
    }

    // Fallback to active deployment if requested one not found
    if (!selectedDeployment) {
      selectedDeployment = deployments.find((d: any) => d.active === true);
      if (selectedDeployment) {
        console.log(
          `Falling back to active deployment: #${selectedDeployment.id}`
        );
      } else {
        console.error("No active deployment available.");
        console.log("Available deployments:");
        deployments.forEach((d: any) => {
          const activeMarker = d.active ? " [ACTIVE]" : "";
          console.log(`  - #${d.id} (${d.createdAt})${activeMarker}`);
        });
        throw new Error("No usable deployment found");
      }
    } else {
      console.log(
        `Using deployment: #${selectedDeployment.id} (created: ${selectedDeployment.createdAt})`
      );
    }

    deploymentData = selectedDeployment;
  }
} catch (error) {
  console.warn("Error loading deployment.json:", error);
}

export const ADMIN =
  ENV.DEPLOYER_KEY != "0x"
    ? getKeyPairFromPvtKey(ENV.DEPLOYER_KEY, ENV.WALLET_SCHEME)
    : getKeyPairFromSeed(ENV.DEPLOYER_PHRASE, ENV.WALLET_SCHEME);

export const DEPLOYMENT = deploymentData as BridgeDeploymentInfo;

const deploymentForClient: BridgeDeploymentInfo = DEPLOYMENT?.Package
  ? DEPLOYMENT
  : ({
      type: "bridge",
      Package: "",
      Objects: {},
    } as BridgeDeploymentInfo);

export const SUI_CLIENT = createClient(
  CONFIG.rpc,
  deploymentForClient,
  ADMIN
) as BridgeClient;
