#!/bin/sh

# Check if OP_PROPOSER_PRIVATE_KEY environment variable is set
if [ -z "$OP_PROPOSER_PRIVATE_KEY" ]; then
  echo "OP_PROPOSER_PRIVATE_KEY are missing, fetching from AWS Secrets Manager..."
  secrets=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_ARN" | jq '.SecretString | fromjson')

  OP_PROPOSER_PRIVATE_KEY="$(echo "${secrets}" | jq -r '.PROPOSER_PRIVATE_KEY')"

  export OP_PROPOSER_PRIVATE_KEY
fi

# Check if OP_PROPOSER_L2OO_ADDRESS environment variable is set
if [ -z "$OP_PROPOSER_L2OO_ADDRESS" ]; then
  # If not set, check if the file exists
  if [ ! -f "$DEPLOYMENT_DIR/addresses.json" ]; then
    echo "File $DEPLOYMENT_DIR/addresses.json does not exist. Please import data/deployments or set the OP_PROPOSER_L2OO_ADDRESS variable."
    exit 1
  fi
  # Use the address from the $DEPLOYMENT_DIR
  OP_PROPOSER_L2OO_ADDRESS=$(jq -r .L2OutputOracleProxy $DEPLOYMENT_DIR/addresses.json)
fi

# Check if OP_PROPOSER_L2OO_ADDRESS environment variable is set
if [ -z "$OP_PROPOSER_L2OO_ADDRESS" ] && [ -z "$OP_PROPOSER_GAME_FACTORY_ADDRESS" ]; then
  # If not set, check if the file exists
  if [ ! -f "$DEPLOYMENT_DIR/addresses.json" ]; then
    echo "File $DEPLOYMENT_DIR/addresses.json does not exist. Please import data/deployments or set the OP_PROPOSER_L2OO_ADDRESS variable."
    exit 1
  fi
  # Use the address from the $DEPLOYMENT_DIR
  OP_PROPOSER_GAME_FACTORY_ADDRESS=$(jq -r .DisputeGameFactoryProxy $DEPLOYMENT_DIR/addresses.json)
fi

exec "$BIN_DIR"/op-proposer
