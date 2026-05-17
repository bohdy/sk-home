FROM ubuntu:latest

ARG TARGETARCH

RUN apt update
RUN apt install -y curl
RUN install -dm 755 /etc/apt/keyrings
RUN curl -fSs https://mise.en.dev/gpg-key.pub | tee /etc/apt/keyrings/mise-archive-keyring.asc 1> /dev/null
RUN echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.en.dev/deb stable main" | tee /etc/apt/sources.list.d/mise.list

RUN apt update
RUN apt install -y \
    unzip \
    gnupg \
    software-properties-common \
    curl \
    sudo \
    npm \
    mise

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Allow devcontainer features to perform root-owned setup from the ubuntu user.
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

RUN curl https://bws.bitwarden.com/install | sh

# Install act so GitHub Actions workflows can be exercised from inside the devcontainer.
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

USER ubuntu
