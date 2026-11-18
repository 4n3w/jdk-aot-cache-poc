#!/bin/bash
# 02: what does a Java agent get to see when the AOT cache is in use?
#
# The plain application runs with the stand-in agent, which reports each demo.* class the JVM offers
# to its class-file hook. Runs inside the test image: make 02
. /poc/lib/common.sh

APP="-cp $FIXTURES/plain-app.jar demo.Main"

agent_lines() { grep '^\[agent\]' "$1" | sed 's/^/      /'; }

# How many demo.* classes the agent found loaded before it started, and how many of them the JVM
# offered to its hook as they loaded.
before_agent() { grep -c 'loaded before the agent started: demo\.' "$1"; }
at_load_time() { grep -c 'hook offered demo\..* at load time' "$1"; }

section "1. No cache: the agent sees every application class as it loads"
java -javaagent:$AGENT $APP >"$WORK/1.out" 2>&1
agent_lines "$WORK/1.out"
expect "loaded before agent:" "$(before_agent "$WORK/1.out") demo.* classes" "0 demo.* classes"
expect "offered at load time:" "$(at_load_time "$WORK/1.out") demo.* classes" "3 demo.* classes"

section "2. Cache trained with the agent, production with the agent"
train "$WORK/2.aot" -javaagent:$AGENT $APP || echo "    TRAINING FAILED: $(jvm_reason "$WORK/2.aot.train.log")"
production "$WORK/2.aot" -javaagent:$AGENT $APP
agent_lines "$WORK/2.aot.run.log"
expect "loaded before agent:" "$(before_agent "$WORK/2.aot.run.log") demo.* classes" "4 demo.* classes"
expect "offered at load time:" "$(at_load_time "$WORK/2.aot.run.log") demo.* classes" "0 demo.* classes"
show "classes from cache:" "$(from_cache "$WORK/2.aot.classes.log") of $(loaded "$WORK/2.aot.classes.log")"

section "3. The same cache, and the agent retransforms the classes it missed"
production "$WORK/2.aot" -javaagent:$AGENT=retransform,rewrite=demo.Service $APP
agent_lines "$WORK/2.aot.run.log"
expect "offered again:" "$(grep -c 'hook offered demo\..* by retransformation' "$WORK/2.aot.run.log") demo.* classes" "3 demo.* classes"
expect "rewritten:" "$(grep -c 'hook rewrote demo\.Service' "$WORK/2.aot.run.log") class" "1 class"
expect "application:" "$(grep -c '^app ran' "$WORK/2.aot.run.log") run completed" "1 run completed"

section "4. The agent rewrites demo.Service during training as well as in production"
train "$WORK/4.aot" -javaagent:$AGENT=rewrite=demo.Service $APP || echo "    TRAINING FAILED: $(jvm_reason "$WORK/4.aot.train.log")"
echo "    Training run, what the JVM left out of the cache because of the agent:"
grep 'ClassFileLoadHook' "$WORK/4.aot.train.log" | sed -E 's/^(\[[^]]*\])+ ?//; s/^/      /'
expect "left out of cache:" "$(grep -c 'Skipping demo/Service: From ClassFileLoadHook' "$WORK/4.aot.train.log") class" "1 class"
production "$WORK/4.aot" -javaagent:$AGENT=rewrite=demo.Service $APP
echo "    Production run:"
agent_lines "$WORK/4.aot.run.log"
expect "loaded before agent:" "$(before_agent "$WORK/4.aot.run.log") demo.* classes" "3 demo.* classes"
expect "offered at load time:" "$(at_load_time "$WORK/4.aot.run.log") demo.* classes" "1 demo.* classes"
expect "rewritten:" "$(grep -c 'hook rewrote demo\.Service' "$WORK/4.aot.run.log") class" "1 class"

section "5. Cache trained without the agent (--add-modules=java.instrument), production with it"
train "$WORK/5.aot" --add-modules=java.instrument $APP || echo "    TRAINING FAILED: $(jvm_reason "$WORK/5.aot.train.log")"
if production "$WORK/5.aot" -javaagent:$AGENT $APP; then result=used; else result=rejected; fi
expect "cache:" "$result" "used"
agent_lines "$WORK/5.aot.run.log"
expect "loaded before agent:" "$(before_agent "$WORK/5.aot.run.log") demo.* classes" "4 demo.* classes"
expect "offered at load time:" "$(at_load_time "$WORK/5.aot.run.log") demo.* classes" "0 demo.* classes"

section "6. The agent appends a jar to the bootstrap class path"
if production "$WORK/2.aot" -javaagent:$AGENT=appendboot=/opt/agent/agent-boot.jar $APP; then result=used; else result=rejected; fi
agent_lines "$WORK/2.aot.run.log"
echo "    JVM output:"
grep -E 'VM warning|^\[[^]]*\]\[(error|warning)' "$WORK/2.aot.run.log" | sed 's/^/      /'
expect "cache:" "$result" "used"
expect "loaded before agent:" "$(before_agent "$WORK/2.aot.run.log") demo.* classes" "4 demo.* classes"
expect "application:" "$(grep -c '^app ran' "$WORK/2.aot.run.log") run completed" "1 run completed"
show "classes from cache:" "$(from_cache "$WORK/2.aot.classes.log") of $(loaded "$WORK/2.aot.classes.log")"

finish
