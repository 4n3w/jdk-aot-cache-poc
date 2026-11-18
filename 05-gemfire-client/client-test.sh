#!/bin/bash
# 05, the part that runs inside the client image: a GemFire Java client with the AOT cache.
# test.sh starts the cluster and runs this with LOCATOR_HOST set.
. /poc/lib/common.sh

CLIENT="-cp $FIXTURES/gemfire-client.jar:/opt/gemfire/lib/gemfire-dependencies.jar demo.GemFireClient"
LIVE="-Dlocator.host=$LOCATOR_HOST -Dlocator.port=${LOCATOR_PORT:-10334}"
BLIND="-Dlocator.host=localhost -Dlocator.port=10999"   # nothing listens there

# Module options for the client on JDK 25. They are part of both runs, because they have to match (01).
MODULE_OPTS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED \
--add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED \
--add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED \
--add-opens=java.sql/java.sql=ALL-UNNAMED --enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow"
TRAIN_OPTS="$MODULE_OPTS -XX:+UseG1GC -Xms999M -Xmx999M"   # no -XX:CompressedClassSpaceSize (03)
PROD_OPTS="$MODULE_OPTS $PROD_MEMORY_OPTS"

GEODE=' org\.apache\.geode\.'
result_line() { grep -m1 '^RESULT' "$1" | sed 's/^RESULT //'; }
operations()  { if grep -q '^RESULT.*operations OK' "$1"; then echo worked; else echo failed; fi; }

# use_cache <cache>: a production run against the live cluster that has to use the cache.
use_cache() {
  local cache=$1 result
  if production "$cache" $PROD_OPTS $LIVE $CLIENT; then result=used; else result=rejected; fi
  expect "cache:" "$result" "used"
  [ "$result" = used ] || { show "JVM:" "$(jvm_reason "$cache.run.log")"; return; }
  expect "operations:" "$(operations "$cache.run.log")" "worked"
  show "client:" "$(result_line "$cache.run.log")"
  show "GemFire classes:" "$(grep -E "$GEODE" "$cache.classes.log" | grep -c 'shared objects file') of $(grep -cE "$GEODE" "$cache.classes.log") from the cache"
  show "all classes:" "$(from_cache "$cache.classes.log") of $(loaded "$cache.classes.log") from the cache"
}

section "1. No AOT cache, against the live cluster"
java $PROD_OPTS $LIVE -Xlog:class+load:file="$WORK/no-cache.classes.log" $CLIENT >"$WORK/no-cache.log" 2>&1
expect "operations:" "$(operations "$WORK/no-cache.log")" "worked"
show "client:" "$(result_line "$WORK/no-cache.log")"
show "GemFire classes:" "$(grep -cE "$GEODE" "$WORK/no-cache.classes.log") loaded"

section "2. Cache trained against the live cluster"
if train "$WORK/live.aot" $TRAIN_OPTS $LIVE $CLIENT; then result="cache written"; else result="no cache written"; fi
expect "training:" "$result" "cache written"
show "training run:" "$(result_line "$WORK/live.aot.train.log")"
show "cache size:" "$(megabytes "$WORK/live.aot")"
use_cache "$WORK/live.aot"

section "3. Cache trained with no cluster reachable, then used against the live cluster"
if train "$WORK/blind.aot" $TRAIN_OPTS $BLIND $CLIENT; then result="cache written"; else result="no cache written"; fi
expect "training:" "$result" "cache written"
expect "training run:" "operations $(operations "$WORK/blind.aot.train.log")" "operations failed"
show "" "$(result_line "$WORK/blind.aot.train.log")"
show "cache size:" "$(megabytes "$WORK/blind.aot")"
use_cache "$WORK/blind.aot"

# timed <extra java options...>: medians over RUNS client runs against the live cluster, after one
# warm-up run. "Whole JVM" is wall-clock time from process start to exit.
timed() {
  local walls="" creates="" i start end out
  for i in $(seq 0 "$RUNS"); do
    start=$(date +%s%N)
    out=$(java "$@" $PROD_OPTS $LIVE $CLIENT 2>/dev/null)
    end=$(date +%s%N)
    [ "$i" -gt 0 ] || continue
    walls="$walls$(( (end - start) / 1000000 ))"$'\n'
    creates="$creates$(sed -n 's/^RESULT cacheCreate=\([0-9]*\)ms.*/\1/p' <<<"$out")"$'\n'
  done
  echo "ClientCache and region creation $(printf '%s' "$creates" | median) ms, whole JVM $(printf '%s' "$walls" | median) ms"
}

section "4. Startup time against the live cluster: median of $RUNS runs"
show "no cache:" "$(timed)"
show "cache, live training:" "$(timed -XX:AOTCache="$WORK/live.aot")"
show "cache, blind training:" "$(timed -XX:AOTCache="$WORK/blind.aot")"

section "5. Training the client at different class-space sizes (no cluster needed)"
for size in 40M 48M 64M; do
  if train "$WORK/size-$size.aot" -XX:CompressedClassSpaceSize=$size $TRAIN_OPTS $BLIND $CLIENT; then
    result="cache written"
  else
    result="no cache written: $(jvm_reason "$WORK/size-$size.aot.train.log")"
  fi
  case $size in
    64M) expect "$size:" "$result" "cache written" ;;
    *)   expect "$size:" "$result" "no cache written: Unable to allocate from 'ro' region: Please reduce the number of shared classes." ;;
  esac
done

finish
