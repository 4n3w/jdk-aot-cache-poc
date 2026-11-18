# 01: What has to match between training and production

The JVM records how the training run was started and compares the production run against it. If
something that matters is different, it refuses the whole cache. This test finds out what matters.

## Run it

```sh
make 01
```

## How it works

[`test.sh`](test.sh) runs 26 cases on the three-class [`plain-app`](../plain-app/). Each case:

1. trains a cache with one set of options: `java <training options> -XX:AOTCacheOutput=<cache> -cp plain-app.jar demo.Main`
2. optionally changes something, such as the jar's timestamp
3. starts the application with another set: `java <production options> -XX:AOTCache=<cache> -XX:AOTMode=on -cp plain-app.jar demo.Main`

The case prints both option sets, whether the cache was used, and either the number of classes that
came from it or the JVM's reason for refusing it.

A last section repeats one rejected case without `-XX:AOTMode=on`, which is how production would
normally run, to show what a rejection looks like there.

## What our run showed

Full output: [`results/01-option-matching.txt`](../results/01-option-matching.txt).

**The set has to match**

| Training | Production | Cache |
|---|---|---|
| `--add-opens` set | the same set, same or different order | used |
| `--add-opens` set | none, or one more | rejected |
| none | `--add-opens` set | rejected |
| `--enable-native-access=ALL-UNNAMED` | the same | used |
| none | `--enable-native-access=ALL-UNNAMED` | rejected |

```
Mismatched values for property jdk.module.addopens: ... specified during runtime but not during dump time
Mismatched values for property jdk.module.enable.native.access: ALL-UNNAMED specified during runtime but not during dump time
```

**The added JDK modules have to match**

`-javaagent` adds the module `java.instrument`. Any system property that starts with
`-Dcom.sun.management` adds `jdk.management.agent`, even with nothing after the prefix.

| Training | Production | Cache |
|---|---|---|
| `-javaagent` | `-javaagent` | used |
| none | `-javaagent` | rejected |
| `-javaagent` | none | rejected |
| `--add-modules=java.instrument` | `-javaagent` | used |
| none | `-Dcom.sun.management.jmxremote`, or `-Dcom.sun.management` alone | rejected |
| `-Dcom.sun.management.jmxremote` | none | rejected |
| `--add-modules=java.instrument,jdk.management.agent` | `-javaagent` and `-Dcom.sun.management` | used |

```
Mismatched values for property jdk.module.addmods: java.instrument specified during runtime but not during dump time
Mismatched values for property jdk.module.addmods: jdk.management.agent specified during runtime but not during dump time
```

The `--add-modules` rows are what make it possible to train without running the agent. 06 uses that.

**These do not have to match**

| Difference | Cache |
|---|---|
| `--sun-misc-unsafe-memory-access=allow` in production only | used |
| Production memory and GC options (999 MB heap, G1 tuning, 40M class space, 256M Metaspace limit, code cache, stack size) against training defaults | used |
| Ordinary `-D` system properties in production only | used |
| Serial GC in one run, G1 in the other, either way round | used |
| Training with 1 CPU and a 256 MB heap | used |

**Heap size matters in one case**

A cache trained with a heap above 32 GB is rejected by a production run with a heap below it, because
the JVM stores object references differently above that size:

```
The saved state of UseCompressedOops and UseCompressedClassPointers is different from runtime, CDS will be disabled.
```

A training run with no `-Xmx` takes a quarter of the build host's memory as its maximum heap, which is
above 32 GB on a host with more than 128 GB. Giving the training run an explicit `-Xmx` avoids that.

**The application archive has to be the same file**

| After training | Cache |
|---|---|
| Timestamp of the jar changed | rejected |
| Jar rebuilt with one more entry | rejected |
| Same jar run from another directory, file name and timestamp kept | used |
| Same jar under another file name | rejected |

```
This file is not the one used while building the AOT cache: '.../app.jar', timestamp has changed, size has changed
The name of app classpath [1] does not match: expected '.../app.jar', got '.../renamed.jar'
```

**A rejected cache does not stop the application**

Without `-XX:AOTMode=on`, the same rejection prints five `[error][aot]` lines and the application
runs normally, with exit code 0. It runs with no class archive at all, which is less than a JVM
started with no AOT option gets:

```
Classes loaded from an archive, out of all classes loaded:
  cache accepted:        890 of 891
  cache rejected:        0 of 851
  no AOT option:         821 of 844 (from the JDK's built-in archive)
```

06 measures what that costs in startup time.
