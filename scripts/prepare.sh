#!/bin/bash

# Ensure script stops on first error
set -e

# Clone repositories if necessary
/app/clone-repos.sh

# Check and build binaries if at least one doesn't exist
if [ ! -f "$BIN_DIR/op-node" ] || [ ! -f "$BIN_DIR/op-batcher" ] || [ ! -f "$BIN_DIR/op-proposer" ] || [ ! -f "$BIN_DIR/geth" ]; then
  # Build op-node, op-batcher and op-proposer
  cd "$OPTIMISM_DIR"
  #pnpm install
  make op-node op-batcher op-proposer
  #pnpm build

  # Copy binaries to the bin volume
  cp -f "$OPTIMISM_DIR"/op-node/bin/op-node "$BIN_DIR"/
  cp -f "$OPTIMISM_DIR"/op-batcher/bin/op-batcher "$BIN_DIR"/
  cp -f "$OPTIMISM_DIR"/op-proposer/bin/op-proposer "$BIN_DIR"/

  # Build op-geth
  cd "$OP_GETH_DIR"
  make geth

  # Copy geth binary to the bin volume
  cp ./build/bin/geth "$BIN_DIR"/
fi

# Create jwt.txt if it does not exist
[ -f "$CONFIG_PATH/jwt.txt" ] || openssl rand -hex 32 > "$CONFIG_PATH"/jwt.txt

# Check if all required config files exist
if [ -f "$CONFIG_PATH/genesis.json" ] && [ -f "$CONFIG_PATH/rollup.json" ]; then
  echo "L2 config files are present, skipping prepare.sh script."
  exec "$@"
  exit 0
elif [ -f "$CONFIG_PATH/genesis.json" ] || [ -f "$CONFIG_PATH/rollup.json" ]; then
  echo "Error: One of the genesis.json or rollup.json files is missing."
  exit 1
fi

# If no L2 config files exist, continue with the script
echo "No required L2 config files are present, continuing script execution."

# Check if all or none of the private keys are provided
if [ -z "$BATCHER_PRIVATE_KEY" ] && [ -z "$PROPOSER_PRIVATE_KEY" ] && [ -z "$SEQUENCER_PRIVATE_KEY" ]; then
  echo "All private keys are missing, fetching from AWS Secrets Manager..."
  secrets=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_ARN" | jq '.SecretString | fromjson')

  BATCHER_PRIVATE_KEY="$(echo "${secrets}" | jq -r '.BATCHER_PRIVATE_KEY')"
  PROPOSER_PRIVATE_KEY="$(echo "${secrets}" | jq -r '.PROPOSER_PRIVATE_KEY')"
  SEQUENCER_PRIVATE_KEY="$(echo "${secrets}" | jq -r '.SEQUENCER_PRIVATE_KEY')"

  export BATCHER_PRIVATE_KEY PROPOSER_PRIVATE_KEY SEQUENCER_PRIVATE_KEY
elif [ -n "$BATCHER_PRIVATE_KEY" ] && [ -n "$PROPOSER_PRIVATE_KEY" ] && [ -n "$SEQUENCER_PRIVATE_KEY" ]; then
  echo "All private keys are provided, continuing..."
else
  echo "Error: Private keys must be all provided or all fetched from AWS Secrets Manager."
  exit 1
fi

# Get L1 chain ID and export it
L1_CHAIN_ID=$(cast chain-id --rpc-url "$L1_RPC_URL")
export L1_CHAIN_ID

# Source the utils.sh file
# shellcheck disable=SC1091
source /app/utils.sh

# Derive addresses from private keys and check for conflicts
derive_and_check "ADMIN_PRIVATE_KEY" "GS_ADMIN_ADDRESS"
derive_and_check "BATCHER_PRIVATE_KEY" "GS_BATCHER_ADDRESS"
derive_and_check "PROPOSER_PRIVATE_KEY" "GS_PROPOSER_ADDRESS"
derive_and_check "SEQUENCER_PRIVATE_KEY" "GS_SEQUENCER_ADDRESS"

#cd "$OPTIMISM_DIR"/packages/contracts-bedrock
cd "$OPTIMISM_DIR"/op-deployer

