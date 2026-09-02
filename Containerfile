FROM quay.io/fedora/fedora-bootc:44

ARG HOSTNAME=wacky
ARG TIMEZONE=UTC

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
        openssh-server \
        firewalld \
        ca-certificates \
        conntrack-tools \
        container-selinux \
        e2fsprogs \
        ethtool \
        iproute \
        iptables \
        kmod \
        nfs-utils \
        socat \
        util-linux \
        https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.6-1.el8.noarch.rpm \
    && dnf clean all && rm -rf /var/cache /var/log/dnf

# Install k3s
RUN curl -sfL https://get.k3s.io | \
    INSTALL_K3S_SKIP_ENABLE=true \
    INSTALL_K3S_SKIP_START=true \
    sh -
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
RUN systemctl enable sshd.service && \
    systemctl enable firewalld.service

# Validate the container
RUN bootc container lint

VOLUME /var/lib/rancher/k3s
VOLUME /etc/rancher/k3s
STOPSIGNAL SIGRTMIN+3
