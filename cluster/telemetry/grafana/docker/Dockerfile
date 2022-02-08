FROM docker.io/grafana/grafana:7.5.11

USER root
RUN apk add curl

COPY create-org.sh /usr/share/grafana/bin/create-org.sh
RUN chmod +x /usr/share/grafana/bin/create-org.sh

USER grafana