## Remove old generated internal-opstack-compose.json deploy config
#rm -f ./deploy-config/internal-opstack-compose.json

## Check if deploy-config.json exists
#if [ -f "$CONFIG_PATH/deploy-config.json" ]; then
#  # Populate deploy-config.json with env variables
#  echo "Populating deploy-config.json with env variables..."
#  envsubst < "$CONFIG_PATH"/deploy-config.json > /app/temp-deploy-config.json && mv /app/temp-deploy-config.json ./deploy-config/internal-opstack-compose.json
#else
#  # If deploy-config.json does not exist, use config.sh to generate getting-started.json
#  echo "Generating getting-started.json..."
#
#  ./scripts/getting-started/config.sh
#  mv ./deploy-config/getting-started.json ./deploy-config/internal-opstack-compose.json
#fi

# Fix L1 and L2 Chain ID to the one set in the environment variable
# todo - check what BATCH_INBOX_ADDRESS_TEMP is for
#BATCH_INBOX_ADDRESS_TEMP=$(openssl rand -hex 32 | head -c 40)
#export BATCH_INBOX_ADDRESS_TEMP
#jq \
#  --argjson l1ChainID "$L1_CHAIN_ID" \
#  --argjson l2ChainID "$L2_CHAIN_ID" \
#  --arg batchInboxAddress "0x$BATCH_INBOX_ADDRESS_TEMP" \
#  '.l1ChainID = $l1ChainID | .l2ChainID = $l2ChainID | .batchInboxAddress = $batchInboxAddress' \
#  ./deploy-config/internal-opstack-compose.json > /app/temp-deploy-config.json && mv /app/temp-deploy-config.json ./deploy-config/internal-opstack-compose.json

## Merge deploy override
#if [ -f "$CONFIG_PATH"/deploy-override.json ]; then
#  jq -s '.[0] * .[1]' ./deploy-config/internal-opstack-compose.json "$CONFIG_PATH"/deploy-override.json > /app/temp-deploy-config.json && mv /app/temp-deploy-config.json ./deploy-config/internal-opstack-compose.json
#fi

## Show deployment config for better debuggability
#cat ./deploy-config/internal-opstack-compose.json

export DEPLOYER_WORKDIR=.deployer
export DEPLOYER_INTENT_FILE=$DEPLOYER_WORKDIR/intent.toml
if [ -z $DEPLOYMENT_STRATEGY ]
  export DEPLOYMENT_STRATEGY=live
fi
if [ -z $FUND_DEV_ACCOUNTS ]
  export FUND_DEV_ACCOUNTS=false
fi

# Create amd modify the intent.toml file
if [ -f "$CONFIG_PATH"/intent.toml ]; then
  update_toml_value 'deploymentStrategy' "$DEPLOYMENT_STRATEGY" "$CONFIG_PATH"/intent.toml
  cp "$CONFIG_PATH"/intent.toml "$DEPLOYER_INTENT_FILE"
else
  init --deployment-strategy "$DEPLOYMENT_STRATEGY" --l1-chain-id "$L1_CHAIN_ID" --l2-chain-ids "$L2_CHAIN_ID" --workdir "$DEPLOYER_WORKDIR"
fi

# Modify the default values
update_toml_value 'fundDevAccounts'       "$FUND_DEV_ACCOUNTS"    "$DEPLOYER_INTENT_FILE"
update_toml_value 'proxyAdminOwner'       "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'protocolVersionsOwner' "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE" # todo - verify that this is the correct address
update_toml_value 'guardian'              "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'baseFeeVaultRecipient' "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'l1FeeVaultRecipient'   "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'sequencerFeeVaultRecipient' "$GS_ADMIN_ADDRESS" "$DEPLOYER_INTENT_FILE"
update_toml_value 'l1ProxyAdminOwner'     "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'l2ProxyAdminOwner'     "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"
update_toml_value 'systemConfigOwner'     "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE" # todo - verify that this is the correct address
update_toml_value 'unsafeBlockSigner'     "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE" # todo - verify that this is the correct address
update_toml_value 'batcher'               "$GS_BATCHER_ADDRESS"   "$DEPLOYER_INTENT_FILE"
update_toml_value 'proposer'              "$GS_PROPOSER_ADDRESS"  "$DEPLOYER_INTENT_FILE"
update_toml_value 'challenger'            "$GS_ADMIN_ADDRESS"     "$DEPLOYER_INTENT_FILE"

