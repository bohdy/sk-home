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

RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /tmp \
    && mv /tmp/terraform /usr/local/bin/ \
    && rm -rf /tmp/* \
    && terraform version

RUN curl https://bws.bitwarden.com/install | sh

USER ubuntu
RUN terraform -install-autocomplete
