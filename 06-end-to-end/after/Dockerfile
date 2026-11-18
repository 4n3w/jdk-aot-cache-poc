# The application image with the AOT cache: before/Dockerfile plus the two numbered build steps.
ARG BASE_IMAGE=aot-poc:base
FROM ${BASE_IMAGE}
USER root

RUN chown -R 1001:0 /opt/agent && chmod -R g+rwX /opt/agent

ADD ./build/libs/sample-app.war /tmp/
COPY run.sh /tmp
RUN chmod 775 /tmp/run.sh

# 1. Unpack the executable WAR into a thin launcher archive plus lib/*.jar
RUN java -Djarmode=tools -jar /tmp/sample-app.war extract --destination /opt/app

# 2. Training run: start the application, exit after context refresh, write the cache.
#    It goes through run.sh, so it gets the same --add-opens set as production.
#    --add-modules stands in for -javaagent and -Dcom.sun.management, which production passes.
#    There is deliberately no -XX:CompressedClassSpaceSize here.
RUN JAVA_OPTS="--add-modules=java.instrument,jdk.management.agent -XX:+UseG1GC -Xms999M -Xmx999M -Dspring.context.exit=onRefresh" \
    AOT_OPTS="-XX:AOTCacheOutput=/opt/app/app.aot" \
    /tmp/run.sh

EXPOSE 8080/tcp
ENTRYPOINT ["/tmp/run.sh"]
USER 1001
