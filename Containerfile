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

# Install other tools
RUN dnf install -y \
        git \
        wget \
        curl \
        htop \
        jq \
        yq \
        openssh-server \
        firewalld \
    && dnf clean all

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
