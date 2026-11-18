# 03: CompressedClassSpaceSize and Metaspace

The production option set limits the compressed class space to 40M and Metaspace to 256M. This test
checks what those limits do to a training run and to a production run that uses the cache.

## Run it

```sh
make 03
```

## How it works

[`test.sh`](test.sh) uses the sample Spring Boot application, extracted (see
[04](../04-executable-war/README.md)):

1. It trains at `-XX:CompressedClassSpaceSize=40M`, `48M`, `64M` and with no option, and reports
   whether a cache was written.
2. It starts the application with the cache trained without the option and the full production
   memory options, including `-XX:CompressedClassSpaceSize=40M -XX:MaxMetaspaceSize=256M`.
3. It starts the application with and without the cache under Native Memory Tracking
   (`-XX:NativeMemoryTracking=summary -XX:+PrintNMTStatistics`) and prints what the JVM had
   committed for class metadata when it exited.

## What our run showed

Full output: [`results/03-class-space-size.txt`](../results/03-class-space-size.txt).

**Training**

| `-XX:CompressedClassSpaceSize` | Training run |
|---|---|
| `40M` | No cache written, exit code 1 |
| `48M` | No cache written, exit code 1 |
| `64M` | Cache written, 54 MB |
| not set (default 1 GB) | Cache written, 54 MB |

The application itself starts normally in the failing runs. The failure comes afterwards, while the
JVM assembles the cache:

```
Unable to allocate from 'ro' region: Please reduce the number of shared classes.
An error has occurred while writing the shared archive file.
```

This JDK build rounds 40M up to 48M (`CompressedClassSpaceSize adjusted from user input 41943040
bytes to 50331648 bytes`), which is why the two behave alike. The size needed grows with the number
of classes, so a larger application needs more than this sample does. The GemFire client alone fails
at the same sizes (see [05](../05-gemfire-client/README.md)). Leaving the option out of the training
run avoids having to find the threshold.

**Production**

A cache trained without the option is used by a production run that has it: 7,608 of 7,894 classes
came from the cache.

**Memory**

| Committed at exit, MB | Without cache | With cache |
|---|---|---|
| Metaspace | 26.9 | 2.7 |
| Shared class space | 13.7 | 51.2 |
| Total, all categories | 1,146.0 | 1,138.8 |

Metaspace holds the class metadata the JVM builds at runtime, and it is what `-XX:MaxMetaspaceSize`
limits. With the cache most of that metadata is read from the mapped cache file instead, which the
JVM counts as shared class space. The total is about the same. The existing limits therefore have
more headroom with the cache, not less.
