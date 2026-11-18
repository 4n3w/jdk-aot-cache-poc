#!/bin/sh
# Median wall-clock time, in milliseconds, of a command that starts the application and exits.
#
#   startup-time.sh <runs> <command...>
#
# Two warm-up runs come first and are not counted. If PREPARE is set, it runs once before them as a
# shell command (a training run, for example). Prints "<median> ms   (runs: ...)".
#
# The script depends on nothing else, so it can be piped into an image that does not contain it:
#   docker run -i --entrypoint sh <image> -s -- 5 /tmp/run.sh < startup-time.sh
runs=$1; shift

if [ -n "${PREPARE:-}" ]; then
  if ! sh -c "$PREPARE" >/tmp/prepare.log 2>&1 </dev/null; then
    echo "prepare step failed: $(tail -n 3 /tmp/prepare.log)"
    exit 1
  fi
fi

times=""
i=-2
while [ "$i" -lt "$runs" ]; do
  start=$(date +%s%N)
  "$@" >/dev/null 2>&1 </dev/null
  code=$?
  end=$(date +%s%N)
  if [ "$code" -ne 0 ]; then
    echo "run failed with exit code $code"
    exit 1
  fi
  if [ "$i" -ge 0 ]; then
    times="$times $(( (end - start) / 1000000 ))"
  fi
  i=$((i + 1))
done

median=$(printf '%s\n' $times | sort -n | sed -n "$(( (runs + 1) / 2 ))p")
echo "$median ms   (runs:$times)"
