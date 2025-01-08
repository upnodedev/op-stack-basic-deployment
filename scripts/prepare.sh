#!/bin/bash

# Ensure script stops on first error
set -e

# Clone repositories if necessary
/app/clone-repos.sh

# Check and build binaries if at least one doesn't exist
if [ ! -f "$BIN_DIR/op-node" ] || [ ! -f "$BIN_DIR/op-batcher" ] || [ ! -f "$BIN_DIR/op-proposer" ] || [ ! -f "$BIN_DIR/geth" ]; then
  # Build op-node, op-batcher and op-proposer
  cd "$OPTIMISM_DIR"
  make op-node op-batcher op-proposer

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

# build op-deployer, if not already present
cd "$OPTIMISM_DIR"/op-deployer
if [ ! -f "./bin/op-deployer" ]; then
  just build
fi

#BATCH_INBOX_ADDRESS_TEMP=$(openssl rand -hex 32 | head -c 40)
#export BATCH_INBOX_ADDRESS_TEMP

export DEPLOYER_WORKDIR=.deployer
export DEPLOYER_INTENT_FILE=$DEPLOYER_WORKDIR/intent.toml

# default the deployment strategy to 'live' (the alternative is 'genesis')
if [ -z $DEPLOYMENT_STRATEGY ]; then
  export DEPLOYMENT_STRATEGY=live
fi

if [ -z $FUND_DEV_ACCOUNTS ]; then
  export FUND_DEV_ACCOUNTS=false
fi

# default to 'custom' (alternative values are 'standard' and 'strict')
if [ -z $INTENT_CONFIG_TYPE ]; then
  export INTENT_CONFIG_TYPE=custom
fi

# Create amd modify the intent.toml file
if [ -f "$CONFIG_PATH"/intent.toml ]; then
  #update_toml_value 'deploymentStrategy' "$DEPLOYMENT_STRATEGY" "$CONFIG_PATH"/intent.toml
  #update_toml_value 'configType' "$INTENT_CONFIG_TYPE" "$CONFIG_PATH"/intent.toml
  dasel put -t string -v "$DEPLOYMENT_STRATEGY" -f "$CONFIG_PATH"/intent.toml -r toml '.deploymentStrategy'
  dasel put -t string -v "$INTENT_CONFIG_TYPE" -f "$CONFIG_PATH"/intent.toml -r toml '.configType'
  cp "$CONFIG_PATH"/intent.toml "$DEPLOYER_INTENT_FILE"
else
  ./bin/op-deployer init --intent-config-type "$INTENT_CONFIG_TYPE" --deployment-strategy "$DEPLOYMENT_STRATEGY" --l1-chain-id "$L1_CHAIN_ID" --l2-chain-ids "$L2_CHAIN_ID" --workdir "$DEPLOYER_WORKDIR"
fi

if [ -z $EIP1559_DENOMINATOR_CANYON ]; then
  export EIP1559_DENOMINATOR_CANYON=false
fi

if [ -z $EIP1559_DENOMINATOR ]; then
  export EIP1559_DENOMINATOR=50
fi

if [ -z $EIP1559_ELASTICITY ]; then
  export EIP1559_ELASTICITY=6
fi

if [ -z $L1_CONTRACTS_LOCATOR ]; then
  export L1_CONTRACTS_LOCATOR=tag://op-contracts/v1.6.0
fi

if [ -z $L2_CONTRACTS_LOCATOR ]; then
  export L2_CONTRACTS_LOCATOR=tag://op-contracts/v1.7.0-beta.1+l2-contracts
fi


# Modify the default values in the intent file
#update_toml_value 'fundDevAccounts'       "$FUND_DEV_ACCOUNTS"        "$DEPLOYER_INTENT_FILE"
#update_toml_value 'proxyAdminOwner'       "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'protocolVersionsOwner' "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'guardian'              "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'baseFeeVaultRecipient' "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'l1FeeVaultRecipient'   "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'sequencerFeeVaultRecipient' "\"$GS_ADMIN_ADDRESS\"" "$DEPLOYER_INTENT_FILE"
#update_toml_value 'l1ProxyAdminOwner'     "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'l2ProxyAdminOwner'     "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'systemConfigOwner'     "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'unsafeBlockSigner'     "\"$GS_SEQUENCER_ADDRESS\"" "$DEPLOYER_INTENT_FILE"
#update_toml_value 'batcher'               "\"$GS_BATCHER_ADDRESS\""   "$DEPLOYER_INTENT_FILE"
#update_toml_value 'proposer'              "\"$GS_PROPOSER_ADDRESS\""  "$DEPLOYER_INTENT_FILE"
#update_toml_value 'challenger'            "\"$GS_ADMIN_ADDRESS\""     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'l1ContractsLocator'    "\"$L1_CONTRACTS_LOCATOR\"" "$DEPLOYER_INTENT_FILE"
#update_toml_value 'l2ContractsLocator'    "\"$L2_CONTRACTS_LOCATOR\"" "$DEPLOYER_INTENT_FILE"
#update_toml_value 'eip1559DenominatorCanyon' "$EIP1559_DENOMINATOR_CANYON" "$DEPLOYER_INTENT_FILE"
#update_toml_value 'eip1559Denominator'     "$EIP1559_DENOMINATOR"     "$DEPLOYER_INTENT_FILE"
#update_toml_value 'eip1559Elasticity'      "$EIP1559_ELASTICITY"      "$DEPLOYER_INTENT_FILE"

dasel put -t bool -v "$FUND_DEV_ACCOUNTS" -f "$DEPLOYER_INTENT_FILE" -r toml '.fundDevAccounts'
dasel put -t string -v "$L1_CONTRACTS_LOCATOR" -f "$DEPLOYER_INTENT_FILE" -r toml '.l1ContractsLocator'
dasel put -t string -v "$L2_CONTRACTS_LOCATOR" -f "$DEPLOYER_INTENT_FILE" -r toml '.l2ContractsLocator'

dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.superchainRoles.proxyAdminOwner'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.superchainRoles.protocolVersionsOwner'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.superchainRoles.guardian'

dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().baseFeeVaultRecipient'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().l1FeeVaultRecipient'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().sequencerFeeVaultRecipient'
dasel put -t int -v "$EIP1559_DENOMINATOR_CANYON" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().eip1559DenominatorCanyon'
dasel put -t int -v "$EIP1559_DENOMINATOR" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().eip1559Denominator'
dasel put -t int -v "$EIP1559_ELASTICITY" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().eip1559Elasticity'

dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.l1ProxyAdminOwner'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.l2ProxyAdminOwner'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.systemConfigOwner'
dasel put -t string -v "$GS_SEQUENCER_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.unsafeBlockSigner'
dasel put -t string -v "$GS_BATCHER_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.batcher'
dasel put -t string -v "$GS_PROPOSER_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.proposer'
dasel put -t string -v "$GS_ADMIN_ADDRESS" -f "$DEPLOYER_INTENT_FILE" -r toml '.chains.first().roles.challenger'

# output the contents of the intetn file for debugging
cat "$DEPLOYER_INTENT_FILE"

# Generate IMPL_SALT
if [ -z "$IMPL_SALT" ]; then
  IMPL_SALT=$(sha256sum "$DEPLOYER_INTENT_FILE" | cut -d ' ' -f1)
  export IMPL_SALT
fi

# If not deployed
if [ ! -f "$DEPLOYMENT_DIR"/addresses.json ]; then
  # Deploy the L1 contracts
  ./bin/op-deployer apply --workdir "$DEPLOYER_WORKDIR" --l1-rpc-url "$L1_RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY"
fi

# Extract artifact info and genesis files.
./bin/op-deployer inspect superchain-registry --workdir "$DEPLOYER_WORKDIR" "$L2_CHAIN_ID"

# Copy the deployment files to the data volume
cp "$DEPLOYER_WORKDIR"/genesis.json "$DEPLOYMENT_DIR"/
cp "$DEPLOYER_WORKDIR"/rollup.json "$DEPLOYMENT_DIR"/
cp "$DEPLOYER_WORKDIR"/deploy-config.json "$DEPLOYMENT_DIR"/
cp "$DEPLOYER_WORKDIR"/superchain-registry.env "$DEPLOYMENT_DIR"/
cp "$DEPLOYER_WORKDIR"/addresses.json  "$DEPLOYMENT_DIR"/

# copy the genesis files to the config folder
cp "$DEPLOYER_INTENT_FILE" "$CONFIG_PATH"/intent.toml
cp "$DEPLOYER_WORKDIR"/genesis.json "$CONFIG_PATH"/
cp "$DEPLOYER_WORKDIR"/rollup.json "$CONFIG_PATH"/

# Reset repository for cleanup
cd "$OPTIMISM_DIR"
git reset HEAD --hard

exec "$@"
