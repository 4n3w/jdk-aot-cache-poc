#!/bin/bash
# 01: what has to be the same in the training run and the production run?
#
# Every case trains a cache for the plain application one way, then starts the application another
# way. Runs inside the test image: make 01
. /poc/lib/common.sh

OPENS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.sql/java.sql=ALL-UNNAMED"
REORDERED="--add-opens=java.sql/java.sql=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED"
NATIVE="--enable-native-access=ALL-UNNAMED"
JAVAAGENT="-javaagent:$AGENT"
JMX="-Dcom.sun.management.jmxremote"

# The archive each run starts. The last section changes these.
TRAIN_JAR=$FIXTURES/plain-app.jar
PROD_JAR=$FIXTURES/plain-app.jar

n=0

# try <outcome in our run> <what the case changes> <training options> <production options> [<step after training>]
# The outcome is one of: used, rejected, "training failed".
try() {
  local ours=$1 what=$2 training=$3 production=$4 after=${5:-} cache result
  n=$((n + 1)); cache=$WORK/case$n.aot
  printf '\n%2d. %s\n' "$n" "$what"
  show "training options:" "${training:-(none)}"
  show "production options:" "${production:-(none)}"
  if ! train "$cache" $training -cp "$TRAIN_JAR" demo.Main; then
    result="training failed"
  else
    if [ -n "$after" ]; then
      show "after training:" "$after"
      eval "$after"
    fi
    if production "$cache" $production -cp "$PROD_JAR" demo.Main; then result=used; else result=rejected; fi
  fi
  expect "cache:" "$result" "$ours"
  case $result in
    used)     show "classes from cache:" "$(from_cache "$cache.classes.log") of $(loaded "$cache.classes.log")" ;;
    rejected) show "JVM:" "$(jvm_reason "$cache.run.log")" ;;
    *)        show "JVM:" "$(jvm_reason "$cache.train.log")" ;;
  esac
}

section "Options that open modules or allow native access: the set has to match"
try used     "--add-opens: same set in both runs"                 "$OPENS"  "$OPENS"
try used     "--add-opens: same set, different order"             "$OPENS"  "$REORDERED"
try rejected "--add-opens: in the training run only"              "$OPENS"  ""
try rejected "--add-opens: in the production run only"            ""        "$OPENS"
try rejected "--add-opens: one more in the production run"        "$OPENS"  "$OPENS --add-opens=java.base/java.nio=ALL-UNNAMED"
try used     "--enable-native-access: in both runs"               "$NATIVE" "$NATIVE"
try rejected "--enable-native-access: in the production run only" ""        "$NATIVE"

section "Options that add a JDK module behind the scenes: the added modules have to match"
try used     "-javaagent: in both runs"                           "$JAVAAGENT" "$JAVAAGENT"
try rejected "-javaagent: in the production run only"             ""           "$JAVAAGENT"
try rejected "-javaagent: in the training run only"               "$JAVAAGENT" ""
try used     "--add-modules=java.instrument in training stands in for -javaagent" "--add-modules=java.instrument" "$JAVAAGENT"
try rejected "-Dcom.sun.management.jmxremote: in the production run only" "" "$JMX"
try rejected "-Dcom.sun.management.jmxremote: in the training run only"   "$JMX" ""
try rejected "-Dcom.sun.management with nothing after it: in the production run only" "" "-Dcom.sun.management"
try used     "--add-modules in training stands in for -javaagent and -Dcom.sun.management" "$TRAIN_MODULE_OPTS" "$PROD_MODULE_OPTS"

section "Options that do not have to match"
try used     "--sun-misc-unsafe-memory-access: in the production run only" "" "--sun-misc-unsafe-memory-access=allow"
try used     "Production memory and GC options against training defaults"  "" "$PROD_MEMORY_OPTS"
try used     "Ordinary -D system properties: in the production run only"   "" "$PROD_PROPERTIES"
try used     "Serial GC in training, G1 in production"            "-XX:+UseSerialGC" "-XX:+UseG1GC"
try used     "G1 in training, Serial GC in production"            "-XX:+UseG1GC"     "-XX:+UseSerialGC"
try used     "Training sized like a small build runner (1 CPU, 256 MB heap)" "-XX:ActiveProcessorCount=1 -Xmx256m" "$PROD_MEMORY_OPTS"

section "Heap size: matters only when one run is above 32 GB and the other is not"
try rejected "Training heap of 40 GB (what an unset -Xmx becomes on a large build host), production heap below 1 GB" "-Xmx40g" "$PROD_MEMORY_OPTS"

section "The application archive has to be the file the cache was trained on"
TRAIN_JAR=$WORK/build/app.jar
PROD_JAR=$WORK/build/app.jar
fresh_copy() { mkdir -p "$WORK/build" "$WORK/deploy"; cp -p "$FIXTURES/plain-app.jar" "$WORK/build/app.jar"; }
echo "added after training" > "$WORK/extra.txt"

fresh_copy
try rejected "Archive timestamp changed after training"  "" "" "touch -d 2020-01-01 $WORK/build/app.jar"
fresh_copy
try rejected "Archive rebuilt after training (one more entry)" "" "" "jar --update --file $WORK/build/app.jar -C $WORK extra.txt"
fresh_copy
PROD_JAR=$WORK/deploy/app.jar
try used     "Same archive run from another directory, file name and timestamp kept" "" "" "cp -p $WORK/build/app.jar $WORK/deploy/app.jar"
PROD_JAR=$WORK/deploy/renamed.jar
try rejected "Same archive run under another file name"  "" "" "cp -p $WORK/build/app.jar $WORK/deploy/renamed.jar"

# The cases above start production with -XX:AOTMode=on, so a rejected cache stops the JVM. This is
# the same rejection as case 4 in the default mode, which is how production would normally run.
section "A rejected cache in the default mode (no -XX:AOTMode=on)"
APP="-cp $FIXTURES/plain-app.jar demo.Main"
cache=$WORK/default-mode.aot
train "$cache" $APP
java -XX:AOTCache="$cache" -Xlog:class+load:file="$WORK/accepted.log" $APP >/dev/null 2>&1
java -XX:AOTCache="$cache" -Xlog:class+load:file="$WORK/rejected.log" $OPENS $APP >"$WORK/rejected.out" 2>&1
code=$?
java -Xlog:class+load:file="$WORK/no-option.log" $OPENS $APP >/dev/null 2>&1
echo "    The cache was trained without --add-opens and production passes them, as in case 4."
expect "exit code:" "$code" "0"
expect "application:" "$(grep -c '^app ran' "$WORK/rejected.out") run completed" "1 run completed"
echo "    JVM output:"
grep -E '^\[' "$WORK/rejected.out" | sed 's/^/      /'
echo "    Classes loaded from an archive, out of all classes loaded:"
show "  cache accepted:"   "$(from_cache "$WORK/accepted.log") of $(loaded "$WORK/accepted.log")"
expect "  cache rejected:" "$(from_cache "$WORK/rejected.log") of $(loaded "$WORK/rejected.log")" "0 of $(loaded "$WORK/rejected.log")"
show "  no AOT option:"    "$(from_cache "$WORK/no-option.log") of $(loaded "$WORK/no-option.log") (from the JDK's built-in archive)"

finish
