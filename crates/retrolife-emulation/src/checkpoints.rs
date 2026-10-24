//! Bounded, atomic checkpoints. This store never reads or writes battery.srm.
use crate::persistence::atomic_write;
use crate::{EmulationError, VideoFrame};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::Read;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub const STATE_SLOTS: usize = 8;
pub const QUICK_SLOT: u8 = 6;
pub const RECOVERY_SLOT: u8 = 7;
pub(crate) const MAX_STATE_BYTES: usize = 32 * 1024 * 1024;
const MAX_METADATA_BYTES: usize = 16 * 1024;
const MAX_PREVIEW_SIDE: u32 = 512;
const MAX_PREVIEW_BYTES: usize = (MAX_PREVIEW_SIDE * MAX_PREVIEW_SIDE * 4) as usize;
const HEADER_BYTES: usize = 56;
const MAX_FILE_BYTES: usize =
    HEADER_BYTES + MAX_METADATA_BYTES + MAX_STATE_BYTES + MAX_PREVIEW_BYTES;
const MAGIC: &[u8; 8] = b"RTLSTATE";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct StateIdentity {
    pub system: String,
    pub rom_sha256: String,
    pub core_sha256: String,
    pub core_name: String,
    pub core_version: String,
    pub options_sha256: String,
    pub platform: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Metadata {
    schema_version: u32,
    slot: u8,
    created_at: u64,
    identity: StateIdentity,
    preview_width: u32,
    preview_height: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveStateSlot {
    pub slot: u8,
    pub occupied: bool,
    pub created_at: u64,
    pub preview_width: u32,
    pub preview_height: u32,
    pub compatible: bool,
    pub state_bytes: usize,
    pub error: String,
}

impl SaveStateSlot {
    fn empty(slot: u8) -> Self {
        Self {
            slot,
            occupied: false,
            created_at: 0,
            preview_width: 0,
            preview_height: 0,
            compatible: false,
            state_bytes: 0,
            error: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveStateOperation {
    pub id: u64,
    pub kind: String,
    pub slot: u8,
    pub status: String,
    pub error: String,
}

impl Default for SaveStateOperation {
    fn default() -> Self {
        Self {
            id: 0,
            kind: String::new(),
            slot: 0,
            status: "idle".into(),
            error: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveStatesSnapshot {
    pub supported: bool,
    pub busy: bool,
    pub slots: Vec<SaveStateSlot>,
    pub operation: SaveStateOperation,
    pub discontinuity: u64,
    /// False only after a failed restore and failed rollback. Existing battery
    /// files remain untouched; quitting can still release the unsafe core.
    pub can_resume: bool,
    #[serde(skip)]
    pub(crate) previews: Vec<Vec<u8>>,
}

impl Default for SaveStatesSnapshot {
    fn default() -> Self {
        Self {
            supported: false,
            busy: false,
            slots: (0..STATE_SLOTS as u8).map(SaveStateSlot::empty).collect(),
            operation: SaveStateOperation::default(),
            discontinuity: 0,
            can_resume: true,
            previews: vec![Vec::new(); STATE_SLOTS],
        }
    }
}

pub(crate) struct Checkpoint {
    metadata: Metadata,
    pub state: Vec<u8>,
    pub preview: Vec<u8>,
}

impl Checkpoint {
    pub fn preview_size(&self) -> (u32, u32) {
        (self.metadata.preview_width, self.metadata.preview_height)
    }
}

pub(crate) struct StateStore {
    directory: PathBuf,
    identity: StateIdentity,
}

fn invalid(message: &str) -> EmulationError {
    EmulationError::Checkpoint(message.to_owned())
}

impl StateStore {
    pub(crate) fn new(save_directory: PathBuf, identity: StateIdentity) -> Self {
        Self {
            directory: save_directory.join("states").join(&identity.rom_sha256),
            identity,
        }
    }

    fn path(&self, slot: u8) -> Result<PathBuf, EmulationError> {
        if usize::from(slot) >= STATE_SLOTS {
            return Err(invalid("Invalid checkpoint slot."));
        }
        Ok(self.directory.join(format!("slot-{slot}.rts")))
    }

    pub(crate) fn save(
        &self,
        slot: u8,
        state: Vec<u8>,
        frame: Option<&VideoFrame>,
    ) -> Result<Checkpoint, EmulationError> {
        let (preview, preview_width, preview_height) = preview(frame);
        let checkpoint = Checkpoint {
            metadata: Metadata {
                schema_version: 1,
                slot,
                created_at: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
                identity: self.identity.clone(),
                preview_width,
                preview_height,
            },
            state,
            preview,
        };
        let encoded = encode(&checkpoint)?;
        atomic_write(&self.path(slot)?, &encoded).map_err(|_| {
            invalid("The checkpoint save could not be confirmed. Check its slot before retrying.")
        })?;
        Ok(checkpoint)
    }

    fn read(&self, slot: u8) -> Result<Checkpoint, EmulationError> {
        let path = self.path(slot)?;
        let info = fs::symlink_metadata(&path)
            .map_err(|_| invalid("This checkpoint is missing or unreadable."))?;
        if !info.is_file() || info.len() > MAX_FILE_BYTES as u64 {
            return Err(invalid("The checkpoint file is invalid or too large."));
        }
        let file = File::open(path).map_err(|_| invalid("This checkpoint could not be opened."))?;
        let mut bytes = Vec::with_capacity(info.len() as usize);
        file.take(MAX_FILE_BYTES as u64 + 1)
            .read_to_end(&mut bytes)
            .map_err(|_| invalid("This checkpoint could not be read."))?;
        let checkpoint = decode(&bytes)?;
        if checkpoint.metadata.slot != slot {
            return Err(invalid("The checkpoint belongs to another slot."));
        }
        Ok(checkpoint)
    }

    pub(crate) fn load(&self, slot: u8) -> Result<Checkpoint, EmulationError> {
        let checkpoint = self.read(slot)?;
        if checkpoint.metadata.identity != self.identity {
            return Err(invalid(
                "This checkpoint uses different game bytes, core build, settings or platform.",
            ));
        }
        Ok(checkpoint)
    }

    pub(crate) fn refresh(&self, snapshot: &mut SaveStatesSnapshot) {
        for slot in 0..STATE_SLOTS as u8 {
            let index = usize::from(slot);
            snapshot.slots[index] = SaveStateSlot::empty(slot);
            snapshot.previews[index].clear();
            if !self
                .path(slot)
                .is_ok_and(|path| path.symlink_metadata().is_ok())
            {
                continue;
            }
            snapshot.slots[index].occupied = true;
            match self.read(slot) {
                Ok(checkpoint) => {
                    let compatible = checkpoint.metadata.identity == self.identity;
                    snapshot.slots[index] = SaveStateSlot {
                        slot,
                        occupied: true,
                        created_at: checkpoint.metadata.created_at,
                        preview_width: checkpoint.metadata.preview_width,
                        preview_height: checkpoint.metadata.preview_height,
                        compatible,
                        state_bytes: checkpoint.state.len(),
                        error: if compatible {
                            String::new()
                        } else {
                            "Different game, core build, settings or platform.".into()
                        },
                    };
                    snapshot.previews[index] = checkpoint.preview;
                }
                Err(error) => snapshot.slots[index].error = error.to_string(),
            }
        }
    }
}

fn preview(frame: Option<&VideoFrame>) -> (Vec<u8>, u32, u32) {
    let Some(frame) = frame else {
        return (Vec::new(), 0, 0);
    };
    let w = frame.info.width;
    let h = frame.info.height;
    if w == 0 || h == 0 || (u64::from(w) * u64::from(h) * 4) != frame.rgba.len() as u64 {
        return (Vec::new(), 0, 0);
    }
    let scale = 1.0_f64.min(f64::from(MAX_PREVIEW_SIDE) / f64::from(w.max(h)));
    let width = (f64::from(w) * scale).round().max(1.0) as u32;
    let height = (f64::from(h) * scale).round().max(1.0) as u32;
    let mut data = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        for x in 0..width {
            let source = (((u64::from(y) * u64::from(h) / u64::from(height)) * u64::from(w)
                + u64::from(x) * u64::from(w) / u64::from(width))
                * 4) as usize;
            data.extend_from_slice(&frame.rgba[source..source + 4]);
        }
    }
    (data, width, height)
}

fn encode(value: &Checkpoint) -> Result<Vec<u8>, EmulationError> {
    let metadata =
        serde_json::to_vec(&value.metadata).map_err(|_| invalid("Invalid checkpoint metadata."))?;
    if metadata.len() > MAX_METADATA_BYTES
        || value.state.is_empty()
        || value.state.len() > MAX_STATE_BYTES
        || value.preview.len() > MAX_PREVIEW_BYTES
    {
        return Err(invalid("The checkpoint exceeds its size limit."));
    }
    let mut payload = metadata;
    let metadata_len = payload.len();
    payload.extend_from_slice(&value.state);
    payload.extend_from_slice(&value.preview);
    let mut result = Vec::with_capacity(HEADER_BYTES + payload.len());
    result.extend_from_slice(MAGIC);
    result.extend_from_slice(&1_u32.to_le_bytes());
    result.extend_from_slice(&(metadata_len as u32).to_le_bytes());
    result.extend_from_slice(&(value.state.len() as u32).to_le_bytes());
    result.extend_from_slice(&(value.preview.len() as u32).to_le_bytes());
    result.extend_from_slice(&Sha256::digest(&payload));
    result.extend_from_slice(&payload);
    Ok(result)
}

fn decode(bytes: &[u8]) -> Result<Checkpoint, EmulationError> {
    if bytes.len() < HEADER_BYTES || bytes.len() > MAX_FILE_BYTES || &bytes[..8] != MAGIC {
        return Err(invalid("The checkpoint header is invalid."));
    }
    let read = |offset| {
        u32::from_le_bytes(
            bytes[offset..offset + 4]
                .try_into()
                .expect("bounded header"),
        ) as usize
    };
    let (meta_len, state_len, preview_len) = (read(12), read(16), read(20));
    if read(8) != 1
        || meta_len > MAX_METADATA_BYTES
        || state_len == 0
        || state_len > MAX_STATE_BYTES
        || preview_len > MAX_PREVIEW_BYTES
        || HEADER_BYTES + meta_len + state_len + preview_len != bytes.len()
    {
        return Err(invalid("The checkpoint sizes or format are invalid."));
    }
    let payload = &bytes[HEADER_BYTES..];
    if Sha256::digest(payload).as_slice() != &bytes[24..56] {
        return Err(invalid(
            "The checkpoint checksum does not match. No state was loaded.",
        ));
    }
    let metadata: Metadata = serde_json::from_slice(&payload[..meta_len])
        .map_err(|_| invalid("The checkpoint metadata is invalid."))?;
    if metadata.schema_version != 1
        || usize::from(metadata.slot) >= STATE_SLOTS
        || metadata.preview_width > MAX_PREVIEW_SIDE
        || metadata.preview_height > MAX_PREVIEW_SIDE
        || u64::from(metadata.preview_width) * u64::from(metadata.preview_height) * 4
            != preview_len as u64
        || (metadata.preview_width == 0) != (metadata.preview_height == 0)
    {
        return Err(invalid("The checkpoint preview is invalid."));
    }
    Ok(Checkpoint {
        metadata,
        state: payload[meta_len..meta_len + state_len].to_vec(),
        preview: payload[meta_len + state_len..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static SERIAL: AtomicU64 = AtomicU64::new(0);

    fn identity() -> StateIdentity {
        StateIdentity {
            system: "snes".into(),
            rom_sha256: "1".repeat(64),
            core_sha256: "2".repeat(64),
            core_name: "Fixture".into(),
            core_version: "1".into(),
            options_sha256: "3".repeat(64),
            platform: "fixture-platform".into(),
        }
    }
    fn directory() -> PathBuf {
        std::env::temp_dir().join(format!(
            "retrolife-checkpoint-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ))
    }
    fn frame() -> VideoFrame {
        let mut video = crate::transport::VideoSlot::new();
        video.publish(
            vec![12, 34, 56, 255, 78, 90, 123, 255],
            2,
            1,
            "rgba8888",
            0,
            false,
        );
        video.latest().unwrap()
    }

    #[test]
    fn checkpoint_roundtrip_persists_raw_preview_and_keeps_battery_untouched() {
        let root = directory();
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("battery.srm"), b"existing battery").unwrap();
        let store = StateStore::new(root.clone(), identity());
        store.save(0, vec![1, 2, 3], Some(&frame())).unwrap();
        let restored_store = StateStore::new(root.clone(), identity());
        let checkpoint = restored_store.load(0).unwrap();
        assert_eq!(checkpoint.state, [1, 2, 3]);
        assert_eq!(checkpoint.preview, frame().rgba);
        assert_eq!(checkpoint.preview_size(), (2, 1));
        assert_eq!(
            fs::read(root.join("battery.srm")).unwrap(),
            b"existing battery"
        );
        let mut list = SaveStatesSnapshot::default();
        restored_store.refresh(&mut list);
        assert!(list.slots[0].occupied && list.slots[0].compatible);
        assert!(!list.slots[1].occupied);
        assert_eq!(list.previews[0], frame().rgba);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn corrupt_truncated_appended_and_oversized_states_are_rejected() {
        let root = directory();
        let store = StateStore::new(root.clone(), identity());
        let checkpoint = store.save(6, vec![4; 64], Some(&frame())).unwrap();
        let encoded = encode(&checkpoint).unwrap();
        for cut in [0, 8, HEADER_BYTES - 1, encoded.len() - 1] {
            assert!(decode(&encoded[..cut]).is_err());
        }
        let mut corrupt = encoded.clone();
        *corrupt.last_mut().unwrap() ^= 1;
        assert!(decode(&corrupt).is_err());
        let mut appended = encoded.clone();
        appended.push(0);
        assert!(decode(&appended).is_err());
        let mut oversized = encoded;
        oversized[16..20].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(decode(&oversized).is_err());
        fs::write(store.path(6).unwrap(), corrupt).unwrap();
        assert!(store.load(6).is_err());
        let mut list = SaveStatesSnapshot::default();
        store.refresh(&mut list);
        assert!(list.slots[6].occupied && !list.slots[6].compatible);
        assert!(list.previews[6].is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn identity_binds_core_version_binary_settings_and_exact_content() {
        let root = directory();
        let original = identity();
        let store = StateStore::new(root.clone(), original.clone());
        store.save(2, vec![8], None).unwrap();
        for field in 0..5 {
            let mut changed = original.clone();
            match field {
                0 => changed.core_sha256 = "4".repeat(64),
                1 => changed.core_version = "2".into(),
                2 => changed.options_sha256 = "5".repeat(64),
                3 => changed.platform = "other-platform".into(),
                _ => changed.rom_sha256 = "6".repeat(64),
            }
            let other = StateStore::new(root.clone(), changed);
            assert!(other.load(2).is_err());
        }
        assert!(store.load(8).is_err());
        assert!(store.save(8, vec![1], None).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn failed_atomic_replace_preserves_existing_slot_and_cleans_temporary_file() {
        let root = directory();
        let store = StateStore::new(root.clone(), identity());
        store.save(0, vec![42], None).unwrap();
        let blocked = store.path(7).unwrap();
        fs::create_dir(&blocked).unwrap();
        assert!(store.save(7, vec![9], None).is_err());
        assert_eq!(store.load(0).unwrap().state, [42]);
        assert_eq!(fs::read_dir(&store.directory).unwrap().count(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn preview_is_bounded_and_never_filtered_or_shader_baked() {
        let mut frame = frame();
        frame.info.width = 1024;
        frame.info.height = 512;
        frame.rgba = [10, 20, 30, 255].repeat(1024 * 512);
        let (bytes, width, height) = preview(Some(&frame));
        assert_eq!((width, height), (512, 256));
        assert!(
            bytes
                .as_chunks::<4>()
                .0
                .iter()
                .all(|pixel| *pixel == [10, 20, 30, 255])
        );
        frame.rgba.pop();
        assert!(preview(Some(&frame)).0.is_empty());
    }
}
