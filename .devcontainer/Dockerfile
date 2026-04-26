FROM ubuntu:latest

# Install Terraform CLI
ARG TERRAFORM_VERSION=1.14.9
ARG TARGETARCH

RUN apt update
RUN apt install -y \
    unzip \
    gnupg \
    software-properties-common \
    curl \
    sudo \
    npm

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Allow devcontainer features to perform root-owned setup from the ubuntu user.
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /tmp \
    && mv /tmp/terraform /usr/local/bin/ \
    && rm -rf /tmp/* \
    && terraform version

RUN curl https://bws.bitwarden.com/install | sh

# Install act so GitHub Actions workflows can be exercised from inside the devcontainer.
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

USER ubuntu
RUN terraform -install-autocomplete
