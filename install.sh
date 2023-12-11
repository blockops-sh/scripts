#!/bin/bash

# Assign command line arguments to variables
PROJECT_ID=$1
PROJECT_NAME=$2

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker could not be found. Please install Docker and retry."
    exit 1
fi

# Create a configuration directory and files
CONFIG_DIR="/tmp/blockops/agent-config"
mkdir -p "${CONFIG_DIR}"

# Create the relaychain.yml file
cat <<EOF > "${CONFIG_DIR}/agent.yaml"
server:
  log_level: info

prometheus:
  wal_directory: /tmp/wal
  global:
    scrape_interval: 15s
    external_labels:
      project_id: \${PROJECT_ID}
      project_name: \${PROJECT_NAME}
  configs:
    - name: relaychain
      scrape_configs:
        - job_name: relaychain
          static_configs:
            - targets: ['localhost:9616']
      remote_write:
        - url: https://thanos-querier.blockops.network
          basic_auth:
            username: loki-blockops
            password: 7a$UG9wt9ace5/.vA
EOF

# Run the Docker container
docker run -d --name grafana-agent --network="host" --pid="host" --cap-add SYS_TIME \
    -v /tmp/agent:/etc/agent \
    -v "${CONFIG_DIR}/agent.yaml:/etc/agent-config/agent.yaml" \
    -e PROJECT_ID=blk-public-rococo \
    -e PROJECT_NAME=blockops-public-dashboards \
    grafana/agent:v0.37.2 \
    --config.file=/etc/agent-config/agent.yaml -config.expand-env