#!/usr/bin/env bash
#
# Run the browser test suite (34 #[wasm_bindgen_test] cases in tests/web.rs).
#
# Why this exists instead of `wasm-pack test --headless --chrome`:
#
#   wasm-pack downloads the *latest* ChromeDriver into its own cache and passes
#   that path to cargo, overriding any CHROMEDRIVER you set yourself. When the
#   installed Chrome is a different major version — which it will be, sooner
#   rather than later — the driver refuses the session and the run dies with a
#   bare `http status: 404` and a SIGKILLed driver. Measured here: ChromeDriver
#   152 against Chrome 151.
#
#   That failure mode is why upstream shipped 34 tests that nobody could run.
#   The tests were fine the whole time. So: resolve the driver that matches THIS
#   machine's Chrome, and invoke the runner directly, cutting wasm-pack out of
#   the driver decision entirely.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

wasm_bindgen_version="$(python3 -c 'import json;print(json.load(open("build-provenance.json"))["toolchain"]["wasm-bindgen"])')"
runner="$HOME/Library/Caches/.wasm-pack/wasm-bindgen-cargo-install-${wasm_bindgen_version}/wasm-bindgen-test-runner"
if [[ ! -x "$runner" ]]; then
  runner="$(command -v wasm-bindgen-test-runner || true)"
fi
if [[ ! -x "$runner" ]]; then
  echo "FAIL: wasm-bindgen-test-runner ${wasm_bindgen_version} not found." >&2
  echo "  cargo install wasm-bindgen-cli --version ${wasm_bindgen_version}" >&2
  exit 1
fi

# CHROMEDRIVER may be supplied by CI, which pins Chrome and its driver together.
if [[ -z "${CHROMEDRIVER:-}" ]]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; platform="mac-arm64" ;;
    Darwin-x86_64) chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; platform="mac-x64" ;;
    *) chrome_bin="$(command -v google-chrome || command -v chromium || command -v chrome || true)"; platform="linux64" ;;
  esac

  # CI installs Chrome somewhere off PATH and knows where it put it.
  [[ -n "${CHROME_BIN:-}" ]] && chrome_bin="$CHROME_BIN"

  if [[ ! -x "$chrome_bin" ]]; then
    echo "FAIL: no Chrome found — install Chrome or set CHROMEDRIVER yourself." >&2
    exit 1
  fi

  chrome_version="$("$chrome_bin" --version | grep -oE '[0-9]+(\.[0-9]+){3}')"
  chrome_build="${chrome_version%.*}"
  echo "==> Chrome $chrome_version ($platform)"

  cache="${XDG_CACHE_HOME:-$HOME/.cache}/signal-bridge-chromedriver/$chrome_version"
  CHROMEDRIVER="$cache/chromedriver"

  if [[ ! -x "$CHROMEDRIVER" ]]; then
    echo "==> fetching the ChromeDriver that matches this Chrome"
    url="$(curl -sS https://googlechromelabs.github.io/chrome-for-testing/latest-patch-versions-per-build-with-downloads.json \
      | python3 -c "
import json,sys
builds = json.load(sys.stdin)['builds']
info = builds.get('$chrome_build')
if not info:
    sys.exit('no Chrome for Testing build published for $chrome_build')
for entry in info['downloads'].get('chromedriver', []):
    if entry['platform'] == '$platform':
        print(entry['url']); break
else:
    sys.exit('no chromedriver for $platform in build $chrome_build')
")"
    mkdir -p "$cache"
    curl -sSL -o "$cache/driver.zip" "$url"
    unzip -oqj "$cache/driver.zip" '*/chromedriver' -d "$cache"
    chmod +x "$CHROMEDRIVER"
    rm "$cache/driver.zip"
  fi
fi

echo "==> driver: $("$CHROMEDRIVER" --version)"

# wasm-bindgen-test-runner reads browser capabilities from webdriver.json in
# the crate root, and says so in its output. Two things have to go in it, and
# both are invisible failures otherwise:
#
#   binary — chromedriver launches whatever `google-chrome` sits on PATH, not
#     the Chrome we just matched a driver to. On a CI runner Chrome lives in a
#     tool cache off PATH, so the driver either finds a different version or
#     nothing at all.
#   --no-sandbox — Chrome cannot use its sandbox on runners and in containers
#     and refuses to start.
#
# Either failure surfaces the same way: the driver cannot create a session,
# gets SIGKILLed, and the run dies with a bare `http status: 404`. That single
# opaque symptom covering several unrelated causes is most of why these tests
# went unrun for so long.
#
# Generated per run rather than committed, so the Chrome path is always this
# machine's.
if [[ -n "${chrome_bin:-}" ]]; then
  python3 - "$chrome_bin" <<'PY'
import json, sys
json.dump(
    {
        "goog:chromeOptions": {
            "binary": sys.argv[1],
            "args": ["--no-sandbox", "--disable-dev-shm-usage"],
        }
    },
    open("webdriver.json", "w"),
    indent=2,
)
PY
  echo "==> webdriver.json written for $chrome_bin"
fi

echo "==> tests"

CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUNNER="$runner" \
CHROMEDRIVER="$CHROMEDRIVER" \
WASM_BINDGEN_TEST_ONLY_WEB=1 \
  cargo test --target wasm32-unknown-unknown
