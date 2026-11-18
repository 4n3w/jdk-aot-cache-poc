#!/bin/bash
# 06: the image build with the AOT cache, end to end.
#
# Builds the application image the way it is built today (before/) and with the two extra build
# steps (after/). Then starts the after image with production-style JAVA_OPTS to check that the cache
# is used, shows what stops it being used, and measures startup time for both images.
#
# Runs on the host and needs the images that `make image` builds: make 06
HERE=$(dirname "$0")
. "$HERE/../lib/options.sh"
. "$HERE/../lib/report.sh"

IMAGE=${IMAGE:-aot-poc}
RUNS=${RUNS:-5}
CPUS=${CPUS:-2}
PLATFORM_FLAG=${PLATFORM:+--platform $PLATFORM}
LOGS=$HERE/build/logs
mkdir -p "$LOGS"

EXIT=-Dspring.context.exit=onRefresh   # exit as soon as the application context has been refreshed

# What the platform injects at deploy time. The stand-in agent reports the application's own classes.
JAVAAGENT="-javaagent:$AGENT=watch=com.example."
PROD_JAVA_OPTS="$JAVAAGENT -Dcom.sun.management $PROD_MEMORY_OPTS $PROD_PROPERTIES"

# The training options of after/Dockerfile, for the runs below that train again.
TRAIN_JAVA_OPTS="$TRAIN_MODULE_OPTS -XX:+UseG1GC -Xms999M -Xmx999M $EXIT"

# start <log> <docker run options...>: start the after image once and keep everything it prints.
start() {
  local log=$1; shift
  docker run --rm $PLATFORM_FLAG --cpus "$CPUS" "$@" "$IMAGE:after" >"$log" 2>&1
}

# report_start <log> <exit code>: the JVM's verdict on the cache, and what was loaded from it.
report_start() {
  local result
  if [ "$2" -eq 0 ]; then result=used; else result=rejected; fi
  expect "cache:" "$result" "used"
  [ "$result" = used ] || { show "JVM:" "$(jvm_reason "$1")"; return; }
  if grep -q 'Root WebApplicationContext: initialization completed' "$1"; then
    expect "application:" "context started" "context started"
  else
    expect "application:" "did not start" "context started"
  fi
  show "classes from cache:" "$(from_cache "$1") of $(loaded "$1")"
  show "agent:" "$(sed -n 's/^\[agent\] started: //p' "$1")"
}

# report_rejection <log> <exit code>: for the runs that are expected to be refused.
report_rejection() {
  local result
  if [ "$2" -eq 0 ]; then result=used; else result=rejected; fi
  expect "cache:" "$result" "rejected"
  [ "$result" = used ] || show "JVM:" "$(jvm_reason "$1")"
}

echo "JDK: $(docker run --rm $PLATFORM_FLAG --entrypoint sh "$IMAGE:base" -c 'java -version 2>&1 | sed -n 2p; uname -m' | paste -sd, - | sed 's/,/, /')"

section "Build"
container=$(docker create $PLATFORM_FLAG "$IMAGE:tools")
for image in before after; do
  mkdir -p "$HERE/$image/build/libs"
  docker cp "$container:/poc/fixtures/sample-app.war" "$HERE/$image/build/libs/sample-app.war" >/dev/null
done
docker rm "$container" >/dev/null
for image in before after; do
  # --no-cache so that the training step runs, and its output is in the log, every time
  if docker build $PLATFORM_FLAG --progress=plain --no-cache --build-arg BASE_IMAGE="$IMAGE:base" \
      -t "$IMAGE:$image" "$HERE/$image" >"$LOGS/build-$image.log" 2>&1; then
    result=built
  else
    result="build failed"
  fi
  expect "$image image:" "$result" "built"
  [ "$result" = built ] || { tail -n 20 "$LOGS/build-$image.log"; finish; }
done
show "training step:" "$(grep -oE 'AOTCache creation is complete: [^ ]+ [0-9]+ bytes' "$LOGS/build-after.log" | head -n 1)"
show "cache file:" "$(docker run --rm $PLATFORM_FLAG --entrypoint stat "$IMAGE:after" -c '%n, owner %U:%G, mode %a' /opt/app/app.aot)"

