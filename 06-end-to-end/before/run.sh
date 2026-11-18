#!/bin/sh
# JAVA_OPTS is injected by the platform at deploy time.
exec java $JAVA_OPTS \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.net=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt.font=ALL-UNNAMED \
  --add-opens=java.sql/java.sql=ALL-UNNAMED \
  --enable-native-access=ALL-UNNAMED \
  --sun-misc-unsafe-memory-access=allow \
  -jar /tmp/sample-app.war
