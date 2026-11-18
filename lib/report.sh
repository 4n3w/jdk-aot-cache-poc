# How the test scripts print results. Sourced by all of them, inside the test image and on the host.

DIFFERS=0   # outcomes that were not what our run gave

section() { printf '\n== %s\n' "$*"; }
show()    { printf '    %-24s %s\n' "$1" "$2"; }

# expect <label> <observed> <in our run>
# A result line, marked when the outcome is not the one our run gave (see results/ in the repo).
# Only outcomes are compared. Class counts, sizes and times vary by JDK build and machine.
expect() {
  if [ "$2" = "$3" ]; then
    show "$1" "$2"
  else
    show "$1" "$2   <-- differs from our run: $3"
    DIFFERS=$((DIFFERS + 1))
  fi
}

finish() {
  echo
  if [ "$DIFFERS" -eq 0 ]; then
    echo "All outcomes match our run."
  else
    echo "$DIFFERS outcome(s) differ from our run, marked with <--."
  fi
  exit $((DIFFERS > 0))
}

# jvm_reason <log>
# The JVM's own explanation for refusing a cache or failing to write one. It prints the specific
# reason among several generic lines, sometimes as an error and sometimes as a warning, so this takes
# the first [aot] error that is not generic, or failing that the first such warning.
jvm_reason() {
  local strip='s/^(\[[^]]*\])+ ?//'
  local generic='An error has occurred|Disabling optimized module handling|aot-linked classes|Unable to map shared spaces|shared class paths mismatch|unrecoverable error|Unable to use AOT cache|Loading static archive failed|^\[[a-z]+ *\] 0x|^ *required = '
  local reason
  reason=$(grep -E '^\[[^]]*\]\[error *\]\[aot' "$1" | sed -E "$strip" | grep -vE "$generic" | head -n 1)
  if [ -z "$reason" ]; then
    reason=$(grep -E '^\[[^]]*\]\[warning *\]\[aot|^\[ +\]' "$1" | sed -E "$strip" |
      grep -vE "$generic|^Skipping |^Preload Warning" | head -n 1)
  fi
  echo "${reason:-(no reason found in the JVM output)}"
}

# Counts from a class-load log (-Xlog:class+load). "shared objects file" is how the JVM names a
# class that came out of an archive: the AOT cache if one is in use, otherwise the small archive
# built into the JDK.
loaded()     { grep -c 'source:' "$1"; }
from_cache() { grep -c 'source: shared objects file' "$1"; }