cat "$DEPLOYER_INTENT_FILE"

# Generate IMPL_SALT
if [ -z "$IMPL_SALT" ]; then
  IMPL_SALT=$(sha256sum ./deploy-config/internal-opstack-compose.json | cut -d ' ' -f1)
  export IMPL_SALT
fi

# NOTE: The $DEPLOYMENT_OUTFILE and $DEPLOY_CONFIG_PATH vars are required for line 136
#export DEPLOYMENT_OUTFILE=./deployments/artifact.json
#export DEPLOY_CONFIG_PATH=./deploy-config/internal-opstack-compose.json # "$CONFIG_PATH"/deploy-config.json not suitable due to the error "... not allowed to be accessed for read operations"

# If not deployed
if [ ! -f "$DEPLOYMENT_DIR"/l1-contracts.json ]; then
  ## Determine the script path (fix for v1.7.7)
  #DEPLOY_SCRIPT_PATH=$(test -f scripts/deploy/Deploy.s.sol && echo "scripts/deploy/Deploy.s.sol" || echo "scripts/Deploy.s.sol")

  ## Deploy the L1 contracts
  #forge script "$DEPLOY_SCRIPT_PATH" --private-key "$DEPLOYER_PRIVATE_KEY" --broadcast --rpc-url "$L1_RPC_URL"

  op-deployer apply --workdir "$DEPLOYER_WORKDIR" --l1-rpc-url "$L1_RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" # deploy contracts

  op-deployer inspect l1 --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID" > "$DEPLOYER_WORKDIR"/l1-contracts.json # outputs all L1 contract addresses for an L2 chain
  #op-deployer inspect deploy-config --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID" # outputs the deploy config for an L2 chain
  #op-deployer inspect l2-semvers --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID" # outputs the semvers for all L2 chains

  # Copy the deployment files to the data volume
  cp "$DEPLOYER_WORKDIR"/l1-contracts.json "$DEPLOYMENT_DIR"/
  #cp $DEPLOY_CONFIG_PATH "$CONFIG_PATH"/deploy-config.json
  cp $DEPLOYER_INTENT_FILE "$CONFIG_PATH"/intent.toml
fi

# Generating L2 Allocs
export CONTRACT_ADDRESSES_PATH=$DEPLOYMENT_DIR/artifact.json
#export STATE_DUMP_PATH=$DEPLOYMENT_DIR/allocs.json

#if [ -f "$STATE_DUMP_PATH" ]; then
#  echo "State dump already exists, skipping state dump generation."
#else
#  forge script scripts/L2Genesis.s.sol:L2Genesis --chain-id "$L2_CHAIN_ID"  --sig 'runWithAllUpgrades()' --private-key "$DEPLOYER_PRIVATE_KEY" # OR runWithStateDump()
#fi

#export DEPLOY_CONFIG_PATH="$CONFIG_PATH"/deploy-config.json
## Generate the L2 genesis files
#cd "$OPTIMISM_DIR"/op-node
#go run cmd/main.go genesis l2 \
#  --deploy-config "$DEPLOY_CONFIG_PATH" \
#  --l1-deployments "$CONTRACT_ADDRESSES_PATH" \
#  --outfile.l2 genesis.json \
#  --outfile.rollup rollup.json \
#  --l1-rpc "$L1_RPC_URL" \
#  --l2-allocs "$STATE_DUMP_PATH"
#cp genesis.json "$CONFIG_PATH"/
#cp rollup.json "$CONFIG_PATH"/

# Generate the L2 genesis files
op-deployer inspect genesis --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID" > "$DEPLOYER_WORKDIR"/genesis.json
op-deployer inspect rollup --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID" > "$DEPLOYER_WORKDIR"/rollup.json
cp "$DEPLOYER_WORKDIR"/genesis.json "$CONFIG_PATH"/
cp "$DEPLOYER_WORKDIR"/rollup.json "$CONFIG_PATH"/

# Reset repository for cleanup
cd "$OPTIMISM_DIR"
git reset HEAD --hard

exec "$@"