section "1. Production-style JAVA_OPTS, and the cache has to be used (-XX:AOTMode=on)"
show "JAVA_OPTS:" "$PROD_JAVA_OPTS"
echo
echo "  As built (user 1001)"
start "$LOGS/as-built.log" -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT -XX:AOTMode=on -Xlog:class+load"
report_start "$LOGS/as-built.log" $?
echo
echo "  As an arbitrary user ID in group 0, the way OpenShift runs containers"
start "$LOGS/arbitrary-uid.log" --user 1000680000:0 -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT -XX:AOTMode=on -Xlog:class+load"
report_start "$LOGS/arbitrary-uid.log" $?
echo
echo "  With -Dcom.sun.management.jmxremote in place of the bare prefix (starts the JMX agent)"
start "$LOGS/jmxremote.log" -e JAVA_OPTS="${PROD_JAVA_OPTS/-Dcom.sun.management/-Dcom.sun.management.jmxremote} $EXIT -XX:AOTMode=on -Xlog:class+load"
report_start "$LOGS/jmxremote.log" $?

section "2. What stops the cache being used"
echo "  JAVA_OPTS without -javaagent"
start "$LOGS/no-agent.log" -e JAVA_OPTS="${PROD_JAVA_OPTS/$JAVAAGENT/} $EXIT -XX:AOTMode=on"
report_rejection "$LOGS/no-agent.log" $?
echo
echo "  JAVA_OPTS without -Dcom.sun.management"
start "$LOGS/no-management.log" -e JAVA_OPTS="${PROD_JAVA_OPTS/-Dcom.sun.management/} $EXIT -XX:AOTMode=on"
report_rejection "$LOGS/no-management.log" $?
echo
echo "  The training step with the production memory options (-XX:CompressedClassSpaceSize=40M)"
start "$LOGS/train-40m.log" -e JAVA_OPTS="$TRAIN_MODULE_OPTS $PROD_MEMORY_OPTS $EXIT" -e AOT_OPTS=-XX:AOTCacheOutput=/tmp/again.aot
code=$?
if [ $code -eq 0 ]; then result="cache written"; else result="no cache written"; fi
expect "training:" "$result" "no cache written"
show "exit code:" "$code"
show "JVM:" "$(jvm_reason "$LOGS/train-40m.log")"

# Wall-clock time of the image's own run.sh: from process start until the JVM has exited again, which
# -Dspring.context.exit=onRefresh makes it do once the application context has been refreshed.
# Measured inside the container, so the time to start the container itself is not included.
section "3. Startup time: median of $RUNS runs, $CPUS CPUs, production-style JAVA_OPTS"
timed() { # <image> <docker run options...>
  local image=$1; shift
  docker run --rm -i $PLATFORM_FLAG --cpus "$CPUS" "$@" --entrypoint sh "$IMAGE:$image" -s -- "$RUNS" /tmp/run.sh \
    <"$HERE/../lib/startup-time.sh"
}
wide() { printf '    %-58s %s\n' "$1" "$2"; }
wide "before: packed WAR, no cache" \
  "$(timed before -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT")"
wide "before, plus a cache trained on the packed WAR" \
  "$(timed before -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT -XX:AOTCache=/tmp/packed.aot" \
       -e PREPARE="JAVA_OPTS='$TRAIN_JAVA_OPTS -XX:AOTCacheOutput=/tmp/packed.aot' /tmp/run.sh")"
wide "after, cache switched off: extracted, no cache" \
  "$(timed after -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT" -e AOT_OPTS=-XX:AOTMode=auto)"
wide "after: extracted, with the cache" \
  "$(timed after -e JAVA_OPTS="$PROD_JAVA_OPTS $EXIT")"
wide "after, cache rejected: one more --add-opens in JAVA_OPTS" \
  "$(timed after -e JAVA_OPTS="$PROD_JAVA_OPTS --add-opens=java.base/java.nio=ALL-UNNAMED $EXIT")"

# The JVM can also store compiled adapter and stub code in the cache. These are its defaults.
section "4. Compiled code in the cache: JVM defaults"
flags=$(docker run --rm $PLATFORM_FLAG --entrypoint sh "$IMAGE:after" -c \
  'java -XX:AOTCache=/opt/app/app.aot -XX:+UnlockDiagnosticVMOptions -XX:+PrintFlagsFinal -version 2>/dev/null')
for flag in AOTAdapterCaching AOTStubCaching; do
  expect "$flag:" "$(awk -v flag="$flag" '$2 == flag { print $4 }' <<<"$flags")" "false"
done

finish
