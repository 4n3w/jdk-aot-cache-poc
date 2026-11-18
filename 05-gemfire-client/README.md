# 05: GemFire client

Checks that a GemFire Java client works when it is started from an AOT cache, how much of GemFire
comes out of the cache, and whether the training run needs a cluster.

## Run it

```sh
make 05 ACCEPT_TERMS=y
```

The GemFire image requires accepting the
[Broadcom terms](https://www.broadcom.com/company/legal/licensing). The test does nothing until you
pass `ACCEPT_TERMS=y`. `GEMFIRE_IMAGE` selects the image (default `gemfire/gemfire:10.3.2-jdk17`).

## How it works

[`test.sh`](test.sh) runs on the host:

1. It builds a client image from the test image ([`Dockerfile`](Dockerfile)). The GemFire jars are
   copied out of the GemFire image and the client is compiled against them.
2. It starts a cluster in a container, with one locator, one server and a partitioned region `demo`.
3. It runs [`client-test.sh`](client-test.sh) in the client image, on the same Docker network.
4. It removes the cluster and the network.

The [client](src/demo/GemFireClient.java) does what a client application does at startup. It creates
a `ClientCache` with a locator pool, subscriptions and the reflection-based PDX auto-serializer,
creates a proxy region, registers interest in all keys, puts 20 objects and reads one back. It prints
how long cache and region creation took, and how long the operations took.

`client-test.sh` runs it:

1. without a cache
2. with a cache trained against the live cluster
3. with a cache trained with **no cluster reachable**, where the locator address points at a port
   nothing listens on. The cache and region are still created, and the operations fail
4. five times each way, for the median startup time
5. in training runs at `-XX:CompressedClassSpaceSize=40M`, `48M` and `64M`

The client runs on JDK 25 with the production memory options and the `--add-opens` set from
`client-test.sh`. Training runs leave out `-XX:CompressedClassSpaceSize`.

## What our run showed

Full output: [`results/05-gemfire-client.txt`](../results/05-gemfire-client.txt).

| Run against the live cluster | Operations | GemFire classes from the cache | `ClientCache` and region creation | Whole JVM |
|---|---|---|---|---|
| No cache | worked | | 747 ms | 810 ms |
| Cache trained against the live cluster | worked | 2,555 of 2,555 | 313 ms | 398 ms |
| Cache trained with no cluster reachable | worked | 2,405 of 2,559 | 316 ms | 426 ms |

- **The client works from the cache.** Connecting, registering interest, puts, the get and PDX
  serialization all worked.
- **GemFire's classes come from the cache.** All of them after live training.
- **Training does not need a cluster.** The cache trained with nothing to connect to still held 94%
  of the GemFire classes used against the live cluster, and cache and region creation took the same
  time. The classes it lacks are loaded the normal way.
- **Training against a cluster makes the build a real client.** That training run registered a PDX
  type and wrote 20 entries. A build that trains this way should use a cluster where that is acceptable.
- **The class-space limit applies here too.** Training the client alone fails at 40M and 48M and
  works at 64M, as in [03](../03-class-space-size/README.md).

The cache shortens class loading and initialization. It does not shorten network work such as
locator discovery, connection setup or the initial register-interest transfer, which is small here
because the cluster is local and nearly empty.

## What this does not show

Whether a given GemFire version is supported on Java 25. The test shows how the 10.3.2 client
behaves there.
