# A production-style set of JVM options, of the kind a platform injects into JAVA_OPTS at deploy
# time. Sourced by the test scripts, both inside the test image and on the host (06).

AGENT=/opt/agent/agent.jar

# Sizing and GC options. None of these has to match between training and production (01), but
# -XX:CompressedClassSpaceSize=40M stops a training run from writing its cache (03).
PROD_MEMORY_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseStringDeduplication \
-XX:CompressedClassSpaceSize=40M -XX:MaxDirectMemorySize=100M -XX:MaxMetaspaceSize=256M \
-XX:ReservedCodeCacheSize=240M -Xss512K -Xms999M -Xmx999M"

# Ordinary system properties. These do not have to match either (01).
PROD_PROPERTIES="-Djdk.nio.maxCachedBufferSize=100000 -Dnetworkaddress.cache.ttl=300 \
-Djava.security.egd=file:/dev/./urandom -Duser.timezone=UTC"

# The two options that add a JDK module behind the scenes, and so do have to match (01):
# -javaagent adds java.instrument, and any -Dcom.sun.management... property adds
# jdk.management.agent. The bare prefix is used here because it adds the module without starting the
# JMX agent, which keeps the class counts about the application.
PROD_MODULE_OPTS="-javaagent:$AGENT -Dcom.sun.management"

# What a training run passes in place of PROD_MODULE_OPTS when the agent is not run at build time.
TRAIN_MODULE_OPTS="--add-modules=java.instrument,jdk.management.agent"
