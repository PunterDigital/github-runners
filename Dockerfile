FROM catthehacker/ubuntu:full-latest

ARG RUNNER_VERSION=2.334.0

USER root

# Runner deps (most already present in full-latest, belt and braces)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl jq sudo ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Ensure runner user exists (catthehacker base already ships one) with sudo + docker group access
RUN id -u runner >/dev/null 2>&1 || useradd -m -s /bin/bash runner \
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

# --- Android / Tauri toolchain -------------------------------------------------
# Required by the voca-desktop CI's `pnpm tauri android build` job. Mirrors
# scripts/install-android-runner.sh on voca-desktop's feature/android branch.

ENV ANDROID_HOME=/opt/android-sdk
ENV NDK_HOME=/opt/android-sdk/ndk/30.0.14904198
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$JAVA_HOME/bin:$PATH

# JDK 21 plus system libs the Rust deps link against (alsa is for cpal even
# though we don't capture audio in CI).
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-21-jdk-headless \
        unzip \
        build-essential \
        pkg-config \
        libssl-dev \
        libasound2-dev \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: command-line tools + the exact package set Tauri 2 needs.
# NDK version is pinned to match NDK_HOME above and the workflow's env.
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "ndk;30.0.14904198" \
        "cmake;3.22.1" \
    && chown -R runner:runner "${ANDROID_HOME}"

# Rust + Android targets, installed for the runner user that executes jobs.
# The catthehacker base already ships rustup with a stable toolchain; re-running
# the installer would try to upgrade in-place and fails with a cross-device
# rename because ~/.rustup/tmp lives on a different mount than ~/.rustup. Only
# bootstrap rustup if it isn't already there.
USER runner
ENV PATH=/home/runner/.cargo/bin:$PATH
RUN if [ ! -x /home/runner/.cargo/bin/rustup ]; then \
        curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
            | sh -s -- -y --default-toolchain stable --profile minimal; \
    fi \
    && rustup target add \
        aarch64-linux-android \
        armv7-linux-androideabi \
        i686-linux-android \
        x86_64-linux-android

# Verify the toolchain is wired up end-to-end. Any non-empty failure here means
# the image isn't ready for the android workflow.
RUN set -e \
    && ls -la "$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang" \
    && rustc --version \
    && rustup target list --installed | grep android \
    && sdkmanager --list_installed | grep -E 'platform-tools|platforms;android-34|build-tools;34.0.0|ndk;30.0.14904198|cmake;3.22.1'

USER root
# ------------------------------------------------------------------------------

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
