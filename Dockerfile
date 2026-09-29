FROM gcc:alpine AS builder
WORKDIR /src
COPY softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz .
RUN apk add --no-cache binutils make \
    && tar xzf softether-vpnclient-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz \
    && cd vpnclient \
    && make main \
    && strip vpnclient vpncmd

FROM alpine:3.20
RUN apk add --no-cache tinyproxy microsocks
COPY --from=builder /src/vpnclient/vpnclient /usr/local/bin/vpnclient
COPY --from=builder /src/vpnclient/vpncmd /usr/local/bin/vpncmd
COPY --from=builder /src/vpnclient/hamcore.se2 /usr/share/softether/hamcore.se2
COPY --from=builder /src/vpnclient/ReadMeFirst_License.txt /usr/share/softether/
COPY --from=builder /src/vpnclient/ReadMeFirst_Important_Notices_en.txt /usr/share/softether/
COPY --from=builder /src/vpnclient/ReadMeFirst_Important_Notices_ja.txt /usr/share/softether/
COPY --from=builder /src/vpnclient/ReadMeFirst_Important_Notices_cn.txt /usr/share/softether/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /vpnclient /var/log/softether
WORKDIR /vpnclient
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
