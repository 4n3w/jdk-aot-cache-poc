#!/bin/bash
# 04: the AOT cache with a Spring Boot executable WAR, packed and extracted.
#
# Runs inside the test image: make 04
. /poc/lib/common.sh

EXIT=-Dspring.context.exit=onRefresh
WAR=$FIXTURES/sample-app.war
PROVIDED_WAR=$FIXTURES/sample-app-provided.war

# Classes that come out of the WAR rather than the JDK: Spring, Tomcat, Jackson and the application.
WAR_CLASSES=' (org\.springframework|org\.apache|tools\.jackson|com\.fasterxml|com\.example)\.'
war_loaded()     { grep -cE "$WAR_CLASSES" "$1"; }
war_from_cache() { grep -E "$WAR_CLASSES" "$1" | grep -c 'source: shared objects file'; }

# train_and_run <cache> <java arguments...>: train, then run with the cache, and report both.
train_and_run() {
  local cache=$1 result; shift
  if train "$cache" "$@"; then result="cache written"; else result="no cache written"; fi
  expect "training:" "$result" "cache written"
  [ "$result" = "cache written" ] || { show "JVM:" "$(jvm_reason "$cache.train.log")"; return; }
  show "cache size:" "$(megabytes "$cache")"
  if production "$cache" "$@"; then result=used; else result=rejected; fi
  expect "cache:" "$result" "used"
  [ "$result" = used ] || { show "JVM:" "$(jvm_reason "$cache.run.log")"; return; }
  show "classes from cache:" "$(from_cache "$cache.classes.log") of $(loaded "$cache.classes.log")"
  show "  from the WAR:" "$(war_from_cache "$cache.classes.log") of $(war_loaded "$cache.classes.log") (Spring, Tomcat, Jackson, application)"
}

section "The two sample WARs"
for war in "$WAR" "$PROVIDED_WAR"; do
  show "$(basename "$war"):" "$(jar tf "$war" | grep -c '^WEB-INF/lib/.*\.jar$') jars in WEB-INF/lib/, $(jar tf "$war" | grep -c '^WEB-INF/lib-provided/.*\.jar$') in WEB-INF/lib-provided/"
done

section "1. Packed: java -jar sample-app.war, trained and run as it is"
train_and_run "$WORK/packed.aot" $EXIT -jar "$WAR"

section "2. Spring Boot's extract command: java -Djarmode=tools -jar <war> extract --destination <dir>"
extract() { # <outcome in our run> <war> <destination>
  local result
  if java -Djarmode=tools -jar "$2" extract --destination "$3" >"$3.log" 2>&1; then result=extracted; else result="extract failed"; fi
  expect "$(basename "$2"):" "$result" "$1"
  if [ "$result" = extracted ]; then
    show "  result:" "$(basename "$2") ($(stat -c %s "$3/$(basename "$2")") bytes, a launcher) and lib/ with $(ls "$3/lib" | wc -l) jars"
  else
    show "  Spring Boot:" "$(grep -m1 -oE 'Invalid library location.*' "$3.log")"
  fi
}
extract "extracted"      "$WAR"          "$WORK/app"
extract "extract failed" "$PROVIDED_WAR" "$WORK/app-provided"

section "3. Extracted: java -jar <dir>/sample-app.war, trained and run from the extracted layout"
train_and_run "$WORK/extracted.aot" $EXIT -jar "$WORK/app/sample-app.war"

section "4. Unzipped by hand, with directories on the class path"
mkdir -p "$WORK/unzipped"
(cd "$WORK/unzipped" && jar xf "$WAR")
CLASSPATH_ARGS="-cp $WORK/unzipped/WEB-INF/classes:$WORK/unzipped/WEB-INF/lib/* com.example.sample.SampleApplication"
show "command:" "java -cp WEB-INF/classes:WEB-INF/lib/* com.example.sample.SampleApplication"
if train "$WORK/unzipped.aot" $EXIT $CLASSPATH_ARGS; then result="cache written"; else result="no cache written"; fi
expect "training:" "$result" "no cache written"
show "JVM:" "$(jvm_reason "$WORK/unzipped.aot.train.log")"
show "" "$(grep -m1 'Cannot have non-empty directory' "$WORK/unzipped.aot.train.log")"

finish
