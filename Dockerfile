FROM catthehacker/ubuntu:full-latest

ARG RUNNER_VERSION=2.321.0

USER root

# Runner deps (most already present in full-latest, belt and braces)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl jq sudo ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Create runner user with sudo + docker group access
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
    && (getent group docker || groupadd docker) \
    && usermod -aG docker runner

# Download and extract the GitHub Actions runner
WORKDIR /actions-runner
RUN curl -fsSL -o runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && tar xzf runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /actions-runner

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
