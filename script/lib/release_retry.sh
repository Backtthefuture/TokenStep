#!/usr/bin/env bash
# Shared retry helper for Apple-side release steps.
#
# Apple's notarization/ticket services (notarytool, stapler, Gatekeeper ticket
# lookup via api.apple-cloudkit.com) occasionally fail with transient network
# errors: `NSURLErrorDomain Code=-1005`, "network connection was lost", or
# "Error 68". Those are retried with a 20s / 40s / 60s backoff.
#
# Deterministic failures (invalid signature, missing ticket, rejected
# notarization) do not match the markers below, so they fail immediately with
# the original output and are never hidden behind retries.

RETRY_DELAYS=(20 40 60)

is_transient_apple_failure() {
  local output="$1"
  case "$output" in
    *"Error 68"*) return 0 ;;
    *"Code=-1005"*) return 0 ;;
    *"NSURLErrorDomain"*) return 0 ;;
    *"network connection was lost"*) return 0 ;;
    *"api.apple-cloudkit.com"*) return 0 ;;
    *"CloudKit"*) return 0 ;;
  esac
  return 1
}

# retry_transient <label> <command...>
#
# Runs the command, retrying only on the transient Apple service errors above.
# Prints the attempt number and a short error summary on each failed attempt,
# replays the command output on success, and reprints the original output
# before failing once all attempts are exhausted.
retry_transient() {
  local label="$1"
  shift
  local attempt=1
  local max_attempts=$(( ${#RETRY_DELAYS[@]} + 1 ))
  local output=""
  while (( attempt <= max_attempts )); do
    if output="$("$@" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi
    printf '%s failed on attempt %d/%d: %s\n' \
      "$label" "$attempt" "$max_attempts" \
      "$(printf '%s\n' "$output" | /usr/bin/tail -n 3 | /usr/bin/tr '\n' ' ')" >&2
    if ! is_transient_apple_failure "$output"; then
      printf '%s\n' "$output" >&2
      return 1
    fi
    if (( attempt == max_attempts )); then
      printf '%s\n' "$output" >&2
      printf '%s still failing after %d attempts; giving up.\n' "$label" "$max_attempts" >&2
      return 1
    fi
    /bin/sleep "${RETRY_DELAYS[$(( attempt - 1 ))]}"
    attempt=$(( attempt + 1 ))
  done
}
