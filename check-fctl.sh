#!/usr/bin/env bash
# Checks that fctl's own development works in an image built from this
# repository, as sessions that work on hyperstructure/fctl do it: what its CI
# checks (`cargo xtask check`), a session through its local stack (`cargo
# xtask dev --smoke`) and through its standalone control plane (`cargo xtask
# serve`), an `npm install` that leaves its lockfile alone, and screenshots of
# its web app with Playwright, as its screenshots skill takes them. Runs
# inside the image as its user; the Develop fctl workflow runs it on pull
# requests that change the image:
#
#   docker run --rm -i --init sandbox:dev bash -s < check-fctl.sh
#
# FCTL_REF is the branch of hyperstructure/fctl to check (default, and when
# there is no such branch: main), FCTL_DIR where to clone it (default
# ~/workspace/fctl), and OUT, when set, a directory for the screenshots.
set -euo pipefail

fail() {
  echo "check-fctl.sh: $*" >&2
  exit 1
}

# All of it runs once bash has read it, with nothing on stdin: the script
# itself comes on stdin, and the tools it runs mustn't read the rest.
main() {
  local repo=https://github.com/hyperstructure/fctl ref=${FCTL_REF:-main}
  if ! [[ $ref =~ ^[A-Za-z0-9._/-]+$ ]] || ! git ls-remote --exit-code --heads "$repo" "$ref" >/dev/null; then
    ref=main
  fi
  local dir=${FCTL_DIR:-$HOME/workspace/fctl}
  git clone --quiet --depth 1 --branch "$ref" "$repo" "$dir"
  cd "$dir"
  echo "Developing hyperstructure/fctl $ref ($(git rev-parse --short HEAD)) with $(node --version), $(rustc --version)"

  cargo xtask check
  cargo xtask dev --smoke

  # Adding a package rewrites the lockfile with the image's npm.
  npm install --no-audit --no-fund
  git diff --quiet package-lock.json ||
    fail "npm $(npm --version) rewrites fctl's package-lock.json: $(git diff --stat package-lock.json)"

  FCTL_SETUP_TOKEN=dev-setup-token cargo xtask serve >"$HOME/serve.log" 2>&1 &
  server=$!
  trap stop_server EXIT
  local deadline=$((SECONDS + 1200))
  until curl -fsS -o /dev/null http://localhost:8787/api/v1/health; do
    kill -0 "$server" 2>/dev/null || { cat "$HOME/serve.log"; fail "cargo xtask serve stopped"; }
    [ "$SECONDS" -lt "$deadline" ] || { cat "$HOME/serve.log"; fail "cargo xtask serve didn't answer"; }
    sleep 5
  done
  cargo xtask dev --smoke --server http://localhost:8787

  # The image's version of Playwright, whose browsers and their libraries are
  # there: nothing to download and no sudo.
  local version
  version=$(playwright --version)
  mkdir -p "$HOME/screenshots"
  cd "$HOME/screenshots"
  npm init -y >/dev/null
  npm install --no-audit --no-fund "playwright@${version#Version }"
  shoot >shoot.mjs
  node shoot.mjs http://localhost:8787/ home-light.png
  node shoot.mjs http://localhost:8787/ home-dark-390.png dark 390x844
  for png in home-light.png home-dark-390.png; do
    [ "$(wc -c <"$png")" -gt 10000 ] || fail "$png is too small to show the web app"
  done
  if [ -n "${OUT:-}" ]; then cp home-*.png "$OUT/"; fi
  echo "fctl's checks, a session through cargo xtask dev and one through cargo xtask serve, and screenshots work in the image."
}

stop_server() {
  pkill -TERM -f deploy/standalone/server.mjs || true
  wait "$server" || true
}

# fctl's screenshots skill's shoot.mjs: signs in as the dev owner, then takes
# the page in a color scheme and size.
shoot() {
  cat <<'EOF'
// node shoot.mjs URL OUT.png [light|dark] [WIDTHxHEIGHT]
import { chromium } from "playwright";

const [url, out, colorScheme = "light", size = "1440x900"] = process.argv.slice(2);
const [width, height] = size.split("x").map(Number);
const browser = await chromium.launch();
const page = await browser.newPage({ colorScheme, reducedMotion: "reduce", viewport: { width, height } });
await page.addInitScript(() => {
  let seed = 42;
  Math.random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
});
await page.goto(new URL("/login", url).href);
await page.fill("input[type=email]", "dev@fctl.test");
await page.fill("input[type=password]", "fctl-dev-password");
await page.click("button[type=submit]");
await page.waitForURL((u) => u.pathname !== "/login");
await page.goto(url, { waitUntil: "networkidle" });
await page.screenshot({ path: out });
await browser.close();
EOF
}

main "$@" </dev/null
