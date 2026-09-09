use serde::{Serialize, de::DeserializeOwned};
use serde_json::Value;

pub const SCHEMA_VERSION: u32 = 1;

pub fn parse_versioned<T: DeserializeOwned>(json: &str, label: &str) -> Result<T, String> {
    let value: Value = serde_json::from_str(json)
        .map_err(|error| format!("Cannot decode {label} JSON: {error}"))?;
    let version = value
        .get("schemaVersion")
        .and_then(Value::as_u64)
        .ok_or_else(|| format!("{label} schemaVersion is required"))?;

    if version != u64::from(SCHEMA_VERSION) {
        return Err(format!(
            "Unsupported {label} schemaVersion {version}; expected {SCHEMA_VERSION}"
        ));
    }

    serde_json::from_value(value).map_err(|error| format!("Cannot decode {label}: {error}"))
}

pub fn canonical_json<T: Serialize>(value: &T, label: &str) -> Result<String, String> {
    serde_json::to_string(value).map_err(|error| format!("Cannot encode {label}: {error}"))
}

pub fn validate_text(label: &str, value: &str, maximum: usize) -> Result<(), String> {
    let trimmed = value.trim();

    if trimmed.is_empty() {
        return Err(format!("{label} cannot be empty"));
    }
    if trimmed.len() > maximum {
        return Err(format!("{label} exceeds {maximum} bytes"));
    }
    if trimmed.chars().any(char::is_control) {
        return Err(format!("{label} contains a control character"));
    }

    Ok(())
}

pub fn validate_identifier(label: &str, value: &str, maximum: usize) -> Result<(), String> {
    validate_text(label, value, maximum)?;

    if !value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':'))
    {
        return Err(format!("{label} contains an unsupported character"));
    }

    Ok(())
}

pub fn validate_sha256(label: &str, value: &str) -> Result<(), String> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || matches!(byte, b'a'..=b'f'))
    {
        return Err(format!("{label} must be a lowercase SHA-256 hash"));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifiers_reject_paths_and_whitespace() {
        assert!(validate_identifier("id", "snes:chrono-trigger", 128).is_ok());
        assert!(validate_identifier("id", "../secret", 128).is_err());
        assert!(validate_identifier("id", "with space", 128).is_err());
    }

    #[test]
    fn sha256_validation_requires_lowercase_hex() {
        assert!(validate_sha256("hash", &"a".repeat(64)).is_ok());
        assert!(validate_sha256("hash", &"A".repeat(64)).is_err());
        assert!(validate_sha256("hash", "short").is_err());
    }
}
