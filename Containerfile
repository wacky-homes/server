FROM quay.io/fedora/fedora-bootc:44

ARG TIMEZONE=UTC
ARG K3S_VERSION=1.36.4+k3s1

# Set timezone
RUN ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone

# Install packages
RUN dnf install -y \
        git \
        wget \
        curl \
        htop \
        jq \
        yq \
        tree \
    && dnf clean all && rm -rf /var/cache /var/log/dnf

# Install k3s dependencies
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

# Install k3s
RUN curl -fL "https://github.com/k3s-io/k3s/releases/download/v${K3S_VERSION}/k3s" -o /usr/bin/k3s && \
    chmod 0755 /usr/bin/k3s && \
    ln -s /usr/bin/k3s /usr/bin/kubectl && \
    ln -s /usr/bin/k3s /usr/bin/crictl && \
    ln -s /usr/bin/k3s /usr/bin/ctr

# Copy k3s configurations
COPY system/usr/share/k3s/manifests/flux.yaml /usr/share/k3s/manifests/flux.yaml
COPY system/usr/share/k3s/manifests/flux-sync.yaml /usr/share/k3s/manifests/flux-sync.yaml
COPY system/etc/systemd/system/flux-sops-age.service /etc/systemd/system/flux-sops-age.service
COPY system/etc/systemd/system/k3s.service /etc/systemd/system/k3s.service
COPY system/etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml

# Copy system configurations
COPY system/usr/share/containers/skopeo.pub /usr/share/containers/skopeo.pub
COPY system/etc/containers/policy.json /etc/containers/policy.json
COPY system/etc/containers/registries.d/ghcr.io.yaml /etc/containers/registries.d/ghcr.io.yaml

# Setup SSH
RUN printf '%s\n' \
        'PubkeyAuthentication yes' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
    >> /etc/ssh/sshd_config

# Setup firewall for ssh, http and k3s cluster and service CIDRs
RUN firewall-offline-cmd --add-service=ssh && \
    firewall-offline-cmd --add-service=http && \
    firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16 && \
    firewall-offline-cmd --zone=trusted --add-source=10.43.0.0/16

# Copy systemd units
COPY system/etc/systemd/system/var-data.mount /etc/systemd/system/var-data.mount

# Enable systemd units
RUN systemctl enable var-data.mount && \
    systemctl enable flux-sops-age.service && \
    systemctl enable k3s.service && \
    systemctl enable sshd.service && \
    systemctl enable firewalld.service

# Validate the container
RUN bootc container lint

STOPSIGNAL SIGRTMIN+3
