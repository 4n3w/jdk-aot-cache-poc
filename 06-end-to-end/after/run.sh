#!/bin/sh
# JAVA_OPTS is injected by the platform at deploy time.
# AOT_OPTS defaults to loading the cache baked into the image.
# The image build overrides it to create the cache instead.
exec java $JAVA_OPTS ${AOT_OPTS:--XX:AOTCache=/opt/app/app.aot} \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.net=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt.font=ALL-UNNAMED \
  --add-opens=java.sql/java.sql=ALL-UNNAMED \
  --enable-native-access=ALL-UNNAMED \
  --sun-misc-unsafe-memory-access=allow \
  -jar /opt/app/sample-app.war
