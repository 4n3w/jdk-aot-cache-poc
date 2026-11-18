# 06: The image build, end to end

Puts the findings of 01-04 into an image build and checks the result the way it would run in
production: `JAVA_OPTS` injected at deploy time, an agent attached, a non-root user.

## Run it

```sh
make 06
```

## The two images

[`before/`](before/) is how the application image is built today. [`after/`](after/) adds the AOT
cache. `diff -r before after` shows the whole change:

**`run.sh`**: two changes. `AOT_OPTS` defaults to loading the cache, and the archive path points at
the extracted application.

```sh
exec java $JAVA_OPTS ${AOT_OPTS:--XX:AOTCache=/opt/app/app.aot} \
  --add-opens=... \
  -jar /opt/app/sample-app.war
```

**`Dockerfile`**: two more build steps.

```dockerfile
# 1. Unpack the executable WAR into a thin launcher archive plus lib/*.jar
RUN java -Djarmode=tools -jar /tmp/sample-app.war extract --destination /opt/app

# 2. Training run: start the application, exit after context refresh, write the cache.
RUN JAVA_OPTS="--add-modules=java.instrument,jdk.management.agent -XX:+UseG1GC -Xms999M -Xmx999M -Dspring.context.exit=onRefresh" \
    AOT_OPTS="-XX:AOTCacheOutput=/opt/app/app.aot" \
    /tmp/run.sh
```

Each part of the training step comes from an earlier test:

| Part | Why | Test |
|---|---|---|
| It runs through `run.sh` | Training gets the same `--add-opens` and `--enable-native-access` set as production, and the same archive | [01](../01-option-matching/README.md) |
| `--add-modules=java.instrument,jdk.management.agent` | Stands in for `-javaagent` and `-Dcom.sun.management`, which production passes, without running the agent in the build | [01](../01-option-matching/README.md), [02](../02-java-agent/README.md) |
| `-Xms999M -Xmx999M` | Keeps the training heap below 32 GB whatever the build host's size | [01](../01-option-matching/README.md) |
| No `-XX:CompressedClassSpaceSize` | With the production value, no cache is written | [03](../03-class-space-size/README.md) |
| The WAR is extracted first | More classes come from the cache | [04](../04-executable-war/README.md) |
| `-Dspring.context.exit=onRefresh` | The application exits once its context has been refreshed, which ends the training run | |
| It is a build step | The cache is made from the files in the image, so it always matches them | [01](../01-option-matching/README.md) |

## How the test works

[`test.sh`](test.sh) runs on the host. It copies the sample WAR out of the test image, builds both
images on `aot-poc:base` (the JDK plus the stand-in agent in `/opt/agent`), and then:

1. **Starts the after image with production-style `JAVA_OPTS`** plus `-XX:AOTMode=on` and
   `-Xlog:class+load`: as built (user 1001), as an arbitrary user ID in group 0, and with
   `-Dcom.sun.management.jmxremote` in place of the bare prefix.
2. **Shows what stops the cache being used**: `JAVA_OPTS` without `-javaagent`, `JAVA_OPTS` without
   `-Dcom.sun.management`, and the training step repeated with the production memory options.
3. **Measures startup time** of each image's own `run.sh`, inside the container, in five
   configurations.
4. **Prints the JVM's defaults** for storing compiled code in the cache.

`JAVA_OPTS` is the option set in [`lib/options.sh`](../lib/options.sh).

## What our run showed

Full output: [`results/06-end-to-end.txt`](../results/06-end-to-end.txt).

**The cache is created and used**

The build log has `AOTCache creation is complete: /opt/app/app.aot 58064896 bytes`. The file is owned
by root with mode 644.

| Start | Cache | Classes from the cache | Loaded before the agent started |
|---|---|---|---|
| As built, user 1001 | used | 7,619 of 7,983 | 8,225 |
| User 1000680000, group 0 | used | 7,619 of 7,983 | 8,225 |
| `-Dcom.sun.management.jmxremote` | used | 7,619 of 8,325 | 8,225 |

The cache file needs no change of ownership to be used by another user. With `jmxremote` the JMX
agent starts, and its classes are loaded the normal way because the training run did not start it.

**What stops it**

| Change | Result |
|---|---|
| `JAVA_OPTS` without `-javaagent` | rejected: `Mismatched values for property jdk.module.addmods: runtime jdk.management.agent dump time java.instrument,jdk.management.agent` |
| `JAVA_OPTS` without `-Dcom.sun.management` | rejected: `Mismatched values for property jdk.module.addmods: runtime java.instrument dump time java.instrument,jdk.management.agent` |
| Training with `-XX:CompressedClassSpaceSize=40M` | no cache written, exit code 1: `Unable to allocate from 'ro' region: Please reduce the number of shared classes.` |

The first two mean that every environment that runs the image has to pass both options. One that
leaves either out runs without the cache.

**Startup time**

Median of 5 runs, 2 CPUs, production-style `JAVA_OPTS` with the stand-in agent:

| Configuration | Median |
|---|---|
| before: packed WAR, no cache | 1,062 ms |
| before, plus a cache trained on the packed WAR | 805 ms |
| after with the cache switched off: extracted, no cache | 870 ms |
| **after: extracted, with the cache** | **497 ms** |
| after with the cache rejected (one more `--add-opens` in `JAVA_OPTS`) | 879 ms |

- Extracting and the cache each help, and together they roughly halve the sample application's startup.
- A rejected cache gives no benefit: 879 ms, against 870 ms with the cache switched off. The JVM then
  also goes without the archive built into the JDK ([01](../01-option-matching/README.md)). The
  application starts, so nothing but the `[error][aot]` lines at the top of the log shows it.
- These are times for a small sample application. A real application does more at startup that the
  cache does not shorten, such as reading configuration from remote sources and opening connections.

The time is the wall-clock time of `run.sh`, from process start until the JVM has exited again after
the context was refreshed. The second row trains its own cache inside the before container. The
third row passes `AOT_OPTS=-XX:AOTMode=auto`, which replaces the default `-XX:AOTCache=...` with the
JVM's default behaviour.

**Compiled code in the cache**

JDK 25 has two diagnostic flags, `AOTAdapterCaching` and `AOTStubCaching`, for storing compiled
adapter and stub code in the cache. There are public reports of JVM crashes when a cache that
contains such code is used on a CPU with fewer features than the one that created it. Both flags are
off by default in this JDK build, on arm64 and on x86-64. We did not test moving a cache between
CPU models.

## Checking a real deployment the same way

The checks in step 1 need nothing from this repository:

1. The image build log contains `AOTCache creation is complete`.
2. Add `-XX:AOTMode=on` to `JAVA_OPTS` once, in a test environment. If the application starts, the
   cache was accepted. Leave the default mode in production, so that a mismatch costs startup time
   and not availability.
3. Add `-Xlog:class+load` once and count the lines that end in `source: shared objects file`.

## What this does not show

- **The real agent.** The stand-in reports that 8,225 classes were loaded before it started. Whether
  a monitoring agent still reports everything it should in that situation has to be checked with
  that agent. See [02](../02-java-agent/README.md).
- **The real application's training run.** The sample starts with nothing but the JDK. An application
  that needs configuration servers, secrets or a data grid at startup needs a way to start during an
  image build, such as a build-time profile. [05](../05-gemfire-client/README.md) shows that a
  GemFire client can be trained with no cluster reachable.
