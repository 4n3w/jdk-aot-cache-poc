#!/bin/bash
# 03: -XX:CompressedClassSpaceSize and -XX:MaxMetaspaceSize with the AOT cache.
#
# Trains the sample Spring Boot application at several class-space sizes, then checks what the
# production memory options do at runtime. Runs inside the test image: make 03
. /poc/lib/common.sh

java -Djarmode=tools -jar "$FIXTURES/sample-app.war" extract --destination "$WORK/app" >/dev/null
APP="-Dspring.context.exit=onRefresh -jar $WORK/app/sample-app.war"

# train_at <outcome in our run> <label> [<option>]
train_at() {
  local ours=$1 label=$2 option=${3:-} cache=$WORK/$2.aot result
  train "$cache" $option $APP
  local code=$?
  if [ $code -eq 0 ]; then result="cache written"; else result="no cache written"; fi
  printf '\n  %s\n' "${option:-no -XX:CompressedClassSpaceSize option (the default is 1 GB)}"
  expect "training:" "$result" "$ours"
  if [ $code -eq 0 ]; then
    show "cache size:" "$(megabytes "$cache")"
  else
    show "exit code:" "$(java -XX:AOTCacheOutput="$cache" $option $APP >/dev/null 2>&1; echo $?)"
    show "JVM:" "$(jvm_reason "$cache.train.log")"
  fi
}

section "Training the sample Spring Boot application at different class-space sizes"
train_at "no cache written" 40M     -XX:CompressedClassSpaceSize=40M
train_at "no cache written" 48M     -XX:CompressedClassSpaceSize=48M
train_at "cache written"    64M     -XX:CompressedClassSpaceSize=64M
train_at "cache written"    default

section "Production with the full memory option set, cache trained without the option"
show "production options:" "$PROD_MEMORY_OPTS"
if production "$WORK/default.aot" $PROD_MEMORY_OPTS $APP; then result=used; else result=rejected; fi
expect "cache:" "$result" "used"
show "classes from cache:" "$(from_cache "$WORK/default.aot.classes.log") of $(loaded "$WORK/default.aot.classes.log")"
grep -m1 'CompressedClassSpaceSize adjusted' "$WORK/default.aot.run.log" | sed -E 's/^(\[[^]]*\])+ ?//' |
  while read -r line; do show "JVM:" "$line"; done

# Native Memory Tracking prints the JVM's own accounting when it exits. "committed" is memory in use.
section "Native memory at exit with the production memory options (NMT summary, committed MB)"
nmt() { # <output file> [<extra option>]
  java ${2:-} $PROD_MEMORY_OPTS -XX:NativeMemoryTracking=summary -XX:+UnlockDiagnosticVMOptions -XX:+PrintNMTStatistics \
    $APP >"$1" 2>&1
}
committed() { # <NMT category> <output file>
  awk -v category="$1" '
    $0 ~ "^(- *)?" category "[ :]+\\(?reserved=" {
      sub(/.*committed=/, ""); sub(/[,)].*/, ""); printf "%.1f", $0 / 1048576; exit
    }' "$2"
}
nmt "$WORK/nmt-without.out"
nmt "$WORK/nmt-with.out" "-XX:AOTCache=$WORK/default.aot"
printf '    %-22s %14s %14s\n' "" "without cache" "with cache"
for category in "Metaspace" "Shared class space" "Total"; do
  printf '    %-22s %14s %14s\n' "$category" "$(committed "$category" "$WORK/nmt-without.out")" "$(committed "$category" "$WORK/nmt-with.out")"
done
echo "    Metaspace holds class metadata the JVM builds at runtime. Shared class space is the mapped cache file."
without=$(committed Metaspace "$WORK/nmt-without.out"); with=$(committed Metaspace "$WORK/nmt-with.out")
expect "Metaspace with cache:" "$(awk -v a="$with" -v b="$without" 'BEGIN { print (a < b) ? "lower" : "not lower" }')" "lower"

finish
