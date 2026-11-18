# The test image plus a GemFire Java client. The GemFire jars are copied out of the GemFire image
# when this image is built, so none of them are stored in this repository.
ARG GEMFIRE_IMAGE=gemfire/gemfire:10.3.2-jdk17
ARG TOOLS_IMAGE=aot-poc:tools

FROM ${GEMFIRE_IMAGE} AS gemfire

FROM ${TOOLS_IMAGE}
COPY --from=gemfire /gemfire/lib/ /opt/gemfire/lib/
COPY src/ /src/gemfire-client/
RUN mkdir -p /classes/gemfire-client && \
    javac -cp /opt/gemfire/lib/gemfire-dependencies.jar -d /classes/gemfire-client \
        $(find /src/gemfire-client -name '*.java') && \
    jar --create --file /poc/fixtures/gemfire-client.jar -C /classes/gemfire-client .
COPY client-test.sh /poc/05-gemfire-client/client-test.sh
