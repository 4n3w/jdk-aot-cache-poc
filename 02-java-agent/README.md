# 02: What a Java agent sees when the cache is in use

A monitoring agent instruments classes through a class-file hook: the JVM offers it each class as
the class is loaded, and the agent may hand back changed bytes. This test checks what happens to
that hook when classes come out of the AOT cache.

## Run it

```sh
make 02
```

## How it works

[`test.sh`](test.sh) runs the three-class [`plain-app`](../plain-app/) with the
[`stand-in-agent`](../stand-in-agent/src/agent/StandInAgent.java). The agent prints:

- how many classes were already loaded when it started, and which of them are `demo.*`
- each `demo.*` class the JVM offers to its hook, and whether that was at load time or by retransformation
- a total when the JVM exits

Its options make it behave like an instrumenting agent: `rewrite=CLASS` hands the JVM new bytes for
a class, `retransform` asks the JVM to offer the already-loaded classes again, and `appendboot=JAR`
appends a jar to the bootstrap class path.

## What our run showed

Full output: [`results/02-java-agent.txt`](../results/02-java-agent.txt).

| Case | Loaded before the agent started | Offered to the hook at load time |
|---|---|---|
| 1. No cache | none of the `demo.*` classes | all 3 |
| 2. Cache trained with the agent, production with the agent | all 4 | none |
| 4. Agent rewrites `demo.Service` in training and production | 3 | `demo.Service` only |
| 5. Cache trained without the agent, using `--add-modules=java.instrument` | all 4 | none |

The fourth class in cases 2 and 5 is the hidden class behind the lambda in `Main`, which is in the
cache as well.

- **Cached classes are loaded before the agent starts (case 2).** With the cache, the JVM loads the
  cached classes during its own startup, before it calls the agent. The hook is never offered them.
- **Retransformation still reaches them (case 3).** When the agent asks for the three classes to be
  retransformed, the JVM offers each one to the hook, the agent rewrites `demo.Service`, and the
  application runs. The JVM limits what retransformation may change: method bodies, but not the set
  of fields or methods.
- **A class the agent rewrites during training stays out of the cache (case 4).** The training run
  logs `Skipping demo/Service: From ClassFileLoadHook`. In production that class is loaded the normal
  way and goes through the hook at load time, as it would without a cache.
- **Training without the agent leaves nothing out (case 5).** The cache is accepted with the agent
  in production, and every class is loaded before the agent starts.
- **Appending to the bootstrap class path only warns (case 6).** The JVM prints `Sharing is only
  supported for boot loader classes because bootstrap classpath has been appended`. The cache stays
  in use, and the application runs.

## What this does not show

The stand-in agent shows what the JVM offers to any agent. It cannot show what a particular
monitoring agent does about it: whether it retransforms classes that were loaded before it started,
and whether everything it normally instruments can be instrumented that way. That needs a run with
the real agent, comparing what it reports with and without the cache.

Cases 4 and 5 are the two ways to train. Training with the real agent keeps the classes it
instruments out of the cache, so they are instrumented at load time as before. Training without it
caches everything and relies on retransformation.
