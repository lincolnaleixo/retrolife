use crate::contracts::{SCHEMA_VERSION, canonical_json, parse_versioned};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum PreviewAudio {
    Muted,
    Enabled,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ScalingMode {
    Integer,
    Aspect,
    Stretch,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ShaderPreset {
    Nearest,
    SharpBilinear,
    Crt,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum LatencyMode {
    Balanced,
    Low,
    Stable,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum GlyphFamily {
    Auto,
    PlayStation,
    Nintendo,
    Xbox,
    Generic,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DisplaySettings {
    pub schema_version: u32,
    pub reduced_motion: bool,
    pub preview_audio: PreviewAudio,
    pub scaling_mode: ScalingMode,
    pub overscan_percent: u8,
    pub shader_preset: ShaderPreset,
    pub latency_mode: LatencyMode,
    pub glyph_family: GlyphFamily,
    pub text_scale_percent: u16,
    pub high_contrast: bool,
    pub safe_area_percent: u8,
}

impl Default for DisplaySettings {
    fn default() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            reduced_motion: false,
            preview_audio: PreviewAudio::Muted,
            scaling_mode: ScalingMode::Aspect,
            overscan_percent: 0,
            shader_preset: ShaderPreset::Nearest,
            latency_mode: LatencyMode::Balanced,
            glyph_family: GlyphFamily::Auto,
            text_scale_percent: 100,
            high_contrast: false,
            safe_area_percent: 3,
        }
    }
}

impl DisplaySettings {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported display settings schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        if self.overscan_percent > 10 {
            return Err("Display settings overscanPercent must be between 0 and 10".to_owned());
        }
        if !(80..=150).contains(&self.text_scale_percent) {
            return Err("Display settings textScalePercent must be between 80 and 150".to_owned());
        }
        if self.safe_area_percent > 10 {
            return Err("Display settings safeAreaPercent must be between 0 and 10".to_owned());
        }

        Ok(())
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyDisplaySettings {
    #[serde(default)]
    reduced_motion: bool,
    #[serde(default = "legacy_preview_muted")]
    preview_muted: bool,
    #[serde(default)]
    integer_scaling: bool,
    #[serde(default)]
    high_contrast: bool,
}

fn legacy_preview_muted() -> bool {
    true
}

pub fn decode(json: &str) -> Result<DisplaySettings, String> {
    let value: Value = serde_json::from_str(json)
        .map_err(|error| format!("Cannot decode display settings JSON: {error}"))?;
    let version = value
        .get("schemaVersion")
        .and_then(Value::as_u64)
        .ok_or_else(|| "Display settings schemaVersion is required".to_owned())?;

    let settings = match version {
        0 => {
            let legacy: LegacyDisplaySettings = serde_json::from_value(value)
                .map_err(|error| format!("Cannot decode legacy display settings: {error}"))?;

            DisplaySettings {
                reduced_motion: legacy.reduced_motion,
                preview_audio: if legacy.preview_muted {
                    PreviewAudio::Muted
                } else {
                    PreviewAudio::Enabled
                },
                scaling_mode: if legacy.integer_scaling {
                    ScalingMode::Integer
                } else {
                    ScalingMode::Aspect
                },
                high_contrast: legacy.high_contrast,
                ..DisplaySettings::default()
            }
        }
        1 => parse_versioned(json, "display settings")?,
        _ => {
            return Err(format!(
                "Unsupported display settings schemaVersion {version}; expected 0 or {SCHEMA_VERSION}"
            ));
        }
    };

    settings.validate()?;
    Ok(settings)
}

pub fn normalize_json(json: &str) -> Result<String, String> {
    canonical_json(&decode(json)?, "display settings")
}

pub fn default_json() -> String {
    canonical_json(&DisplaySettings::default(), "display settings")
        .expect("default display settings must always serialize")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn current_settings_round_trip_canonically() {
        let settings = DisplaySettings {
            reduced_motion: true,
            preview_audio: PreviewAudio::Enabled,
            scaling_mode: ScalingMode::Integer,
            ..DisplaySettings::default()
        };

        let json = canonical_json(&settings, "display settings").unwrap();
        assert_eq!(decode(&json).unwrap(), settings);
    }

    #[test]
    fn version_zero_migrates_without_losing_user_choices() {
        let migrated = decode(
            r#"{"schemaVersion":0,"reducedMotion":true,"previewMuted":false,"integerScaling":true,"highContrast":true}"#,
        )
        .unwrap();

        assert_eq!(migrated.schema_version, SCHEMA_VERSION);
        assert!(migrated.reduced_motion);
        assert_eq!(migrated.preview_audio, PreviewAudio::Enabled);
        assert_eq!(migrated.scaling_mode, ScalingMode::Integer);
        assert!(migrated.high_contrast);
        assert_eq!(migrated.safe_area_percent, 3);
    }

    #[test]
    fn corrupt_missing_future_unknown_and_out_of_range_values_are_safe() {
        assert!(
            normalize_json("nope")
                .unwrap_err()
                .contains("Cannot decode")
        );
        assert!(
            normalize_json(r#"{"reducedMotion":true}"#)
                .unwrap_err()
                .contains("schemaVersion is required")
        );
        assert!(
            normalize_json(r#"{"schemaVersion":4}"#)
                .unwrap_err()
                .contains("Unsupported")
        );

        let mut value = serde_json::to_value(DisplaySettings::default()).unwrap();
        value["futureField"] = serde_json::json!(true);
        assert!(normalize_json(&value.to_string()).is_ok());

        value["textScalePercent"] = serde_json::json!(200);
        assert!(
            normalize_json(&value.to_string())
                .unwrap_err()
                .contains("between 80 and 150")
        );
    }

    #[test]
    fn default_json_is_valid_and_canonical() {
        let json = default_json();
        let decoded = decode(&json).unwrap();

        assert_eq!(decoded, DisplaySettings::default());
        assert_eq!(normalize_json(&json).unwrap(), json);
    }
}
