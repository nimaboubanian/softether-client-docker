FROM ubuntu:26.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl iproute2 isc-dhcp-client tar \
    && rm -rf /var/lib/apt/lists/*
COPY build/softether/vpnclient /usr/local/bin/vpnclient
COPY build/softether/vpncmd /usr/local/bin/vpncmd
COPY build/softether/hamcore.se2 /usr/local/bin/hamcore.se2
COPY build/softether/ReadMeFirst_License.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_en.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_ja.txt /usr/share/softether/
COPY build/softether/ReadMeFirst_Important_Notices_cn.txt /usr/share/softether/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY vpn-status.sh /usr/local/bin/vpn-status.sh
ADD --checksum=sha256:676fb7f78d267b6ae73df719c0c7f2b565dde7147da935cfafbc1e1da558b6d5 \
    https://github.com/go-gost/gost/releases/download/v3.3.0/gost_3.3.0_linux_amd64.tar.gz /tmp/gost.tgz
RUN tar -xzf /tmp/gost.tgz -C /usr/local/bin gost \
    && rm /tmp/gost.tgz \
    && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/vpn-status.sh \
    && mkdir -p /vpnclient
WORKDIR /vpnclient
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
