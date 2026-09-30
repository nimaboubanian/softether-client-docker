FROM ubuntu:26.04
RUN sed -i 's/^Components: .*/Components: main universe/' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates dante-server iproute2 isc-dhcp-client mawk tinyproxy \
    && rm -rf /var/lib/apt/lists/*
COPY build/softether/vpnclient /usr/local/bin/vpnclient
COPY build/softether/vpncmd /usr/local/bin/vpncmd
COPY build/softether/hamcore.se2 /usr/local/bin/hamcore.se2
COPY build/softether/hamcore.se2 /usr/share/softether/hamcore.se2
COPY build/softether/ReadMeFirst_License.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_en.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_ja.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_cn.txt /usr/share/softether/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY danted.conf /etc/danted.conf
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /vpnclient /var/log/softether
WORKDIR /vpnclient
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
