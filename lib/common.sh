# Helpers for the test scripts that run inside the test image. Sourced, not run.

. /poc/lib/options.sh
. /poc/lib/report.sh

FIXTURES=/poc/fixtures
WORK=/tmp/aot-poc                       # this run's caches and logs
rm -rf "$WORK"; mkdir -p "$WORK"
RUNS=${RUNS:-5}

echo "JDK: $(java -version 2>&1 | sed -n 2p), $(uname -m)"

# train <cache> <java arguments...>
# A training run: start the application once and let the JVM write <cache> as it exits
# (-XX:AOTCacheOutput). The JVM's output goes to <cache>.train.log. Fails if no cache was written.
train() {
  local cache=$1; shift
  rm -f "$cache"
  java -XX:AOTCacheOutput="$cache" "$@" >"$cache.train.log" 2>&1 && [ -s "$cache" ]
}

# production <cache> <java arguments...>
# A production run that has to use <cache>: with -XX:AOTMode=on the JVM exits instead of carrying on
# without it, so the exit code is the JVM's own verdict. Output goes to <cache>.run.log, and the
# source of every loaded class to <cache>.classes.log.
production() {
  local cache=$1; shift
  rm -f "$cache.classes.log"
  java -XX:AOTCache="$cache" -XX:AOTMode=on -Xlog:class+load:file="$cache.classes.log" "$@" >"$cache.run.log" 2>&1
}

megabytes() { echo "$(( $(stat -c %s "$1") / 1048576 )) MB"; }

# Median of the numbers on stdin, one per line (the lower of the two middle ones for an even count).
median() { sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }
