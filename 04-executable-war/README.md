# 04: Executable WAR, packed and extracted

A Spring Boot executable WAR keeps its libraries as jars inside the WAR, and Spring Boot's own
class loader reads them from there. This test checks how well the AOT cache works with that layout,
and with the extracted layout that Spring Boot recommends for it.

## Run it

```sh
make 04
```

## How it works

The [`sample-app`](../sample-app/) builds two WARs from the same code:

| WAR | Built with | Difference |
|---|---|---|
| `sample-app.war` | `./gradlew bootWar` | All libraries in `WEB-INF/lib/` |
| `sample-app-provided.war` | `./gradlew bootWar -PprovidedTomcat` | The embedded Tomcat is declared `providedRuntime`, so Spring Boot packages it in `WEB-INF/lib-provided/` |

[`test.sh`](test.sh) then:

1. trains and runs the packed WAR: `java -jar sample-app.war`
2. runs Spring Boot's extract command on both WARs: `java -Djarmode=tools -jar <war> extract --destination <dir>`
3. trains and runs the extracted application: `java -jar <dir>/sample-app.war`
4. unzips the WAR by hand and tries to train with `-cp WEB-INF/classes:WEB-INF/lib/*`

For the runs that use a cache it counts the classes that came from it, in total and for the classes
that belong to the WAR (Spring, Tomcat, Jackson and the application's own).

## What our run showed

Full output: [`results/04-executable-war.txt`](../results/04-executable-war.txt).

| Layout | Cache | WAR classes from the cache | All classes from the cache |
|---|---|---|---|
| Packed, `java -jar sample-app.war` | written and used | 3,033 of 3,886 | 6,052 of 7,355 |
| Extracted, `java -jar <dir>/sample-app.war` | written and used | 4,363 of 4,396 | 7,660 of 7,941 |
| Unzipped, directories on the class path | training fails | | |

- **Packed works in part.** On JDK 25 the cache is created and used with the packed WAR, but about a
  fifth of the WAR's classes are still loaded the normal way.
- **Extracted works almost fully.** `extract` writes a small launcher archive with the same name and a
  `lib/` directory of ordinary jars. Nearly every class then comes from the cache.
  [06](../06-end-to-end/README.md) measures the difference in startup time.
- **`extract` fails on `WEB-INF/lib-provided/`.** On Spring Boot 4.1.1:

  ```
  Invalid library location WEB-INF/lib-provided/spring-boot-tomcat-4.1.1.jar
  ```

  To check a WAR: `jar tf <war> | grep WEB-INF/lib-provided/`. A WAR that has the directory needs
  those dependencies changed to ordinary runtime dependencies, or needs to be built as an executable
  JAR, before it can be extracted this way.
- **Unzipping by hand does not work.** A training run cannot have a non-empty directory on the class
  path:

  ```
  Error: non-empty directory '.../WEB-INF/classes'
  Cannot have non-empty directory in paths
  ```
