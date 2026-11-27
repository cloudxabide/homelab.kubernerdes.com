#!/bin/bash

echo "Enable SUSE AI Assistant extension in Rancher"

mkdir -p ~/Developer/Projects/Liz_AI_Assistant; cd $_

cat << EOF > values.yaml
activeLlm: "ollama"
ollamaUrl: "http://ollama:11434"
ollamaLlmModel: "gpt-oss:20b"
EOF

helm install rancher-ai-agent \
  --namespace cattle-ai-agent-system \
  --create-namespace \
  -f values.yaml \
  oci://registry.suse.com/rancher/charts/rancher-ai-agent
