# Conclusions

**Setup:** Oracle JDK 25.0.5.0.3 on Oracle Linux 9.8 in a container, linux/arm64, 2 CPUs per container, median of 5 runs, 2026-11-18. Sample Spring Boot 4.1.1 WAR, stand-in Java agent, GemFire 10.3.2 client. The outcomes of 01-04 and 06 were the same on linux/amd64 under emulation. [README.md](README.md) has the details and the raw output.

## Short version

- **The cache can be built into the image and is used at runtime.** With two extra build steps, the sample application started with production-style `JAVA_OPTS`, an agent attached and a non-root user, and loaded 7,619 of its 7,983 classes from the cache.
- **GemFire is not an obstacle.** The client worked from the cache, every GemFire class it used came from the cache, and the training run did not need a cluster.
- **The startup command is where it goes wrong.** A production-style option set, used unchanged, either stops the cache from being written or gets it rejected at runtime. The fix is in how the training run is started, not in the production options.
- **A rejected cache is silent.** The application starts as usual and gains nothing.
- **The agent needs a check with the real thing.** With the cache, classes are loaded before a Java agent starts. A stand-in agent can show that, but not how a particular monitoring agent copes with it.

## The numbers

| Measurement | Without the cache | With the cache | Test |
|---|---|---|---|
| Sample application startup, image as built today against image with extraction and cache | 1,062 ms | 497 ms | 06 |
| GemFire `ClientCache` and region creation | 747 ms | 313 ms | 05 |
| GemFire client, whole JVM run | 810 ms | 398 ms | 05 |
| Metaspace committed | 26.9 MB | 2.7 MB | 03 |
| Native memory committed, all categories | 1,146.0 MB | 1,138.8 MB | 03 |

Where the startup time goes, for the sample application (06):

| Configuration | Startup |
|---|---|
| Packed WAR, no cache (today) | 1,062 ms |
| Packed WAR, with a cache | 805 ms |
| Extracted, no cache | 870 ms |
| **Extracted, with the cache** | **497 ms** |
| Extracted, cache rejected | 879 ms |

These are small sample applications. The numbers show the direction and relative size of the effect, not what a real application will gain.

## What we conclude, and from which test

**1. A GemFire client works from the cache and can be trained without a cluster (05)**

- **It works.** Connecting, registering interest, puts, a get and PDX auto-serialization all worked with the cache in use.
- **GemFire's classes are cached.** 2,555 of 2,555 after training against a live cluster.
- **No cluster is needed at build time.** A cache trained with nothing to connect to held 2,405 of the 2,559 GemFire classes used later, and `ClientCache` and region creation took 316 ms against 313 ms.

**2. The cache is all or nothing, and the command line decides (01)**

- **Has to match between training and production:**
  - the `--add-opens` and `--enable-native-access` sets, in any order;
  - the JDK modules that options add behind the scenes: `java.instrument` for `-javaagent`, `jdk.management.agent` for any `-Dcom.sun.management...` property;
  - the application archive: same file name, size and timestamp.
- **Does not have to match:** GC choice and tuning, heap and other size options, ordinary `-D` properties, `--sun-misc-unsafe-memory-access`. The one exception is a heap above 32 GB in one run and below it in the other.
- **One difference rejects everything.** The JVM then loads no class from the cache at all.

**3. Three options in a production-style set get in the way (01, 03, 06)**

| Option | What it does | What to do in the training run |
|---|---|---|
| `-XX:CompressedClassSpaceSize=40M` | The training run cannot write its cache. It failed at 40M and 48M and worked at 64M, for the sample application and for the GemFire client alone. The option is harmless at runtime | Leave it out |
| `-javaagent` | Adds `java.instrument`. The cache is rejected if only one of the two runs has it | Pass the agent too, or pass `--add-modules=java.instrument` |
| `-Dcom.sun.management...` | Adds `jdk.management.agent`, with the same effect | Pass it too, or pass `--add-modules=jdk.management.agent` |

**4. A rejected cache is easy to miss (01, 06)**

- **The application still starts.** Exit code 0, and five `[error][aot]` lines at the top of the log.
- **It gains nothing.** Startup was 879 ms, against 870 ms with no cache at all. The JVM also goes without the class archive built into the JDK.
- **`-XX:AOTMode=on` makes it visible.** The JVM then refuses to start without the cache, which is what a test environment wants and production does not.

**5. With the cache, classes are loaded before a Java agent starts (02, 06)**

- **The agent's load-time hook misses them.** In 06, 8,225 classes were already loaded when the stand-in agent started. In 02, none of the application's cached classes were offered to its hook as they loaded.
- **Retransformation still reaches them.** The JVM offered every class the agent asked for, within the usual limits of retransformation.
- **Training with the agent changes the picture.** A class the agent rewrites during training is left out of the cache and goes through the hook at load time, as it does today.

**6. Extract the WAR first (04, 06)**

- **Packed works in part.** 3,033 of 3,886 WAR classes came from the cache, and startup was 805 ms.
- **Extracted works almost fully.** 4,363 of 4,396, and 497 ms.
- **Two layouts cannot be used.** Spring Boot's `extract` fails on a WAR with `WEB-INF/lib-provided/`, and a training run fails with a directory on the class path.

**7. The existing memory limits are fine at runtime (03)**

- **Metaspace use falls**, from 26.9 MB to 2.7 MB, because class metadata is read from the mapped cache file.
- **Total native memory is about the same**, 1,146.0 MB against 1,138.8 MB.

## What follows for the image build

[`06-end-to-end/after`](../06-end-to-end/after/) is the result. Compared with the image as built today:

1. **Extract the WAR** with `java -Djarmode=tools -jar <war> extract`.
2. **Train in a build step, through the same `run.sh` as production**, so the `--add-opens` set and the archive cannot differ. Give it `--add-modules=java.instrument,jdk.management.agent`, an explicit `-Xmx`, and no `-XX:CompressedClassSpaceSize`.
3. **Let `run.sh` default to `-XX:AOTCache=<file>`.** `JAVA_OPTS` stays as it is, as long as every environment passes both `-javaagent` and `-Dcom.sun.management...`.

## What these runs do not establish

- **How a particular monitoring agent behaves** when classes are loaded before it starts. That needs a comparison of what it reports with and without the cache.
- **What a real application gains,** or whether it can start during an image build without its configuration sources and data grid.
- **Whether a given GemFire version is supported on Java 25.** 05 shows how the 10.3.2 client behaves.
- **Timing on x86-64.** That run was emulated, so only its outcomes count. 05 was not run there.
- **Moving a cache between CPU models.** The JVM flags that would put compiled code in the cache are off by default in this JDK build, and we did not test further.
- **Other JDK builds.** `make all JDK_IMAGE=<image>` repeats the tests on another one and marks any outcome that differs.
