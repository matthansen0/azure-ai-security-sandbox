# Lab 5: Defender for Cloud

**Objective:** Enable Microsoft Defender for Cloud plans, explore security recommendations, and understand how Defender protects each resource type in the sandbox.

**Time:** ~20 minutes

**Requires:** Base deployment + willingness to enable Defender plans (subscription-scoped billing)

> **Warning:** Defender plans are enabled at the **subscription level**. If you're using a shared subscription, these changes apply beyond this sandbox. Use a dedicated subscription or be prepared to roll back with `./scripts/disable-defender.sh --confirm`.

---

## Exercise 1: Check Current Defender Status

1. In the Azure Portal, search for **Microsoft Defender for Cloud** in the top search bar.
2. Click **Environment settings** in the left menu.
3. Expand the management group hierarchy until you find your subscription. Click on it.
4. Review the list of Defender plans. Note which plans are **On** vs **Off**.

**What to look for:**
- Most plans should be **Off** (free tier)
- Any plans showing **On** were already enabled (possibly from prior setup)

---

## Exercise 2: Review the Enable Script

Before enabling Defender, understand what the provided script does. The script (`scripts/enable-defender.sh`) enables these plans:

| Defender Plan | Protects | Enabled When |
|---|---|---|
| **Containers** | Container Apps, ACR | Always (Container Apps is core) |
| **StorageAccounts** | Blob storage + uploads | Storage account exists |
| **CosmosDbs** | Cosmos DB data plane | Cosmos DB endpoint exists |
| **Api** | API Management | APIM is deployed |

It also applies **Defender for Storage advanced settings** to the sandbox storage account:
- **Malware scanning** on blob upload
- **Sensitive data discovery** (PII, PCI, PHI detection)

---

## Exercise 3: Enable Defender Plans

You can enable plans either via the Portal or using the provided script.

### Option A: Enable via Portal

1. In **Defender for Cloud** → **Environment settings** → your subscription.
2. Toggle the plans listed above to **On**.
3. Click **Save**.

### Option B: Enable via Script

```bash
./scripts/enable-defender.sh --confirm
```

This creates a state file under `.defender/` for safe rollback later.

### Verify

After enabling, return to **Environment settings** and confirm the relevant plans now show **On**.

---

## Exercise 4: Explore Security Recommendations

After enabling Defender, Azure generates security recommendations for your resources.

1. In **Microsoft Defender for Cloud**, click **Recommendations** in the left menu.
2. Use the **Resource group** filter to narrow to `rg-<your-env-name>`.
3. Browse the recommendations — they're grouped by severity (High, Medium, Low).
4. Click any recommendation to see details: affected resources, remediation steps, and compliance mapping.

> **Note:** Recommendations take **15-30 minutes** to appear after enabling Defender plans. If you don't see any yet, check the **Secure Score** → **Overview** page to see if your score has been calculated.

---

## Exercise 5: Verify Defender for Storage Settings

1. In the Azure Portal, go to your **Storage account** (named `st*` in your resource group).
2. In the left menu, go to **Security** → **Microsoft Defender for Storage**.
3. Check that:
   - **Defender for Storage** is **Enabled**
   - **On-upload malware scanning** is **On**
   - **Sensitive data threat detection** is **On**

<details>
<summary>Optional: CLI equivalent</summary>

```bash
STORAGE_NAME=$(az storage account list -g "$RG" --query "[0].name" -o tsv)

az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2022-12-01-preview" \
  --query "{enabled: properties.isEnabled, malwareScan: properties.malwareScanning.onUpload.isEnabled, sensitiveData: properties.sensitiveDataDiscovery.isEnabled}" -o json
```

</details>

---

## Exercise 6: Test Malware Scanning (Optional)

If malware scanning is enabled, test it with the standard EICAR test file.

1. Create a text file on your local machine named `test-eicar.txt` with this content (it's a harmless antivirus test pattern, **not** actual malware):
   ```
   X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
   ```
2. In the Portal, go to your **Storage account** → **Containers** → **content**.
3. Click **Upload** and upload `test-eicar.txt`.
4. Go to **Microsoft Defender for Cloud** → **Security alerts**.
5. After a few minutes, you should see an alert about the malware detection.
6. Delete the test file from the container when done.

<details>
<summary>Optional: CLI equivalent</summary>

```bash
STORAGE_NAME=$(az storage account list -g "$RG" --query "[0].name" -o tsv)
STORAGE_KEY=$(az storage account keys list -g "$RG" -n "$STORAGE_NAME" --query "[0].value" -o tsv)
EICAR='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'

echo "$EICAR" | az storage blob upload \
  --account-name "$STORAGE_NAME" --account-key "$STORAGE_KEY" \
  --container-name "content" --name "test-eicar.txt" --data "@-" --overwrite

# Clean up
az storage blob delete \
  --account-name "$STORAGE_NAME" --account-key "$STORAGE_KEY" \
  --container-name "content" --name "test-eicar.txt"
```

</details>

---

## Exercise 7: Roll Back Defender Plans

When you're done testing, disable the plans to stop billing.

### Option A: Disable via Portal

1. Go to **Defender for Cloud** → **Environment settings** → your subscription.
2. Toggle the plans you enabled back to **Off**.
3. Click **Save**.

### Option B: Disable via Script

```bash
./scripts/disable-defender.sh --confirm
```

The script only rolls back plans that were changed by `enable-defender.sh` (tracked in the `.defender/` state file). Plans already enabled before are left alone.

---

## What You Learned

- Defender for Cloud plans are **subscription-scoped** (affect all resources in the subscription)
- The sandbox provides enable/disable scripts with **state tracking** for safe rollback
- Defender for Storage adds **malware scanning** and **sensitive data discovery** to blob uploads
- Security **recommendations** take 15-30 minutes to appear after enabling Defender
- Different Defender plans protect different resource types (Containers, Storage, Cosmos DB, APIs)
- The **EICAR test file** is a safe way to verify malware scanning is working

## Next Lab

Continue to [Lab 6: AI Agent Security](lab-6-ai-agent-security.md) to explore how the IT Admin Agent is secured, or skip to [Lab 7: Defender for AI](lab-7-defender-for-ai.md) for AI-specific threat detection.
