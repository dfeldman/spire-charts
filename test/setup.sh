#!/bin/bash -xeuo pipefail

TRUST_DOMAIN="spiffe://test.com"

# Check binaries: kind, kubectl, docker, helm
which kind || (echo "kind not found"; exit 1)
which kubectl || (echo "kubectl not found"; exit 1)
which helm || (echo "helm not found"; exit 1)
which docker || (echo "docker not found"; exit 1)
(helm version | grep "Version:\"v3.") || (echo "Helm is not version 3"; exit 1)
jq


# First create the test cluster
kind delete cluster --name=test  # make sure we're starting from a blank slate
kind create cluster --name=test --config=kind-config.yaml
kind export kubeconfig --name=test

# Install MetalLB on the test cluster
# This is the easiest way to get traffic in and out of the cluster
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/master/manifests/namespace.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/master/manifests/metallb.yaml
sleep 5
subnet=`cmds/get_docker_subnet.sh`
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${subnet}0.100-${subnet}0.150
EOF

# Sleep pod for use as a curl client
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.9/samples/sleep/sleep.yaml

# Install the SPIRE server, agents, and k8s-workload-registrar with all defaults
helm install spire ../charts/spire-chart
# LB so it can be accessed outside the cluster
kubectl apply -f util/spire-server-lb.yaml
# This helps with debugging in case the LB isn't working
kubectl apply -f util/spire-nodeport.yaml


