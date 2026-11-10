#!/bin/sh
# launchd's datadog.otelcol: the native OpenTelemetry collector with the Datadog API key from the keychain.
DD_API_KEY=$(/usr/bin/security find-generic-password -s datadog-api-key -w) || exit 78
export DD_API_KEY
exec "$HOME/.local/opt/otelcol/otelcol-contrib" --config="$(dirname "$0")/otel.yaml"
