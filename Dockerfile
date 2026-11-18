# The test image. Two of its stages are tagged by `make image`:
#
#   base    what an application's base image provides: the JDK, plus a Java agent in /opt/agent
#   tools   base, plus the sample applications and the test scripts (01-04 run inside it)
#
# JDK_IMAGE must contain a full JDK 25 (javac and jar are used below), not only a runtime.
ARG JDK_IMAGE=container-registry.oracle.com/java/jdk-no-fee-term:25

FROM ${JDK_IMAGE} AS build
USER root
WORKDIR /src

# The stand-in Java agent and the three-class plain application
COPY stand-in-agent/ stand-in-agent/
COPY plain-app/ plain-app/
RUN mkdir -p /out /classes/agent /classes/agent-boot /classes/app && \
    javac -d /classes/agent $(find stand-in-agent/src -name '*.java') && \
    jar --create --file /out/agent.jar --manifest stand-in-agent/MANIFEST.MF -C /classes/agent . && \
    javac -d /classes/agent-boot $(find stand-in-agent/boot-src -name '*.java') && \
    jar --create --file /out/agent-boot.jar -C /classes/agent-boot . && \
    javac -d /classes/app $(find plain-app/src -name '*.java') && \
    jar --create --file /out/plain-app.jar -C /classes/app .

# The sample Spring Boot executable WAR, without and with WEB-INF/lib-provided/
COPY sample-app/ sample-app/
RUN --mount=type=cache,target=/gradle-home \
    cd sample-app && \
    GRADLE_USER_HOME=/gradle-home ./gradlew --no-daemon -q bootWar && \
    GRADLE_USER_HOME=/gradle-home ./gradlew --no-daemon -q bootWar -PprovidedTomcat && \
    cp build/libs/sample-app.war build/libs/sample-app-provided.war /out/

FROM ${JDK_IMAGE} AS base
USER root
COPY --from=build /out/agent.jar /out/agent-boot.jar /opt/agent/

FROM base AS tools
COPY --from=build /out/plain-app.jar /out/sample-app.war /out/sample-app-provided.war /poc/fixtures/
COPY lib/ /poc/lib/
COPY 01-option-matching/ /poc/01-option-matching/
COPY 02-java-agent/ /poc/02-java-agent/
COPY 03-class-space-size/ /poc/03-class-space-size/
COPY 04-executable-war/ /poc/04-executable-war/
