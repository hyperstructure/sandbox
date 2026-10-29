# The kernel of fctl's Firecracker sandboxes, as an image whose /vmlinux it
# is: fctl hosts with the firecracker driver pull it and boot their VMs
# with it. .github/workflows/kernel.yml publishes it as
# ghcr.io/hyperstructure/sandbox-kernel.
#
#   docker build -t sandbox-kernel:dev kernel
#   docker build --output type=local,dest=out kernel   # out/vmlinux
FROM debian:trixie-slim AS build
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates curl flex libelf-dev libssl-dev xz-utils \
  && rm -rf /var/lib/apt/lists/*
COPY . /kernel
RUN OUT=/out /kernel/build.sh

FROM scratch
COPY --from=build /out/vmlinux /out/vmlinux.config /
