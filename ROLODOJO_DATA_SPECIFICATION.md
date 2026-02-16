# 💾 ROLODOJO Data & JSON Specification

## 1. The Rolo Object (Standard Payload)
Every Rolo entry in `tbl_rolos` must follow this JSON structure in the `data_payload` column to ensure cross-platform compatibility.

{
  "header": {
    "version": "1.0",
    "source_device": "User_Device_ID",
    "confidence_score": 1.0
  },
  "entities": [
    {
      "uri": "dojo.con.joe",
      "action": "UPDATE_ATTR",
      "attributes": {
        "coffee_preference": "Dark Roast",
        "last_seen": "2026-02-01T11:00:00Z"
      }
    }
  ],
  "context": {
    "location": "32.123, -95.456",
    "weather": "Clear",
    "trigger": "Manual_Entry"
  }
}

## 2. Formatting Standards
To prevent data fragmentation, the Sensei must enforce these formats:

| Data Type | Standard | Example |
| :--- | :--- | :--- |
| **Dates/Times** | ISO 8601 (UTC) | `2026-02-01T15:30:00Z` |
| **Phone Numbers** | E.164 Format | `+12345678900` |
| **Names** | Title Case | `Joe Smith` |
| **URIs** | Lowercase/Underscore | `dojo.con.joe_smith` |
| **Coordinates** | Decimal Degrees | `29.1234, -95.5678` |

## 3. User Profile Object (`tbl_user`)
Dedicated owner profile data is stored outside URI contact records:

{
  "user_id": "owner",
  "display_name": "Scott Bannert",
  "preferred_name": "Scott",
  "profile_json": {
    "timezone": "America/Chicago",
    "locale": "en_US"
  },
  "created_at": "2026-02-16T12:00:00Z",
  "updated_at": "2026-02-16T12:00:00Z"
}

## 4. Sensei Response Object (`tbl_sensei`)
Every user input should produce a stored Sensei response row:

{
  "sensei_id": "uuid-v4",
  "input_rolo_id": "uuid-v4",
  "target_uri": "dojo.con.joe",
  "response_text": "Updated Joe's Coffee Preference to Espresso",
  "provider": "llama",
  "model": "llama3.3",
  "confidence_score": 0.91,
  "created_at": "2026-02-16T12:01:00Z"
}

## 5. Attribute Vault Rules
- **Keys:** Use `snake_case` for all keys (e.g., `gate_code`, not `GateCode`).
- **Secret Data:** If an attribute is marked `is_encrypted: 1` in the database, the value must be encrypted via SQLCipher before storage.
- **Nullification:** When a user "removes" a fact, the value becomes `null` but the key remains to preserve the `last_rolo_id` audit link.

## 6. Conflict Resolution
- **Rule of Recency:** If two Rolos provide conflicting data for the same URI attribute, the Rolo with the latest `timestamp` wins.
- **History:** The previous value is moved to a `history` array within the record's payload before being overwritten.
- 
