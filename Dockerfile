# The default sandbox for fctl sessions: Debian with git, gh, build tools,
# Python and uv, Rust, Node.js, TypeScript, Bun, Playwright and its browsers,
# Claude Code and fctl (README.md lists the versions). Sessions run as the
# `agent` user.
# .github/workflows/image.yml publishes it as ghcr.io/hyperstructure/sandbox.
#
#   docker build -t sandbox:dev .
#   fctl host image build          # on an fctl host, with its driver
FROM debian:trixie-slim

# The fctl release to install and where releases come from; `fctl host
# image build` passes its own version and download_base. Empty: the latest,
# from https://fctl.sh/releases. CLAUDE_VERSION pins Claude Code (empty: the
# latest release).
ARG FCTL_VERSION=
ARG FCTL_DOWNLOAD=
ARG CLAUDE_VERSION=
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC
COPY provision.sh /tmp/provision.sh
# Each of provision.sh's steps makes a layer of its own, none over about
# 200 MB compressed: ghcr.io sends each layer's download to a link that
# expires within 5 to 10 minutes, and closes the connection then, and Apple's
# container keeps nothing of a pull that broke off. One layer of 1.3 GB never
# arrived at 2.4 MB/s.
RUN bash /tmp/provision.sh tools
RUN bash /tmp/provision.sh build-tools
RUN bash /tmp/provision.sh media-tools
RUN bash /tmp/provision.sh node
RUN bash /tmp/provision.sh browser-libraries
RUN bash /tmp/provision.sh python
RUN bash /tmp/provision.sh user
RUN bash /tmp/provision.sh claude
RUN bash /tmp/provision.sh rust
RUN bash /tmp/provision.sh rust-extras
RUN bash /tmp/provision.sh bun
RUN bash /tmp/provision.sh chromium
RUN bash /tmp/provision.sh webkit
RUN bash /tmp/provision.sh versions && rm /tmp/provision.sh

USER agent
WORKDIR /home/agent
# As /etc/profile.d/fctl.sh (provision.sh) sets it for login shells.
ENV PATH=/home/agent/.local/bin:/home/agent/.cargo/bin:/home/agent/.bun/bin:/opt/fctl/bin:$PATH
CMD ["tail", "-f", "/dev/null"]
