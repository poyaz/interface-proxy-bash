FROM alpine:3.12

RUN apk add --no-cache bash apache2-utils squid=4.17-r0 jq curl

COPY defaultConfig/* /etc/squid/

VOLUME /etc/squid/conf.d/

CMD /bin/sh -c "squid -d 1 --foreground -f /etc/squid/squid.conf"
