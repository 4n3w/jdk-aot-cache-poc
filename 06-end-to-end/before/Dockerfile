# The application image as it is built today: the executable WAR is copied in and started with -jar.
ARG BASE_IMAGE=aot-poc:base
FROM ${BASE_IMAGE}
USER root

RUN chown -R 1001:0 /opt/agent && chmod -R g+rwX /opt/agent

ADD ./build/libs/sample-app.war /tmp/
COPY run.sh /tmp
RUN chmod 775 /tmp/run.sh

EXPOSE 8080/tcp
ENTRYPOINT ["/tmp/run.sh"]
USER 1001
