#!/usr/bin/env bats

# Test Entra ID tenant name and ID parsing from dsregcmd output

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

@test "Parse TenantName from dsregcmd output using line-by-line approach" {
    # This simulates the fix: process line by line to find TenantName
    result=$(echo "$DSREG_OUTPUT" | grep -i "TenantName" | sed -E 's/^[[:space:]]*TenantName[[:space:]]*:[[:space:]]*//' | tr -d '\r')
    
    [ "$result" = "contoso.microsoft.com" ]
}

@test "Parse TenantId from dsregcmd output using line-by-line approach" {
    # This simulates the fix: process line by line to find TenantId
    result=$(echo "$DSREG_OUTPUT" | grep -i "TenantId" | sed -E 's/^[[:space:]]*TenantId[[:space:]]*:[[:space:]]*//' | tr -d '\r')
    
    [ "$result" = "abcdef12-3456-7890-abcd-ef1234567890" ]
}

@test "Verify isWork detection with microsoft.com tenant" {
    tenant_name="contoso.microsoft.com"
    
    # Check if tenant name ends with microsoft.com
    if [[ "$tenant_name" == *microsoft.com ]]; then
        result="true"
    else
        result="false"
    fi
    
    [ "$result" = "true" ]
}

@test "Verify isWork detection with non-microsoft tenant" {
    tenant_name="contoso.com"
    
    # Check if tenant name ends with microsoft.com
    if [[ "$tenant_name" == *microsoft.com ]]; then
        result="true"
    else
        result="false"
    fi
    
    [ "$result" = "false" ]
}
