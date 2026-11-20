# An image for fctl sessions that doesn't start from fctl's own: Ubuntu with
# what fctl needs, to which you add what your sessions need. fctl's docs
# explain each step: https://fctl.sh/docs/sandbox-images/#an-image-from-another-base
#
#   docker build -t my-sandbox examples/ubuntu
#   docker run --rm -i my-sandbox sh -s < examples/check.sh
FROM ubuntu:24.04

# A download piped into a shell fails the step when it fails.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# What fctl needs: bash, git, curl and CA certificates (for the installers,
# and git over HTTPS), and the GitHub CLI from GitHub's repository. sudo lets
# the agent install what a task needs: the sandbox is the boundary. Add your
# own packages to the list.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git sudo \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# fctl, for every user: a static build, which runs on any Linux. An empty
# FCTL_VERSION installs the latest release. The host puts its own fctl-agent
# into the sandbox each time a session starts, so the archive's goes.
ARG FCTL_VERSION=
RUN curl -fsSL https://fctl.sh/install \
    | env FCTL_VERSION="$FCTL_VERSION" FCTL_INSTALL_DIR=/usr/local/bin FCTL_NO_COMPLETIONS=1 sh \
  && rm -f /usr/local/bin/fctl-agent-*-linux

# The user sessions run as, with sudo and the package caches' directory.
# Ubuntu's images come with the user ubuntu at uid 1000: agent takes its
# place.
RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi \
  && useradd --create-home --shell /bin/bash --uid 1000 agent \
  && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
  && chmod 0440 /etc/sudoers.d/agent \
  && install -d -o agent -g agent /var/cache/fctl

# Claude Code, the native build, in ~/.local/bin, as the user. Claude and its
# commands find their tools through the image's PATH, and so do setup
# scripts: Ubuntu's login shells keep it.
USER agent
WORKDIR /home/agent
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH=/home/agent/.local/bin:$PATH
