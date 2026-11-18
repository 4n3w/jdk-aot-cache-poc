#!/bin/bash
# 05: a GemFire Java client with the AOT cache.
#
# Builds the client image, starts a one-locator, one-server GemFire cluster in a container, runs
# client-test.sh in the client image against it, and removes the cluster again.
#
# Runs on the host and needs the images that `make image` builds: make 05 ACCEPT_TERMS=y
HERE=$(dirname "$0")

IMAGE=${IMAGE:-aot-poc}
GEMFIRE_IMAGE=${GEMFIRE_IMAGE:-gemfire/gemfire:10.3.2-jdk17}
RUNS=${RUNS:-5}
CPUS=${CPUS:-2}
PLATFORM_FLAG=${PLATFORM:+--platform $PLATFORM}
NETWORK=aot-poc-net
CLUSTER=aot-poc-gemfire

# The GemFire image only runs once the Broadcom terms are accepted, and that is the user's call.
if [ "${ACCEPT_TERMS:-}" != y ]; then
  echo "05 uses the GemFire image $GEMFIRE_IMAGE, which requires accepting the Broadcom terms:"
  echo "  https://www.broadcom.com/company/legal/licensing"
  echo "To accept them and run this test:  make 05 ACCEPT_TERMS=y"
  exit 1
fi

cleanup() {
  docker rm -f "$CLUSTER" >/dev/null 2>&1
  docker network rm "$NETWORK" >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

echo "Building the client image ($GEMFIRE_IMAGE jars, client compiled against them) ..."
docker build -q $PLATFORM_FLAG --build-arg GEMFIRE_IMAGE="$GEMFIRE_IMAGE" --build-arg TOOLS_IMAGE="$IMAGE:tools" \
  -t "$IMAGE:gemfire-client" "$HERE" >/dev/null || exit 1

echo "Starting a GemFire cluster (1 locator, 1 server, region 'demo') ..."
docker network create "$NETWORK" >/dev/null || exit 1
docker run -d --name "$CLUSTER" --network "$NETWORK" -e ACCEPT_TERMS=y "$GEMFIRE_IMAGE" sh -c "
  gfsh -e 'start locator --name=locator1 --hostname-for-clients=$CLUSTER' \
       -e 'start server --name=server1 --locators=localhost[10334] --hostname-for-clients=$CLUSTER' \
       -e 'create region --name=demo --type=PARTITION' &&
  touch /tmp/ready && tail -f /dev/null" >/dev/null || exit 1
for i in $(seq 1 60); do
  docker exec "$CLUSTER" test -f /tmp/ready 2>/dev/null && break
  [ "$(docker inspect -f '{{.State.Running}}' "$CLUSTER" 2>/dev/null)" = true ] || break
  sleep 3
done
if ! docker exec "$CLUSTER" test -f /tmp/ready 2>/dev/null; then
  echo "The cluster did not start. Its output:"
  docker logs "$CLUSTER" 2>&1 | tail -n 30
  exit 1
fi

docker run --rm $PLATFORM_FLAG --cpus "$CPUS" --network "$NETWORK" -e RUNS="$RUNS" -e LOCATOR_HOST="$CLUSTER" \
  "$IMAGE:gemfire-client" bash /poc/05-gemfire-client/client-test.sh
