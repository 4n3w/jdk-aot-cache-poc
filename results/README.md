# Results of our run

The unedited output of each test, as printed by `make 01` ... `make 06`.

| | |
|---|---|
| Date | 2026-11-18 |
| JDK | Oracle JDK 25.0.5.0.3 (build 25.0.5.0.3+1-LTS-2), image `container-registry.oracle.com/java/jdk-no-fee-term:25` |
| OS | Oracle Linux 9.8, in a container |
| Architecture | linux/arm64 (Docker Desktop on an Apple Silicon Mac) |
| Settings | `RUNS=5`, `CPUS=2` |
| GemFire (05) | `gemfire/gemfire:10.3.2-jdk17`, one locator and one server in a container |
| Sample application | Spring Boot 4.1.1 |

| Test | Output |
|---|---|
| 01 | [`01-option-matching.txt`](01-option-matching.txt) |
| 02 | [`02-java-agent.txt`](02-java-agent.txt) |
| 03 | [`03-class-space-size.txt`](03-class-space-size.txt) |
| 04 | [`04-executable-war.txt`](04-executable-war.txt) |
| 05 | [`05-gemfire-client.txt`](05-gemfire-client.txt) |
| 06 | [`06-end-to-end.txt`](06-end-to-end.txt) |

## x86-64

[`linux-amd64-emulated.txt`](linux-amd64-emulated.txt) is `make all PLATFORM=linux/amd64 RUNS=3` on
the same machine, which runs the x86-64 JDK under emulation. Every outcome was the same as on arm64.
The times in that file are several times slower than native and mean nothing. 05 was not part of
that run.

## Reading the numbers

- **Outcomes** (cache used or rejected, cache written or not, operations worked or failed) are what
  the tests compare against when you run them. They were the same on every run we made.
- **Class counts** move by a few classes from run to run and with the JDK build.
- **Times** depend on the machine. Compare the rows of one run with each other, not with another
  machine's.
