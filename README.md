# JDK 25 AOT cache: testing a container startup command

These are the tests behind our review of a container startup command for use with the JDK 25 AOT
cache (`-XX:AOTCacheOutput` to create it, `-XX:AOTCache` to use it). The application under review is
a Spring Boot executable WAR with a GemFire client. Its `run.sh` starts it with `java $JAVA_OPTS ...
-jar`, and the platform injects `JAVA_OPTS`, including a monitoring agent, at deploy time.

We did not have the application, its agent or its base image. Everything here runs on stand-ins that
anyone can build and read: a sample WAR, a stand-in agent, a small GemFire client and a
production-style option set. [The stand-ins](#the-stand-ins) says what they can and cannot show.

One folder per question:

| Folder | Question | What our run showed |
|---|---|---|
| [`01-option-matching`](01-option-matching/README.md) | What has to be the same in the training run and the production run? | The `--add-opens` and `--enable-native-access` sets, the JDK modules that `-javaagent` and `-Dcom.sun.management...` add, and the application archive. Heap, GC and ordinary `-D` options do not. A rejected cache does not stop the application |
| [`02-java-agent`](02-java-agent/README.md) | What does a Java agent get to see when the cache is in use? | Cached classes are loaded before the agent starts, so its load-time hook never sees them. Retransformation still reaches them |
| [`03-class-space-size`](03-class-space-size/README.md) | What do `-XX:CompressedClassSpaceSize=40M` and `-XX:MaxMetaspaceSize=256M` do? | A training run with 40M cannot write its cache. At runtime the option is harmless, and Metaspace use falls from 27 MB to 3 MB |
| [`04-executable-war`](04-executable-war/README.md) | Does the cache work with an executable WAR? | Partly when packed (3,033 of 3,886 WAR classes from the cache), almost fully when extracted (4,363 of 4,396). Spring Boot's `extract` fails on a WAR with `WEB-INF/lib-provided/` |
| [`05-gemfire-client`](05-gemfire-client/README.md) | Does a GemFire client work with the cache? | Yes. All 2,555 GemFire classes came from the cache, and `ClientCache` and region creation went from 747 ms to 313 ms. Training with no cluster reachable is nearly as good |
| [`06-end-to-end`](06-end-to-end/README.md) | Does it all hold together in an image build? | Yes. Two extra build steps create the cache, production-style `JAVA_OPTS` use it, and sample-application startup goes from 1,062 ms to 497 ms |

**Short version:** [`results/CONCLUSIONS.md`](results/CONCLUSIONS.md) has what we conclude and the
numbers behind it. The full output of our run is in [`results/`](results/README.md).

## How the tests work

The AOT cache takes two runs. A **training run** starts the application once and writes the cache
file as it exits. Every later **production run** loads that file. Most of what can go wrong is a
difference between those two runs, so most tests train one way and run another.

- **Used or rejected.** Production runs in the tests pass `-XX:AOTMode=on`. With it the JVM exits
  instead of carrying on without the cache, so the exit code is the JVM's own verdict.
- **How much came from the cache.** `-Xlog:class+load` logs the source of every class. The tests
  count the lines that end in `source: shared objects file`.
- **Why.** Lines labelled `JVM:` are the JVM's own message, with its log prefix removed.
- **Compared with our run.** Each test knows the outcome our run gave (used, rejected, cache written
  and so on) and marks a different one with `<--`. A test that finds one exits with code 1. Class
  counts, sizes and times are printed but not compared, because they vary by JDK build and machine.
- **Startup time.** The wall-clock time of the process, from start until it has exited again.
  Spring Boot's `-Dspring.context.exit=onRefresh` makes the application exit as soon as its context
  has been refreshed. Each figure is the median of `RUNS` runs after warm-up runs, measured inside
  a container limited to `CPUS` CPUs.

The helpers that do this are short: [`lib/common.sh`](lib/common.sh) has `train` and `production`,
[`lib/report.sh`](lib/report.sh) the counting and reporting, and
[`lib/startup-time.sh`](lib/startup-time.sh) the timing.

## The stand-ins

| Stand-in | What it is | What it cannot show |
|---|---|---|
| [`sample-app`](sample-app/) | A minimal Spring Boot 4.1.1 web application (Spring MVC, embedded Tomcat, Actuator) built as an executable WAR, with and without `WEB-INF/lib-provided/` | How long a real application takes to start, or how much of that the cache removes. The numbers show the direction and relative size of the effect |
| [`stand-in-agent`](stand-in-agent/) | A Java agent that reports which classes were loaded before it started and which ones the JVM offers to its class-file hook. On request it rewrites a class, retransforms classes, or appends a jar to the bootstrap class path | Whether a particular monitoring agent keeps full visibility when classes are loaded before it starts. That has to be tested with that agent |
| [`plain-app`](plain-app/) | Three classes that start in tens of milliseconds, for the tests that train and run many times | Anything about frameworks |
| [`05-gemfire-client/src`](05-gemfire-client/src/demo/GemFireClient.java) | A GemFire 10.3.2 Java client: `ClientCache`, locator pool, subscriptions, register interest, puts and a get with PDX auto-serialization, against a one-server cluster | Whether a given GemFire version is supported on Java 25. The test shows behaviour, not support status |
| [`lib/options.sh`](lib/options.sh) | A production-style option set: G1, a 999 MB heap, 40M class space, 256M Metaspace limit, system properties, `-javaagent` and `-Dcom.sun.management` | |

## Running

Everything runs in containers, from the repo root through `make` (`make` alone lists the targets):

| Command | What it does |
|---|---|
| `make image` | Builds the test images: the JDK plus the stand-in agent (`aot-poc:base`), and that plus the sample applications and test scripts (`aot-poc:tools`). Every test target does this first |
| `make 01` ... `make 04` | Run one test inside the test image |
| `make 05 ACCEPT_TERMS=y` | Builds a client image with the GemFire jars, starts a one-server GemFire cluster in a container, runs the client test, removes the cluster |
| `make 06` | Builds the `before` and `after` application images and tests them |
| `make all` | 01-04 and 06, plus 05 when `ACCEPT_TERMS=y` is given |
| `make clean` | Removes the images, the test cluster and the files the tests copied or logged |

Settings you can pass:

- **`JDK_IMAGE`**: the JDK the tests run on (default `container-registry.oracle.com/java/jdk-no-fee-term:25`).
  Point it at your own base image to repeat the tests on your JDK build. It needs a full JDK 25,
  because the sample applications are compiled in it.
- **`PLATFORM`**: for example `linux/amd64`. Empty means this machine's architecture.
- **`RUNS`** (default 5) and **`CPUS`** (default 2): timed runs per measurement, and CPUs per container.
- **`ACCEPT_TERMS=y`** and **`GEMFIRE_IMAGE`** (default `gemfire/gemfire:10.3.2-jdk17`): for 05. The
  GemFire image requires accepting the [Broadcom terms](https://www.broadcom.com/company/legal/licensing),
  so the test does not run until you pass `ACCEPT_TERMS=y`.

## Prerequisites

| For | Needs |
|---|---|
| Everything | Docker with BuildKit, GNU Make, bash |
| The first `make image` | Network access to the JDK image's registry, `services.gradle.org` and Maven Central, to build the sample WAR |
| 05 | Access to the GemFire image. No GemFire jars are stored in this repository; they are copied out of that image at build time |

## Our run

Oracle JDK 25.0.5.0.3 (build 25.0.5.0.3+1-LTS-2) on Oracle Linux 9.8 in a container, linux/arm64,
2 CPUs per container, 2026-11-18. The outcomes of 01-04 and 06 were the same on linux/amd64 under
emulation. See [`results/`](results/README.md).

## Layout

```
Makefile              make targets for everything below
Dockerfile            the test images: base (JDK + stand-in agent) and tools (+ sample applications, tests)
lib/                  options.sh (production-style options), common.sh, report.sh, startup-time.sh
plain-app/            three-class Java application
stand-in-agent/       the stand-in Java agent and its bootstrap helper jar
sample-app/           the sample Spring Boot executable WAR (Gradle; -PprovidedTomcat for the second variant)
01-option-matching/   test.sh, runs in the test image
02-java-agent/        test.sh, runs in the test image
03-class-space-size/  test.sh, runs in the test image
04-executable-war/    test.sh, runs in the test image
05-gemfire-client/    test.sh (host: cluster up, run, cluster down), client-test.sh, Dockerfile, client source
06-end-to-end/        test.sh (host), before/ and after/ with a Dockerfile and run.sh each
results/              the output of our run
```
