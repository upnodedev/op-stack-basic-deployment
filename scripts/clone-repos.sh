#!/bin/bash

# Function to clear and clone a repository
clone_repo() {
  local repo_url=$1
  local branch_or_commit=$2
  local dest_dir=$3

  cd "$dest_dir" || exit 1

  # Check if the repository is on the correct version
  if [ -d ".git" ]; then
    echo "Checking repository version in $dest_dir"
    git fetch --all -q

    local remote_commit
    if git ls-remote --heads origin | grep -qE "refs/heads/$branch_or_commit$"; then
      # branch_or_commit is a branch
      remote_commit=$(git rev-parse origin/"$branch_or_commit")
    elif git ls-remote --tags origin | grep -qE "refs/tags/$branch_or_commit$"; then
      # branch_or_commit is a tag
      remote_commit=$(git rev-parse "refs/tags/$branch_or_commit^{commit}")
    else
      # Verify if branch_or_commit is a valid commit hash
      if ! git cat-file -e "$branch_or_commit^{commit}" 2> /dev/null; then
        echo "Error: '$branch_or_commit' is not a valid branch, tag, or commit hash."
        cd - > /dev/null || exit
        return 1
      fi
      # branch_or_commit is a commit hash
      remote_commit=$(git rev-parse "$branch_or_commit")
    fi

    local current_commit
    current_commit=$(git rev-parse HEAD)

    if [ "$current_commit" != "$remote_commit" ]; then
      echo "Version mismatch. Clearing binaries and existing repository..."
      # Remove binaries
      rm -f "$BIN_DIR"/op-node "$BIN_DIR"/op-batcher "$BIN_DIR"/op-proposer "$BIN_DIR"/geth

      # Remove all contents including hidden files and directories
      rm -rf ./{,.[!.],..?}*
    else
      if [ ! -f "$BIN_DIR/op-node" ] || [ ! -f "$BIN_DIR/op-batcher" ] || [ ! -f "$BIN_DIR/op-proposer" ] || [ ! -f "$BIN_DIR/geth" ]; then
        echo "Some binary is missing. Force clearing repository..."
        rm -rf ./{,.[!.],..?}*
      else
        echo "Repository in $dest_dir is already up to date."
        cd - > /dev/null || exit
        return 0
      fi
    fi
  fi

  # Clone the repository
  echo "Cloning $repo_url into $dest_dir"
  git clone --recursive "$repo_url" .
  echo "Cloning complete"

  # Checkout to the specific branch or commit
  echo "Checking out to $branch_or_commit"
  git checkout "$branch_or_commit"

  cd - > /dev/null || exit
}

# Use environment variables if set, otherwise default to the official repositories
OPTIMISM_REPO=${OPTIMISM_REPO_URL:-https://github.com/ethereum-optimism/optimism.git}
OPTIMISM_BRANCH_OR_COMMIT=${OPTIMISM_BRANCH_OR_COMMIT:-v1.9.0}
OP_GETH_REPO=${OP_GETH_REPO_URL:-https://github.com/ethereum-optimism/op-geth.git}
OP_GETH_BRANCH_OR_COMMIT=${OP_GETH_BRANCH_OR_COMMIT:-v1.101315.3}

# Cloning repositories
clone_repo "$OPTIMISM_REPO" "$OPTIMISM_BRANCH_OR_COMMIT" "$OPTIMISM_DIR" || exit 1
clone_repo "$OP_GETH_REPO" "$OP_GETH_BRANCH_OR_COMMIT" "$OP_GETH_DIR" || exit 1

git config --global --add safe.directory '*'

exec "$@"
