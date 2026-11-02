#!/usr/bin/env bash
# StackGuard does not use Vertical or Horizontal Pod Autoscaling.
# Application and Postgres are always exactly 1 pod.
# Scale by increasing CPU/RAM on the pod (and the node machine size).
echo "Autoscaling is disabled for StackGuard. Application and Postgres stay at 1 pod."
echo "Raise APPLICATION_* / POSTGRES_* CPU and memory in stackguard.env, then re-run apply.sh."
echo "Increase the cluster node size in Terraform if the node is too small."
exit 0
