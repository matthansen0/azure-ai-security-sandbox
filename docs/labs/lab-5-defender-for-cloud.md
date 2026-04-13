# Lab 5: Defender for Cloud

**Objective:** Enable Microsoft Defender for Cloud plans, explore security recommendations, and understand how Defender protects each resource type in the sandbox.

**Time:** ~20 minutes

**Requires:** Base deployment + willingness to enable Defender plans (subscription-scoped billing)

> **Warning:** Defender plans are enabled at the **subscription level**. If you're using a shared subscription, these changes apply beyond this sandbox. Use a dedicated subscription or be prepared to roll back with `./scripts/disable-defender.sh --confirm`.

---

## Exercise 1: Check Current Defender Status

Before enabling anything, see what Defender plans are currently active.

```bash
# List all Defender plans and their status
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings?api-version=2023-01-01" \
  --query "value[].{plan: name, tier: properties.pricingTier, subPlan: properties.subPlan}" -o table 2>/dev/null || \
  az security pricing list --query "[].{plan: name, tier: pricingTier}" -o table
```

**What to look for:**
- Most plans should show `Free` (Defender not enabled)
- Any showing `Standard` are already enabled (possibly from prior setup)

---

## Exercise 2: Review the Enable Script

Before running any scripts, understand what they do.

```bash
# Read the script's help text
./scripts/enable-defender.sh --help
```

The script enables these plans (when the corresponding resources exist):

| Defender Plan | Protects | Enabled When |
|---|---|---|
| **Containers** | Container Apps, ACR | Always (Container Apps is core) |
| **StorageAccounts** | Blob storage + uploads | Storage account exists |
| **CosmosDbs** | Cosmos DB data plane | Cosmos DB endpoint exists |
| **Api** | API Management | APIM is deployed |

The script also applies **Defender for Storage advanced settings** to the sandbox storage account:
- **Malware scanning** on blob upload
- **Sensitive data discovery** (PII, PCI, PHI detection)

---

## Exercise 3: Enable Defender Plans

```bash
# Enable Defender plans for this sandbox
./scripts/enable-defender.sh --confirm
```

**What to observe:**
- Which plans get enabled (vs already enabled)
- The state file created under `.defender/` for rollback tracking
- Any plans skipped (e.g., `Api` if APIM isn't deployed)

Verify the new status:

```bash
# Check updated plan status
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings?api-version=2023-01-01" \
  --query "value[?properties.pricingTier == 'Standard'].{plan: name, tier: properties.pricingTier, subPlan: properties.subPlan}" -o table 2>/dev/null || \
  az security pricing list --query "[?pricingTier == 'Standard'].{plan: name, tier: pricingTier}" -o table
```

---

## Exercise 4: Explore Security Recommendations

After enabling Defender, Azure generates security recommendations for your resources.

```bash
# List security recommendations for the resource group
az security assessment list \
  --query "[?contains(resourceDetails.id, '${RG}')].{name: displayName, status: status.code, severity: metadata.severity}" \
  -o table 2>/dev/null || echo "Recommendations may take 15-30 minutes to appear after enabling Defender."
```

You can also check via ARM REST:

```bash
# Get security score for the subscription
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Security/secureScores/ascScore?api-version=2020-01-01" \
  --query "{score: properties.score.current, max: properties.score.max, percentage: properties.score.percentage}" -o json 2>/dev/null || echo "Secure score not yet available."
```

> **Note:** Security recommendations and scores take 15-30 minutes to populate after Defender plans are enabled.

---

## Exercise 5: Verify Defender for Storage Settings

Check that the storage account has advanced Defender settings applied.

```bash
STORAGE_NAME=$(azd env get-value AZURE_STORAGE_ACCOUNT 2>/dev/null || \
  az storage account list -g "$RG" --query "[0].name" -o tsv)
echo "Storage Account: $STORAGE_NAME"

# Check Defender for Storage settings on the specific storage account
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2022-12-01-preview" \
  --query "{enabled: properties.isEnabled, malwareScan: properties.malwareScanning.onUpload.isEnabled, sensitiveData: properties.sensitiveDataDiscovery.isEnabled}" -o json 2>/dev/null || \
  echo "Defender for Storage settings not yet applied. Run enable-defender.sh first."
```

**What to look for:**
- `enabled: true` — Defender for Storage is active on this account
- `malwareScan: true` — Files uploaded to blob storage are scanned for malware
- `sensitiveData: true` — Uploaded files are checked for PII, credit card numbers, etc.

---

## Exercise 6: Test Malware Scanning (Optional)

If Defender for Storage malware scanning is enabled, you can test it with the EICAR test file.

```bash
# Create the EICAR test file (standard antivirus test pattern, NOT actual malware)
EICAR='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'

# Upload to blob storage
STORAGE_KEY=$(az storage account keys list -g "$RG" -n "$STORAGE_NAME" --query "[0].value" -o tsv)
echo "$EICAR" | az storage blob upload \
  --account-name "$STORAGE_NAME" \
  --account-key "$STORAGE_KEY" \
  --container-name "content" \
  --name "test-eicar.txt" \
  --data "@-" \
  --overwrite 2>/dev/null && echo "EICAR test file uploaded" || echo "Upload may have been blocked by malware scanning"
```

> **Note:** Malware scanning results may take a few minutes to appear. Check Defender alerts in the Azure Portal under **Microsoft Defender for Cloud → Security Alerts**.

Clean up the test file:

```bash
az storage blob delete \
  --account-name "$STORAGE_NAME" \
  --account-key "$STORAGE_KEY" \
  --container-name "content" \
  --name "test-eicar.txt" 2>/dev/null
```

---

## Exercise 7: Roll Back Defender Plans

When you're done testing, you can disable the Defender plans that the enable script turned on.

```bash
# View what the enable script changed
cat .defender/defender-state-${AZURE_ENV_NAME}.json 2>/dev/null | jq . || echo "No state file found"

# Roll back the changes
./scripts/disable-defender.sh --confirm
```

**What to observe:**
- Only plans that were changed by the enable script get rolled back
- Plans that were already enabled before are left alone
- The state file tracks what was changed for safe rollback

---

## What You Learned

- Defender for Cloud plans are subscription-scoped (affect all resources in the subscription)
- The sandbox provides enable/disable scripts with state tracking for safe rollback
- Defender for Storage adds malware scanning and sensitive data discovery to blob uploads
- Security recommendations take 15-30 minutes to appear after enabling Defender
- Different Defender plans protect different resource types (Containers, Storage, Cosmos DB, APIs)
- The EICAR test file is a safe way to verify malware scanning is working

## Next Lab

Continue to [Lab 6: AI Agent Security](lab-6-ai-agent-security.md) to explore how the IT Admin Agent is secured.
