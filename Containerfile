FROM quay.io/fedora/fedora-bootc:44

ARG HOSTNAME=wacky
ARG TIMEZONE=UTC
ARG K3S_VERSION=v1.36.4+k3s1

# Set hostname
RUN echo "$HOSTNAME"            > /etc/hostname && \
	echo "127.0.0.1	$HOSTNAME" >> /etc/hosts && \
	echo "::1		$HOSTNAME" >> /etc/hosts

# Set timezone
RUN ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime && \
    echo "${TZ}" > /etc/timezone

# Install packages
RUN dnf install -y \
        git \
        wget \
        curl \
        htop \
        jq \
        yq \
    && dnf clean all && rm -rf /var/cache /var/log/dnf

# Install k3s
RUN dnf install -y \
        openssh-server \
        firewalld \
        ca-certificates \
        conntrack-tools \
        e2fsprogs \
        ethtool \
        iproute \
        iptables \
        kmod \
        nfs-utils \
        socat \
        util-linux \
    && dnf clean all && rm -rf /var/cache /var/log/dnf
RUN curl -fL "https://github.com/k3s-io/k3s/releases/download/v1.36.4%2Bk3s1/k3s-arm64" -o /usr/local/bin/k3s && \
    chmod 0755 /usr/local/bin/k3s && \
    ln -s /usr/local/bin/k3s /usr/local/bin/kubectl && \
    ln -s /usr/local/bin/k3s /usr/local/bin/crictl && \
    ln -s /usr/local/bin/k3s /usr/local/bin/ctr && \
    mkdir -p \
        /etc/rancher/k3s \
        /var/lib/rancher/k3s \
        /var/lib/kubelet \
        /run/k3s
COPY system/etc/systemd/system/k3s.service /etc/systemd/system/k3s.service
COPY system/etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml

# Setup SSH
RUN printf '%s\n' \
        'PubkeyAuthentication yes' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
    >> /etc/ssh/sshd_config

# Setup firewall
RUN firewall-offline-cmd --add-service=ssh

# Enable systemd services
RUN systemctl enable k3s.service && \
    systemctl enable sshd.service && \
    systemctl enable firewalld.service

# Validate the container
RUN bootc container lint

VOLUME /var/lib/rancher/k3s
VOLUME /etc/rancher/k3s
STOPSIGNAL SIGRTMIN+3
