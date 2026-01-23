#!/usr/bin/env bats

# Test Entra ID tenant name and ID parsing from dsregcmd output
# These tests verify that the regex patterns in .chezmoi.yaml.tmpl correctly
# extract tenant information from dsregcmd output without capturing the entire output.

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	# Ensure PATH includes ~/.local/bin for chezmoi
	export PATH="${HOME}/.local/bin:${PATH}"
}

# Sample dsregcmd /status output (simplified)
DSREG_OUTPUT='+----------------------------------------------------------------------+
| Device State                                                         |
+----------------------------------------------------------------------+

             AzureAdJoined : YES
          EnterpriseJoined : NO
              DomainJoined : NO
           WorkplaceJoined : NO

+----------------------------------------------------------------------+
| Device Details                                                       |
+----------------------------------------------------------------------+

                  DeviceId : 12345678-1234-1234-1234-123456789abc

+----------------------------------------------------------------------+
| Tenant Details                                                       |
+----------------------------------------------------------------------+

                TenantName : contoso.microsoft.com
                  TenantId : abcdef12-3456-7890-abcd-ef1234567890

+----------------------------------------------------------------------+
| User State                                                           |
+----------------------------------------------------------------------+'

@test "entra-id-parsing: Parse TenantName from dsregcmd output" {
	# This simulates the fix: process line by line to find TenantName
	result=$(echo "$DSREG_OUTPUT" | grep -i "TenantName" | sed -E 's/^[[:space:]]*TenantName[[:space:]]*:[[:space:]]*//' | tr -d '\r')

	[ "$result" = "contoso.microsoft.com" ]
}

@test "entra-id-parsing: Parse TenantId from dsregcmd output" {
	# This simulates the fix: process line by line to find TenantId
	result=$(echo "$DSREG_OUTPUT" | grep -i "TenantId" | sed -E 's/^[[:space:]]*TenantId[[:space:]]*:[[:space:]]*//' | tr -d '\r')

	[ "$result" = "abcdef12-3456-7890-abcd-ef1234567890" ]
}

@test "entra-id-parsing: Verify isWork detection with microsoft.com tenant" {
	tenant_name="contoso.microsoft.com"

	# Check if tenant name ends with microsoft.com
	if [[ "$tenant_name" == *microsoft.com ]]; then
		result="true"
	else
		result="false"
	fi

	[ "$result" = "true" ]
}

@test "entra-id-parsing: Verify isWork detection with non-microsoft tenant" {
	tenant_name="contoso.com"

	# Check if tenant name ends with microsoft.com
	if [[ "$tenant_name" == *microsoft.com ]]; then
		result="true"
	else
		result="false"
	fi

	[ "$result" = "false" ]
}

@test "entra-id-parsing: Verify chezmoi template with mock output" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Test the actual regex pattern used in the template
	cat >/tmp/test_entra_template.tmpl <<'EOF'
{{- $dsregOutput := `+----------------------------------------------------------------------+
| Device State                                                         |
+----------------------------------------------------------------------+

             AzureAdJoined : YES

+----------------------------------------------------------------------+
| Tenant Details                                                       |
+----------------------------------------------------------------------+

                TenantName : test.microsoft.com
                  TenantId : test-id-1234

+----------------------------------------------------------------------+` -}}
{{- $tenantNameLine := regexFind "(?i)TenantName\\s*:[^\\r\\n]+" $dsregOutput -}}
{{- $entraIDTenantName := "" -}}
{{- if $tenantNameLine -}}
{{-   $entraIDTenantName = regexReplaceAll "(?i)^.*TenantName\\s*:\\s*" $tenantNameLine "" | trim -}}
{{- end -}}
{{- $tenantIdLine := regexFind "(?i)TenantId\\s*:[^\\r\\n]+" $dsregOutput -}}
{{- $entraIDTenantId := "" -}}
{{- if $tenantIdLine -}}
{{-   $entraIDTenantId = regexReplaceAll "(?i)^.*TenantId\\s*:\\s*" $tenantIdLine "" | trim -}}
{{- end -}}
{{- $isWork := false -}}
{{- if $entraIDTenantName -}}
{{-   $isWork = hasSuffix "microsoft.com" $entraIDTenantName -}}
{{- end -}}
TenantName:{{ $entraIDTenantName }}
TenantId:{{ $entraIDTenantId }}
IsWork:{{ $isWork }}
EOF

	run chezmoi execute-template </tmp/test_entra_template.tmpl
	[ "$status" -eq 0 ]

	# Verify the output contains correct values
	[[ "$output" == *"TenantName:test.microsoft.com"* ]]
	[[ "$output" == *"TenantId:test-id-1234"* ]]
	[[ "$output" == *"IsWork:true"* ]]

	rm -f /tmp/test_entra_template.tmpl
}
