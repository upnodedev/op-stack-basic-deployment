# Use Ubuntu as the base image
FROM ubuntu:22.04

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=noninteractive

ENV NODE_VERSION 20
ENV GO_VERSION 1.21.8
ENV FOUNDRY_VERSION nightly-ef62fdbab638a275fc19a2ff8fe8951c3bd1d9aa

# Update and install basic dependencies
RUN apt-get update && \
    apt-get install -y git make jq curl wget gettext-base build-essential pkg-config libssl-dev openssl ca-certificates unzip gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install nodejs -y

# Install just
RUN mkdir -p /app/bin
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /app/bin
ENV PATH="$PATH:/app/bin"

# Install Go
RUN ARCH=$(dpkg --print-architecture) && echo "Architecture: ${ARCH}" && \
    wget https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz -O go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup -v ${FOUNDRY_VERSION}

# Install AWS CLI version 2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip ./aws

# Define work directory
WORKDIR /app

# Copy the scripts
COPY scripts/clone-repos.sh /app/clone-repos.sh
COPY scripts/utils.sh /app/utils.sh
COPY scripts/prepare.sh /app/prepare.sh

# Set permissions
RUN chmod +x /app/clone-repos.sh
RUN chmod +x /app/prepare.sh

# MacOS pnpm fix
#RUN mkdir -p /app/pnpm/store
#RUN pnpm config set store-dir /app/pnpm/store

# Set the clone-repos.sh script as the entry point
ENTRYPOINT ["/app/prepare.sh"]
