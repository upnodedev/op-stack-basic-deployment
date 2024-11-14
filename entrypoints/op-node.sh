#!/bin/sh

# Check if SEQUENCER_MODE environment variable is set to false
if [ "$SEQUENCER_MODE" != "true" ]; then
  unset OP_NODE_SEQUENCER_ENABLED
  unset OP_NODE_SEQUENCER_L1_CONFS
  unset OP_NODE_P2P_SEQUENCER_KEY
fi

# Check if OP_NODE_P2P_SEQUENCER_KEY environment variable is set
if [ "$OP_NODE_SEQUENCER_ENABLED" = "true" ]; then
  if [ -z "$OP_NODE_P2P_SEQUENCER_KEY" ]; then
    echo "OP_NODE_P2P_SEQUENCER_KEY is missing, fetching from AWS Secrets Manager..."
    secrets=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_ARN" | jq '.SecretString | fromjson')

    OP_NODE_P2P_SEQUENCER_KEY="$(echo "${secrets}" | jq -r '.SEQUENCER_PRIVATE_KEY')"

    export OP_NODE_P2P_SEQUENCER_KEY
  fi
else
  echo "Sequencer is not enabled. Skipping fetching OP_NODE_P2P_SEQUENCER_KEY."
fi

exec "$BIN_DIR"/op-node
