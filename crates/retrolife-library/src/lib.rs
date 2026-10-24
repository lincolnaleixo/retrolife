//! Durable, app-managed storage for user-owned SNES ROM files.
//!
//! The library copies an input `.sfc` or `.smc` file into its own `snes/`
//! directory. The input is never moved, renamed, or deleted. Imported files
//! keep readable filenames; SHA-256 remains the internal identity for duplicate
//! detection and progress. Renamed copies are reconnected by verified contents.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// The largest source file accepted by [`Library::import`].
///
/// This is deliberately larger than ordinary SNES ROM sizes so that valid
/// enhancement and homebrew images can still be imported, while preventing a
/// mistaken path from consuming unbounded disk space.
pub const MAX_ROM_SIZE_BYTES: u64 = 32 * 1024 * 1024;

/// The smallest accepted SNES image.
///
/// This rejects empty/text fixtures while keeping the boundary focused on
/// storage rather than attempting to authenticate ROM headers. `.smc` copier
/// headers are preserved as part of the copied bytes.
pub const MIN_ROM_SIZE_BYTES: u64 = 32 * 1024;

/// The metadata filename inside an opened library directory.
pub const METADATA_FILE_NAME: &str = "library.json";

/// The directory containing app-managed ROM copies.
pub const ROMS_DIRECTORY_NAME: &str = "snes";

const METADATA_VERSION: u32 = 1;
const JOURNAL_FILE_NAME: &str = ".import-journal.json";
const STAGING_SUFFIX: &str = ".part";
const SHA256_HEX_LENGTH: usize = 64;
const MAX_TITLE_CHARS: usize = 200;
const COPY_BUFFER_SIZE: usize = 64 * 1024;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// An item in the library index.
///
/// `path` is always relative to the directory passed to [`Library::open`].
/// Keeping it relative makes metadata portable and avoids persisting the
/// caller's private absolute filesystem path.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Entry {
    /// Lowercase SHA-256 of the imported file contents.
    pub id: String,
    /// A display title derived from the source filename stem.
    pub title: String,
    /// Relative path to the app-managed copy.
    pub path: PathBuf,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    version: u32,
    entries: Vec<Entry>,
}

impl Default for Metadata {
    fn default() -> Self {
        Self {
            version: METADATA_VERSION,
            entries: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ImportJournal {
    version: u32,
    id: String,
    title: String,
    path: PathBuf,
    staging_path: PathBuf,
}

/// Errors returned by the library boundary.
///
/// Error messages intentionally identify operations and safe basenames only;
/// they do not echo caller-provided absolute paths into logs or UI.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Error {
    /// The library root could not be used as a directory.
    InvalidLibraryPath { reason: &'static str },
    /// The requested source does not exist.
    SourceNotFound { name: String },
    /// The requested source exists but is not a regular file.
    SourceNotRegularFile { name: String },
    /// The source is not an `.sfc` or `.smc` file.
    UnsupportedExtension { name: String },
    /// The source is empty.
    EmptySource { name: String },
    /// The source is non-empty but below the minimum SNES image size.
    FileTooSmall { size: u64, min: u64 },
    /// The source exceeds the configured import limit.
    FileTooLarge { size: u64, max: u64 },
    /// The source changed while it was being copied.
    SourceChanged,
    /// The SHA-256 identity already exists in the index.
    Duplicate { id: String },
    /// A managed destination conflicts with another file.
    StorageConflict { id: String },
    /// Another process left an import journal that cannot be safely recovered.
    InterruptedImport { reason: String },
    /// A managed entry points to a missing file.
    ManagedFileMissing { id: String },
    /// A managed file no longer matches its SHA-256 identity.
    ManagedFileCorrupt { id: String },
    /// The JSON metadata could not be read.
    MetadataUnreadable { reason: String },
    /// The JSON metadata was readable but violated the library contract.
    MetadataInvalid { reason: String },
    /// An operating-system operation failed.
    Io {
        operation: &'static str,
        kind: io::ErrorKind,
    },
    /// The in-process import gate was poisoned.
    LockPoisoned,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidLibraryPath { reason } => {
                write!(f, "The library directory cannot be used: {reason}.")
            }
            Self::SourceNotFound { name } => write!(
                f,
                "The source file '{name}' was not found; check the selected file and try again."
            ),
            Self::SourceNotRegularFile { name } => write!(
                f,
                "The source '{name}' is not a regular file; select an .sfc or .smc file."
            ),
            Self::UnsupportedExtension { name } => write!(
                f,
                "The source '{name}' has an unsupported extension; use .sfc or .smc."
            ),
            Self::EmptySource { name } => write!(
                f,
                "The source '{name}' is empty; select a complete .sfc or .smc file."
            ),
            Self::FileTooSmall { size, min } => write!(
                f,
                "The source is {size} bytes, below the {min}-byte minimum for a SNES image."
            ),
            Self::FileTooLarge { size, max } => write!(
                f,
                "The source is {size} bytes, above the {max}-byte import limit."
            ),
            Self::SourceChanged => write!(
                f,
                "The source changed while it was being imported; retry from the original file."
            ),
            Self::Duplicate { id } => write!(
                f,
                "This file is already in the library (SHA-256 identity {id})."
            ),
            Self::StorageConflict { id } => write!(
                f,
                "The managed destination for identity {id} conflicts with another file; repair the library before retrying."
            ),
            Self::InterruptedImport { reason } => write!(
                f,
                "An interrupted import could not be recovered: {reason}. Reopen the library after checking its permissions and free space."
            ),
            Self::ManagedFileMissing { .. } => write!(
                f,
                "A ROM could not be found in the library. Reconnect its drive or restore the file to the console folder. Renamed ROMs are recognized automatically."
            ),
            Self::ManagedFileCorrupt { id } => write!(
                f,
                "Library entry {id} no longer matches its SHA-256 identity; restore the original copy."
            ),
            Self::MetadataUnreadable { reason } => write!(
                f,
                "Library metadata could not be read: {reason}. Restore a valid {METADATA_FILE_NAME} before retrying."
            ),
            Self::MetadataInvalid { reason } => write!(
                f,
                "Library metadata is invalid: {reason}. Repair {METADATA_FILE_NAME} before retrying."
            ),
            Self::Io { operation, kind } => write!(
                f,
                "The library could not complete {operation} ({kind}); check permissions and free space."
            ),
            Self::LockPoisoned => write!(
                f,
                "The library import operation is unavailable because a previous operation failed unexpectedly."
            ),
        }
    }
}

impl std::error::Error for Error {}

/// A durable library rooted at an application-owned directory.
#[derive(Clone, Debug)]
pub struct Library {
    root: PathBuf,
    gate: Arc<Mutex<()>>,
}

impl Library {
    /// Open or create a library at `path`.
    ///
    /// The directory contains `library.json` and an app-managed `roms/`
    /// subdirectory. Any interrupted import journal is recovered before this
    /// method returns.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let root = path.as_ref().to_path_buf();
        ensure_volume_available(&root)?;
        if root.exists() && !root.is_dir() {
            return Err(Error::InvalidLibraryPath {
                reason: "the selected path is not a directory",
            });
        }

        fs::create_dir_all(&root)
            .map_err(|error| map_io("creating the library directory", error))?;
        let roms = root.join(ROMS_DIRECTORY_NAME);
        fs::create_dir_all(&roms)
            .map_err(|error| map_io("creating the managed ROM directory", error))?;

        let library = Self {
            root,
            gate: Arc::new(Mutex::new(())),
        };

        let (mut metadata, metadata_missing) = library.load_metadata()?;
        let recovered = library.recover_interrupted(&mut metadata)?;
        let reconnected = library.reconnect_renamed(&mut metadata)?;
        library.validate_metadata(&metadata)?;

        if metadata_missing || recovered || reconnected {
            library.write_metadata(&metadata)?;
        }

        Ok(library)
    }

    /// Copy a source `.sfc` or `.smc` into the app-managed library.
    ///
    /// The source is read-only throughout the operation. The copied file is
    /// staged, flushed, atomically renamed into `roms/`, and then recorded in
    /// atomically replaced JSON metadata. SHA-256 is both the entry identity
    /// and the duplicate key.
    pub fn import(&self, source: impl AsRef<Path>) -> Result<Entry> {
        let _guard = self.gate.lock().map_err(|_| Error::LockPoisoned)?;
        let source = source.as_ref();
        let source_name = safe_name(source);
        let source_metadata = match fs::metadata(source) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Err(Error::SourceNotFound { name: source_name });
            }
            Err(error) => return Err(map_io("reading the source file", error)),
        };

        if !source_metadata.file_type().is_file() {
            return Err(Error::SourceNotRegularFile { name: source_name });
        }
        let extension = supported_extension(source).ok_or_else(|| Error::UnsupportedExtension {
            name: source_name.clone(),
        })?;
        validate_source_size(source_metadata.len(), &source_name)?;

        let (id, original_size) = hash_source(source, &source_name)?;
        let mut metadata = self.load_and_recover()?;
        if metadata.entries.iter().any(|entry| entry.id == id) {
            return Err(Error::Duplicate { id });
        }

        let title = title_from_source(source).ok_or_else(|| Error::UnsupportedExtension {
            name: source_name.clone(),
        })?;
        let relative_path = self.available_rom_path(&title, extension)?;
        let final_path = self.root.join(&relative_path);
        match fs::symlink_metadata(&final_path) {
            Ok(final_metadata) => {
                if final_metadata.file_type().is_symlink() {
                    return Err(Error::StorageConflict { id });
                }
                if !final_metadata.file_type().is_file() {
                    return Err(Error::StorageConflict { id });
                }
                let (existing_id, _) = hash_managed_file(&final_path)?;
                if existing_id == id {
                    return Err(Error::Duplicate { id });
                }
                return Err(Error::StorageConflict { id });
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(map_io("checking the managed destination", error)),
        }

        let staging_relative_path = staging_relative_path(&id);
        let staging_path = self.root.join(&staging_relative_path);

        let journal = ImportJournal {
            version: METADATA_VERSION,
            id: id.clone(),
            title: title.clone(),
            path: relative_path.clone(),
            staging_path: staging_relative_path,
        };

        if self.journal_path().exists() {
            return Err(Error::InterruptedImport {
                reason: "another import is already being recovered".to_owned(),
            });
        }

        copy_to_staging(source, &staging_path, original_size, &id, &source_name)?;
        if let Err(error) = self.write_journal(&journal) {
            let _ = fs::remove_file(&staging_path);
            return Err(error);
        }

        if let Err(error) = fs::rename(&staging_path, &final_path)
            .map_err(|error| map_io("committing the imported ROM", error))
            .and_then(|_| sync_directory(&self.root.join(ROMS_DIRECTORY_NAME)))
        {
            if !path_exists(&final_path) {
                let _ = fs::remove_file(&staging_path);
                let _ = fs::remove_file(self.journal_path());
            }
            return Err(error);
        }

        let entry = Entry {
            id,
            title,
            path: relative_path,
        };
        metadata.entries.push(entry.clone());
        // Keep the durable file and journal for recovery when metadata fails.
        self.validate_metadata(&metadata)
            .and_then(|_| self.write_metadata(&metadata))?;

        let _ = fs::remove_file(self.journal_path());
        let _ = sync_directory(&self.root);
        Ok(entry)
    }

    /// Return all indexed entries in insertion order.
    pub fn list(&self) -> Result<Vec<Entry>> {
        let _guard = self.gate.lock().map_err(|_| Error::LockPoisoned)?;
        Ok(self.load_and_recover()?.entries)
    }

    /// Alias for [`Library::list`] for callers that prefer noun-style naming.
    pub fn entries(&self) -> Result<Vec<Entry>> {
        self.list()
    }

    /// Resolve an entry's relative managed path inside this library.
    pub fn resolve(&self, entry: &Entry) -> Result<PathBuf> {
        validate_entry_shape(entry)?;
        let _guard = self.gate.lock().map_err(|_| Error::LockPoisoned)?;
        let metadata = self.load_and_recover()?;
        let current = metadata
            .entries
            .iter()
            .find(|item| item.id == entry.id)
            .ok_or_else(|| Error::ManagedFileMissing {
                id: entry.id.clone(),
            })?;
        Ok(self.root.join(&current.path))
    }

    /// Verify a complete copy before callers switch roots. Source files are
    /// deliberately retained, so interruption and cancellation are recoverable.
    pub fn copy_to(&self, destination: impl AsRef<Path>) -> Result<usize> {
        let entries = self.list()?;
        let target = Self::open(destination)?;
        for entry in &entries {
            match target.import(self.resolve(entry)?) {
                Ok(_) | Err(Error::Duplicate { .. }) => {}
                Err(error) => return Err(error),
            }
        }
        let _guard = target.gate.lock().map_err(|_| Error::LockPoisoned)?;
        let mut metadata = target.load_and_recover()?;
        for entry in &entries {
            if let Some(copied) = metadata.entries.iter_mut().find(|item| item.id == entry.id) {
                copied.title.clone_from(&entry.title);
            }
        }
        target.validate_metadata(&metadata)?;
        target.write_metadata(&metadata)?;
        Ok(entries.len())
    }

    fn load_and_recover(&self) -> Result<Metadata> {
        let (mut metadata, metadata_missing) = self.load_metadata()?;
        let recovered = self.recover_interrupted(&mut metadata)?;
        let reconnected = self.reconnect_renamed(&mut metadata)?;
        self.validate_metadata(&metadata)?;
        if metadata_missing || recovered || reconnected {
            self.write_metadata(&metadata)?;
        }
        Ok(metadata)
    }

    fn available_rom_path(&self, title: &str, extension: &str) -> Result<PathBuf> {
        // Keep names portable between Mac, Windows and shared storage, while
        // retaining the recognizable title. Bound UTF-8 bytes, not just chars.
        let mut stem = String::new();
        for character in title.chars() {
            let character = if "<>:\"/\\|?*".contains(character) {
                '_'
            } else {
                character
            };
            if stem.len() + character.len_utf8() > 180 {
                break;
            }
            stem.push(character);
        }
        let stem = stem.trim_matches([' ', '.']);
        let stem = if stem.is_empty() { "Game" } else { stem };
        for suffix in 0..10_000 {
            let name = if suffix == 0 {
                format!("{stem}.{extension}")
            } else {
                format!("{stem} ({suffix}).{extension}")
            };
            let relative = Path::new(ROMS_DIRECTORY_NAME).join(name);
            match fs::symlink_metadata(self.root.join(&relative)) {
                Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(relative),
                Err(error) => return Err(map_io("checking a ROM filename", error)),
                Ok(_) => {}
            }
        }
        Err(Error::MetadataInvalid {
            reason: "too many files share this game name".to_owned(),
        })
    }

    fn reconnect_renamed(&self, metadata: &mut Metadata) -> Result<bool> {
        let mut missing = HashSet::new();
        for entry in &metadata.entries {
            validate_entry_shape(entry)?;
            self.validate_rom_directory(&entry.path)?;
            match fs::symlink_metadata(self.root.join(&entry.path)) {
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    missing.insert(entry.id.clone());
                }
                Err(error) => return Err(map_io("checking a managed ROM", error)),
                Ok(_) => {}
            }
        }
        if missing.is_empty() {
            return Ok(false);
        }

        // Search only the two supported, direct console folders, never arbitrary
        // paths or symlinks. A matching filename is not evidence of game identity.
        let mut candidates = Vec::new();
        for directory in [ROMS_DIRECTORY_NAME, "roms"] {
            self.validate_rom_directory(&Path::new(directory).join("probe.sfc"))?;
            let files = match fs::read_dir(self.root.join(directory)) {
                Ok(files) => files,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(map_io("looking for renamed ROMs", error)),
            };
            for file in files {
                let file = file.map_err(|error| map_io("looking for renamed ROMs", error))?;
                let info = fs::symlink_metadata(file.path())
                    .map_err(|error| map_io("checking a renamed ROM", error))?;
                if info.is_file()
                    && supported_extension(&file.path()).is_some()
                    && (MIN_ROM_SIZE_BYTES..=MAX_ROM_SIZE_BYTES).contains(&info.len())
                {
                    candidates.push(Path::new(directory).join(file.file_name()));
                }
            }
        }
        candidates.sort();
        let mut changed = false;
        for path in candidates {
            let (id, _) = hash_managed_file(&self.root.join(&path))?;
            if missing.remove(&id) {
                for entry in metadata.entries.iter_mut().filter(|entry| entry.id == id) {
                    entry.path.clone_from(&path);
                }
                changed = true;
                if missing.is_empty() {
                    break;
                }
            }
        }
        Ok(changed)
    }

    fn validate_rom_directory(&self, relative: &Path) -> Result<()> {
        let directory =
            self.root
                .join(relative.parent().ok_or_else(|| Error::MetadataInvalid {
                    reason: "a ROM path has no console folder".to_owned(),
                })?);
        if is_symlink(&directory)? {
            return Err(Error::MetadataInvalid {
                reason: "a console folder is a symbolic link".to_owned(),
            });
        }
        Ok(())
    }

    fn load_metadata(&self) -> Result<(Metadata, bool)> {
        let path = self.metadata_path();
        let content = match fs::read_to_string(path) {
            Ok(content) => content,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok((Metadata::default(), true));
            }
            Err(error) => return Err(map_io("reading library metadata", error)),
        };

        let metadata: Metadata =
            serde_json::from_str(&content).map_err(|error| Error::MetadataUnreadable {
                reason: compact_reason(&error.to_string()),
            })?;
        if metadata.version != METADATA_VERSION {
            return Err(Error::MetadataInvalid {
                reason: format!("unsupported metadata version {}", metadata.version),
            });
        }
        Ok((metadata, false))
    }

    fn validate_metadata(&self, metadata: &Metadata) -> Result<()> {
        if metadata.version != METADATA_VERSION {
            return Err(Error::MetadataInvalid {
                reason: format!("unsupported metadata version {}", metadata.version),
            });
        }

        let mut ids = HashSet::with_capacity(metadata.entries.len());
        for entry in &metadata.entries {
            validate_entry_shape(entry)?;
            self.validate_rom_directory(&entry.path)?;
            if !ids.insert(entry.id.clone()) {
                return Err(Error::MetadataInvalid {
                    reason: format!("duplicate entry identity {}", entry.id),
                });
            }

            let managed_path = self.root.join(&entry.path);
            let file_metadata = match fs::symlink_metadata(&managed_path) {
                Ok(file_metadata) => file_metadata,
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    return Err(Error::ManagedFileMissing {
                        id: entry.id.clone(),
                    });
                }
                Err(error) => return Err(map_io("checking a managed ROM", error)),
            };
            if file_metadata.file_type().is_symlink() {
                return Err(Error::MetadataInvalid {
                    reason: "a managed entry points through a symbolic link".to_owned(),
                });
            }
            if !file_metadata.file_type().is_file() {
                return Err(Error::ManagedFileMissing {
                    id: entry.id.clone(),
                });
            }
            validate_managed_size(file_metadata.len())?;
            let (actual_id, _) = hash_managed_file(&managed_path)?;
            if actual_id != entry.id {
                return Err(Error::ManagedFileCorrupt {
                    id: entry.id.clone(),
                });
            }
        }
        Ok(())
    }

    fn recover_interrupted(&self, metadata: &mut Metadata) -> Result<bool> {
        let journal_path = self.journal_path();
        if !journal_path.exists() {
            remove_stale_staging_files(&self.root.join(ROMS_DIRECTORY_NAME))?;
            return Ok(false);
        }

        let journal_content = fs::read_to_string(&journal_path)
            .map_err(|error| map_io("reading the import recovery journal", error))?;
        let journal: ImportJournal =
            serde_json::from_str(&journal_content).map_err(|error| Error::InterruptedImport {
                reason: format!(
                    "the recovery journal is invalid ({})",
                    compact_reason(&error.to_string())
                ),
            })?;
        validate_journal_shape(&journal)?;
        self.validate_rom_directory(&journal.path)?;

        let final_path = self.root.join(&journal.path);
        let staging_path = self.root.join(&journal.staging_path);
        let metadata_entry = metadata.entries.iter().find(|entry| entry.id == journal.id);

        if let Some(entry) = metadata_entry {
            if entry.path != journal.path {
                return Err(Error::InterruptedImport {
                    reason: "the journal and metadata refer to different destinations".to_owned(),
                });
            }
            if is_symlink(&final_path)? {
                return Err(Error::InterruptedImport {
                    reason: "the interrupted destination is a symbolic link".to_owned(),
                });
            }
            if !path_exists(&final_path) && path_exists(&staging_path) {
                fs::rename(&staging_path, &final_path)
                    .map_err(|error| map_io("finishing the interrupted ROM move", error))?;
                sync_directory(&self.root.join(ROMS_DIRECTORY_NAME))?;
            }
            if !path_exists(&final_path) {
                return Err(Error::ManagedFileMissing { id: journal.id });
            }
            verify_managed_identity(&final_path, &journal.id)?;
        } else if path_exists(&final_path) {
            if is_symlink(&final_path)? {
                return Err(Error::InterruptedImport {
                    reason: "the interrupted destination is a symbolic link".to_owned(),
                });
            }
            verify_managed_identity(&final_path, &journal.id)?;
            metadata.entries.push(Entry {
                id: journal.id.clone(),
                title: journal.title.clone(),
                path: journal.path.clone(),
            });
        } else if path_exists(&staging_path) {
            verify_managed_identity(&staging_path, &journal.id)?;
            fs::rename(&staging_path, &final_path)
                .map_err(|error| map_io("finishing the interrupted ROM move", error))?;
            sync_directory(&self.root.join(ROMS_DIRECTORY_NAME))?;
            metadata.entries.push(Entry {
                id: journal.id.clone(),
                title: journal.title.clone(),
                path: journal.path.clone(),
            });
        } else {
            // The journal was durable before the staged file was created, or
            // the user removed an unfinished import. It is safe to discard the
            // journal because no metadata entry points at a missing file.
        }

        let _ = fs::remove_file(&staging_path);
        fs::remove_file(&journal_path)
            .map_err(|error| map_io("clearing the import recovery journal", error))?;
        sync_directory(&self.root)?;
        Ok(true)
    }

    fn write_journal(&self, journal: &ImportJournal) -> Result<()> {
        let bytes =
            serde_json::to_vec_pretty(journal).map_err(|error| Error::MetadataUnreadable {
                reason: compact_reason(&error.to_string()),
            })?;
        write_atomic_bytes(
            &self.journal_path(),
            &bytes,
            "writing the import recovery journal",
        )
    }

    fn write_metadata(&self, metadata: &Metadata) -> Result<()> {
        let mut bytes =
            serde_json::to_vec_pretty(metadata).map_err(|error| Error::MetadataUnreadable {
                reason: compact_reason(&error.to_string()),
            })?;
        bytes.push(b'\n');
        write_atomic_bytes(&self.metadata_path(), &bytes, "writing library metadata")
    }

    fn metadata_path(&self) -> PathBuf {
        self.root.join(METADATA_FILE_NAME)
    }

    fn journal_path(&self) -> PathBuf {
        self.root.join(JOURNAL_FILE_NAME)
    }
}

/// Convenient result type for library operations.
pub type Result<T> = std::result::Result<T, Error>;

fn validate_source_size(size: u64, name: &str) -> Result<()> {
    if size == 0 {
        return Err(Error::EmptySource {
            name: name.to_owned(),
        });
    }
    if size < MIN_ROM_SIZE_BYTES {
        return Err(Error::FileTooSmall {
            size,
            min: MIN_ROM_SIZE_BYTES,
        });
    }
    validate_managed_size(size)
}

fn validate_managed_size(size: u64) -> Result<()> {
    if size > MAX_ROM_SIZE_BYTES {
        return Err(Error::FileTooLarge {
            size,
            max: MAX_ROM_SIZE_BYTES,
        });
    }
    Ok(())
}

fn supported_extension(path: &Path) -> Option<&'static str> {
    let extension = path.extension()?.to_str()?.to_ascii_lowercase();
    match extension.as_str() {
        "sfc" => Some("sfc"),
        "smc" => Some("smc"),
        _ => None,
    }
}

fn title_from_source(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_str()?.trim();
    let title: String = stem
        .chars()
        .filter(|character| !character.is_control())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if title.is_empty() || title.chars().count() > MAX_TITLE_CHARS {
        None
    } else {
        Some(title)
    }
}

/// Do not recreate a missing removable volume on the system disk.
fn ensure_volume_available(path: &Path) -> Result<()> {
    let parts: Vec<_> = path.components().collect();
    if path.starts_with("/Volumes") && parts.len() >= 3 {
        let volume: PathBuf = parts[..3].iter().collect();
        if !volume.is_dir() {
            return Err(Error::InvalidLibraryPath {
                reason: "the selected volume is offline; reconnect it or choose another folder",
            });
        }
    }
    Ok(())
}

fn staging_relative_path(id: &str) -> PathBuf {
    Path::new(ROMS_DIRECTORY_NAME).join(format!(".{id}{STAGING_SUFFIX}"))
}

fn validate_entry_shape(entry: &Entry) -> Result<()> {
    if !is_sha256_id(&entry.id) {
        return Err(Error::MetadataInvalid {
            reason: "an entry has an invalid SHA-256 identity".to_owned(),
        });
    }
    if entry.title.is_empty()
        || entry.title.chars().count() > MAX_TITLE_CHARS
        || entry.title.chars().any(char::is_control)
    {
        return Err(Error::MetadataInvalid {
            reason: "an entry has an invalid title".to_owned(),
        });
    }

    let components: Vec<Component<'_>> = entry.path.components().collect();
    if components.len() != 2
        || !["snes", "roms"]
            .iter()
            .any(|directory| components[0] == Component::Normal(Path::new(directory).as_os_str()))
    {
        return Err(Error::MetadataInvalid {
            reason: "an entry path must stay inside the managed roms directory".to_owned(),
        });
    }

    let filename = match components[1] {
        Component::Normal(filename) => filename.to_string_lossy(),
        _ => {
            return Err(Error::MetadataInvalid {
                reason: "an entry path must name a regular managed file".to_owned(),
            });
        }
    };
    if filename.contains(['\\', ':'])
        || filename.chars().any(char::is_control)
        || supported_extension(&entry.path).is_none()
    {
        return Err(Error::MetadataInvalid {
            reason: "an entry path must name a SNES ROM inside its console folder".to_owned(),
        });
    }
    Ok(())
}

fn validate_journal_shape(journal: &ImportJournal) -> Result<()> {
    if journal.version != METADATA_VERSION || !is_sha256_id(&journal.id) {
        return Err(Error::InterruptedImport {
            reason: "the journal version or identity is invalid".to_owned(),
        });
    }
    validate_entry_shape(&Entry {
        id: journal.id.clone(),
        title: journal.title.clone(),
        path: journal.path.clone(),
    })
    .map_err(|_| Error::InterruptedImport {
        reason: "the journal destination is outside the managed ROM layout".to_owned(),
    })?;
    if journal.staging_path != staging_relative_path(&journal.id)
        && journal.staging_path
            != Path::new("roms").join(format!(".{}{STAGING_SUFFIX}", journal.id))
    {
        return Err(Error::InterruptedImport {
            reason: "the journal staging file is outside the managed ROM layout".to_owned(),
        });
    }
    if journal.title.is_empty()
        || journal.title.chars().count() > MAX_TITLE_CHARS
        || journal.title.chars().any(char::is_control)
    {
        return Err(Error::InterruptedImport {
            reason: "the journal title is invalid".to_owned(),
        });
    }
    Ok(())
}

fn is_sha256_id(id: &str) -> bool {
    id.len() == SHA256_HEX_LENGTH
        && id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn hash_source(path: &Path, name: &str) -> Result<(String, u64)> {
    let mut file = File::open(path).map_err(|error| {
        if error.kind() == io::ErrorKind::NotFound {
            Error::SourceNotFound {
                name: name.to_owned(),
            }
        } else {
            map_io("opening the source file", error)
        }
    })?;
    hash_reader(&mut file, "reading the source file")
}

fn hash_managed_file(path: &Path) -> Result<(String, u64)> {
    let mut file = File::open(path).map_err(|error| map_io("reading a managed ROM", error))?;
    hash_reader(&mut file, "reading a managed ROM")
}

fn verify_managed_identity(path: &Path, expected_id: &str) -> Result<()> {
    let metadata =
        fs::symlink_metadata(path).map_err(|error| map_io("checking an interrupted ROM", error))?;
    if metadata.file_type().is_symlink() {
        return Err(Error::InterruptedImport {
            reason: "the interrupted file is a symbolic link".to_owned(),
        });
    }
    if !metadata.file_type().is_file() {
        return Err(Error::InterruptedImport {
            reason: "the interrupted destination is not a regular file".to_owned(),
        });
    }
    validate_managed_size(metadata.len())?;
    let (actual_id, _) = hash_managed_file(path)?;
    if actual_id != expected_id {
        return Err(Error::InterruptedImport {
            reason: "the interrupted file failed its SHA-256 identity check".to_owned(),
        });
    }
    Ok(())
}

fn hash_reader(reader: &mut impl Read, operation: &'static str) -> Result<(String, u64)> {
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; COPY_BUFFER_SIZE];
    let mut size = 0u64;
    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|error| map_io(operation, error))?;
        if read == 0 {
            break;
        }
        size = size.saturating_add(read as u64);
        validate_managed_size(size)?;
        hasher.update(&buffer[..read]);
    }
    Ok((hex_digest(&hasher.finalize()), size))
}

fn copy_to_staging(
    source: &Path,
    staging: &Path,
    expected_size: u64,
    expected_id: &str,
    source_name: &str,
) -> Result<()> {
    let result = (|| {
        let mut input = File::open(source).map_err(|error| {
            if error.kind() == io::ErrorKind::NotFound {
                Error::SourceNotFound {
                    name: source_name.to_owned(),
                }
            } else {
                map_io("opening the source for import", error)
            }
        })?;
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(staging)
            .map_err(|error| map_io("creating the import staging file", error))?;
        let mut buffer = [0u8; COPY_BUFFER_SIZE];
        let mut hasher = Sha256::new();
        let mut copied = 0u64;
        loop {
            let read = input
                .read(&mut buffer)
                .map_err(|error| map_io("reading the source for import", error))?;
            if read == 0 {
                break;
            }
            output
                .write_all(&buffer[..read])
                .map_err(|error| map_io("writing the imported ROM", error))?;
            hasher.update(&buffer[..read]);
            copied = copied.saturating_add(read as u64);
        }
        output
            .sync_all()
            .map_err(|error| map_io("flushing the imported ROM", error))?;
        drop(output);

        let copied_id = hex_digest(&hasher.finalize());
        if copied != expected_size || copied_id != expected_id {
            return Err(Error::SourceChanged);
        }
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(staging);
    }
    result
}

fn write_atomic_bytes(path: &Path, bytes: &[u8], operation: &'static str) -> Result<()> {
    let parent = path.parent().ok_or(Error::InvalidLibraryPath {
        reason: "the library path has no parent directory",
    })?;
    let filename = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("library-file");
    let temp_name = format!(
        ".{filename}.tmp-{}-{}",
        std::process::id(),
        TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let temp_path = parent.join(temp_name);

    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)
            .map_err(|error| map_io(operation, error))?;
        file.write_all(bytes)
            .map_err(|error| map_io(operation, error))?;
        file.sync_all().map_err(|error| map_io(operation, error))?;
        drop(file);
        fs::rename(&temp_path, path).map_err(|error| map_io(operation, error))?;
        sync_directory(parent)
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

fn remove_stale_staging_files(roms: &Path) -> Result<()> {
    let entries =
        fs::read_dir(roms).map_err(|error| map_io("checking import staging files", error))?;
    for entry in entries {
        let entry = entry.map_err(|error| map_io("checking import staging files", error))?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') && name.ends_with(STAGING_SUFFIX) {
            let file_type = entry
                .file_type()
                .map_err(|error| map_io("checking import staging files", error))?;
            if file_type.is_file() {
                fs::remove_file(entry.path())
                    .map_err(|error| map_io("cleaning an interrupted import", error))?;
            }
        }
    }
    Ok(())
}

fn safe_name(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| {
            let cleaned: String = name
                .chars()
                .filter(|character| !character.is_control())
                .collect();
            if cleaned.is_empty() {
                "selected source".to_owned()
            } else {
                cleaned
            }
        })
        .unwrap_or_else(|| "selected source".to_owned())
}

fn compact_reason(reason: &str) -> String {
    reason
        .chars()
        .filter(|character| !character.is_control())
        .take(240)
        .collect()
}

fn hex_digest(digest: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(digest.len() * 2);
    for byte in digest {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn map_io(operation: &'static str, error: io::Error) -> Error {
    Error::Io {
        operation,
        kind: error.kind(),
    }
}

fn path_exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

fn is_symlink(path: &Path) -> Result<bool> {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_symlink())
        .or_else(|error| {
            if error.kind() == io::ErrorKind::NotFound {
                Ok(false)
            } else {
                Err(map_io("checking a managed path", error))
            }
        })
}

fn sync_directory(path: &Path) -> Result<()> {
    match File::open(path).and_then(|file| file.sync_all()) {
        Ok(()) => Ok(()),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::Unsupported
                    | io::ErrorKind::PermissionDenied
                    | io::ErrorKind::InvalidInput
            ) =>
        {
            Ok(())
        }
        Err(error) => Err(map_io("flushing library metadata", error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(label: &str) -> Self {
            let counter = TEST_COUNTER.fetch_add(1, Ordering::Relaxed);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("clock before epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "retrolife-library-{label}-{}-{counter}-{nanos}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("create test directory");
            Self { path }
        }

        fn file(&self, name: &str, bytes: &[u8]) -> PathBuf {
            let path = self.path.join(name);
            fs::write(&path, bytes).expect("write test source");
            path
        }

        fn rom(&self, name: &str, marker: &[u8]) -> (PathBuf, Vec<u8>) {
            let mut bytes = vec![0u8; MIN_ROM_SIZE_BYTES as usize];
            bytes[..marker.len()].copy_from_slice(marker);
            (self.file(name, &bytes), bytes)
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn copy_is_verified_retryable_and_preserves_title_identity_and_source() {
        let temp = TestDir::new("copy");
        let (rom, bytes) = temp.rom("Adventure.sfc", b"copy fixture");
        let source = Library::open(temp.path.join("source")).unwrap();
        let original = source.import(rom).unwrap();
        let destination = temp.path.join("destination");
        assert_eq!(source.copy_to(&destination).unwrap(), 1);
        assert_eq!(source.copy_to(&destination).unwrap(), 1);
        let target = Library::open(destination).unwrap();
        let copied = &target.list().unwrap()[0];
        assert_eq!(copied.title, "Adventure");
        assert_eq!(copied.id, original.id);
        assert_eq!(copied.path.parent(), Some(Path::new("snes")));
        assert_eq!(fs::read(target.resolve(copied).unwrap()).unwrap(), bytes);
        assert_eq!(fs::read(source.resolve(&original).unwrap()).unwrap(), bytes);
    }

    #[test]
    fn legacy_roms_layout_is_read_without_moving_files() {
        let temp = TestDir::new("legacy");
        let (rom, _) = temp.rom("Old game.sfc", b"legacy fixture");
        let root = temp.path.join("library");
        let library = Library::open(&root).unwrap();
        let mut entry = library.import(rom).unwrap();
        fs::create_dir(root.join("roms")).unwrap();
        let old_path = Path::new("roms").join(entry.path.file_name().unwrap());
        fs::rename(root.join(&entry.path), root.join(&old_path)).unwrap();
        entry.path = old_path;
        library
            .write_metadata(&Metadata {
                version: 1,
                entries: vec![entry.clone()],
            })
            .unwrap();
        assert_eq!(Library::open(root).unwrap().list().unwrap(), vec![entry]);
    }

    #[test]
    fn offline_volume_is_never_created_on_the_internal_disk() {
        let path = Path::new("/Volumes/retrolife-offline-test-volume/ROMs");
        if !Path::new("/Volumes/retrolife-offline-test-volume").exists() {
            assert!(matches!(
                Library::open(path),
                Err(Error::InvalidLibraryPath { .. })
            ));
            assert!(!path.exists());
        }
    }

    #[test]
    fn imports_a_copy_and_lists_relative_identity_entry() {
        let temp = TestDir::new("import");
        let (source, source_bytes) = temp.rom("Example Game.sfc", b"fixture bytes");
        let library_path = temp.path.join("library");
        let library = Library::open(&library_path).expect("open library");

        let entry = library.import(&source).expect("import source");
        assert_eq!(entry.title, "Example Game");
        assert_eq!(entry.path.parent(), Some(Path::new(ROMS_DIRECTORY_NAME)));
        assert!(!entry.path.is_absolute());
        assert_eq!(fs::read(&source).expect("read original"), source_bytes);
        assert_eq!(
            fs::read(library.resolve(&entry).expect("resolve entry")).expect("read copy"),
            source_bytes
        );
        assert_eq!(library.list().expect("list entries"), vec![entry]);
        let reopened = Library::open(&library_path).expect("reopen library");
        assert_eq!(reopened.list().expect("list persisted entry").len(), 1);
        let metadata = fs::read_to_string(library_path.join(METADATA_FILE_NAME))
            .expect("read persisted metadata");
        assert!(!metadata.contains(temp.path.to_string_lossy().as_ref()));
    }

    #[test]
    fn duplicate_content_is_rejected_even_when_the_filename_differs() {
        let temp = TestDir::new("duplicate");
        let (first, source_bytes) = temp.rom("first.sfc", b"same content");
        let second = temp.file("second.smc", &source_bytes);
        let library = Library::open(temp.path.join("library")).expect("open library");
        let first_entry = library.import(&first).expect("first import");

        let error = library.import(&second).expect_err("duplicate should fail");
        assert_eq!(
            error,
            Error::Duplicate {
                id: first_entry.id.clone()
            }
        );
        assert_eq!(library.list().expect("list entries").len(), 1);
        assert_eq!(
            fs::read(&second).expect("read second original"),
            source_bytes
        );
    }

    #[test]
    fn readable_names_disambiguate_different_games_without_overwriting() {
        let temp = TestDir::new("readable-collisions");
        let (source, first_bytes) = temp.rom("Example Game.sfc", b"first game");
        let library = Library::open(temp.path.join("library")).unwrap();
        let first = library.import(&source).unwrap();
        let (_, second_bytes) = temp.rom("Example Game.sfc", b"second game");
        let second = library.import(&source).unwrap();
        assert_eq!(first.path, Path::new("snes/Example Game.sfc"));
        assert_eq!(second.path, Path::new("snes/Example Game (1).sfc"));
        assert_ne!(first.id, second.id);
        assert_eq!(
            fs::read(library.resolve(&first).unwrap()).unwrap(),
            first_bytes
        );
        assert_eq!(
            fs::read(library.resolve(&second).unwrap()).unwrap(),
            second_bytes
        );
    }

    #[test]
    fn renamed_rom_reconnects_live_and_on_restart_without_changing_identity_or_title() {
        let temp = TestDir::new("rename");
        let (source, bytes) = temp.rom("Adventure.sfc", b"rename fixture");
        let root = temp.path.join("library");
        let library = Library::open(&root).unwrap();
        let original = library.import(source).unwrap();
        let renamed = Path::new("snes/My Adventure.SFC");
        fs::rename(root.join(&original.path), root.join(renamed)).unwrap();
        // Launches can hold an Entry from before the Finder rename.
        assert_eq!(library.resolve(&original).unwrap(), root.join(renamed));
        let updated = library.list().unwrap().remove(0);
        assert_eq!(updated.id, original.id);
        assert_eq!(updated.title, original.title);
        assert_eq!(updated.path, renamed);
        assert_eq!(fs::read(root.join(renamed)).unwrap(), bytes);
        let second_name = Path::new("snes/Another Name.smc");
        fs::rename(root.join(renamed), root.join(second_name)).unwrap();
        let reopened = Library::open(&root).unwrap();
        assert_eq!(reopened.list().unwrap()[0].path, second_name);
        assert_eq!(reopened.list().unwrap()[0].id, original.id);
        assert!(!root.join(&original.path).exists());
    }

    #[test]
    fn legacy_hash_filename_can_be_renamed_and_copied_with_identity_intact() {
        let temp = TestDir::new("hash-rename");
        let (source, _) = temp.rom("Classic.sfc", b"old library fixture");
        let root = temp.path.join("library");
        let library = Library::open(&root).unwrap();
        let mut entry = library.import(source).unwrap();
        let legacy_path = Path::new("snes").join(format!("{}.sfc", entry.id));
        fs::rename(root.join(&entry.path), root.join(&legacy_path)).unwrap();
        entry.path = legacy_path;
        library
            .write_metadata(&Metadata {
                version: 1,
                entries: vec![entry.clone()],
            })
            .unwrap();
        let legacy = Library::open(&root).unwrap();
        assert_eq!(legacy.list().unwrap()[0], entry);
        fs::rename(root.join(&entry.path), root.join("snes/Classic.sfc")).unwrap();
        let target_root = temp.path.join("copy");
        assert_eq!(legacy.copy_to(&target_root).unwrap(), 1);
        let copied = Library::open(target_root)
            .unwrap()
            .list()
            .unwrap()
            .remove(0);
        assert_eq!(copied.id, entry.id);
        assert_eq!(copied.title, entry.title);
        assert_eq!(copied.path, Path::new("snes/Classic.sfc"));
    }

    #[test]
    fn renamed_recovery_never_adopts_different_content_or_mutates_failed_metadata() {
        let temp = TestDir::new("wrong-rename");
        let (source, _) = temp.rom("Game.sfc", b"original");
        let root = temp.path.join("library");
        let library = Library::open(&root).unwrap();
        let entry = library.import(source).unwrap();
        let before = fs::read(root.join(METADATA_FILE_NAME)).unwrap();
        fs::remove_file(root.join(&entry.path)).unwrap();
        let (_, other) = temp.rom("Other.sfc", b"different game");
        fs::write(root.join("snes/Renamed.sfc"), other).unwrap();
        assert!(matches!(
            Library::open(&root),
            Err(Error::ManagedFileMissing { .. })
        ));
        assert_eq!(fs::read(root.join(METADATA_FILE_NAME)).unwrap(), before);
    }

    #[cfg(unix)]
    #[test]
    fn rename_recovery_rejects_symlinks_and_parent_escape() {
        use std::os::unix::fs::symlink;
        let temp = TestDir::new("unsafe-rename");
        let (source, _) = temp.rom("Game.sfc", b"outside content");
        let root = temp.path.join("library");
        let library = Library::open(&root).unwrap();
        let entry = library.import(&source).unwrap();
        fs::remove_file(root.join(&entry.path)).unwrap();
        symlink(&source, root.join("snes/Renamed.sfc")).unwrap();
        assert!(matches!(
            Library::open(&root),
            Err(Error::ManagedFileMissing { .. })
        ));
        for invalid in [
            "../Game.sfc",
            "snes/../../Game.sfc",
            "/Game.sfc",
            "snes/..\\Game.sfc",
        ] {
            let mut forged = entry.clone();
            forged.path = PathBuf::from(invalid);
            assert!(validate_entry_shape(&forged).is_err());
        }
        fs::rename(root.join("snes"), root.join("elsewhere")).unwrap();
        symlink(root.join("elsewhere"), root.join("snes")).unwrap();
        assert!(matches!(
            Library::open(&root),
            Err(Error::MetadataInvalid { .. })
        ));
    }

    #[test]
    fn invalid_sources_return_actionable_errors_without_full_paths() {
        let temp = TestDir::new("invalid");
        let library = Library::open(temp.path.join("library")).expect("open library");
        let missing = temp.path.join("private-folder").join("missing.bin");
        let error = library
            .import(&missing)
            .expect_err("missing source should fail");
        assert!(matches!(error, Error::SourceNotFound { .. }));
        assert!(
            !error
                .to_string()
                .contains(temp.path.to_string_lossy().as_ref())
        );

        let invalid = temp.file("notes.txt", b"not a ROM");
        assert!(matches!(
            library.import(&invalid),
            Err(Error::UnsupportedExtension { .. })
        ));

        let empty = temp.file("empty.sfc", b"");
        assert!(matches!(
            library.import(&empty),
            Err(Error::EmptySource { .. })
        ));

        let tiny = temp.file("tiny.sfc", b"too small");
        assert!(matches!(
            library.import(&tiny),
            Err(Error::FileTooSmall {
                size: 9,
                min: MIN_ROM_SIZE_BYTES
            })
        ));
    }

    #[test]
    fn recovers_an_interrupted_staged_import() {
        let temp = TestDir::new("interrupted");
        let library_path = temp.path.join("library");
        let _library = Library::open(&library_path).expect("open library");
        let mut bytes = vec![0u8; MIN_ROM_SIZE_BYTES as usize];
        bytes[..b"interrupted fixture".len()].copy_from_slice(b"interrupted fixture");
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        let id = hex_digest(&hasher.finalize());
        let relative_path = Path::new(ROMS_DIRECTORY_NAME).join(format!("{id}.sfc"));
        let staging_relative_path = staging_relative_path(&id);
        let staging_path = library_path.join(&staging_relative_path);
        fs::write(&staging_path, bytes).expect("write staged import");
        let journal = ImportJournal {
            version: METADATA_VERSION,
            id: id.clone(),
            title: "Interrupted Fixture".to_owned(),
            path: relative_path,
            staging_path: staging_relative_path,
        };
        fs::write(
            library_path.join(JOURNAL_FILE_NAME),
            serde_json::to_vec(&journal).expect("serialize journal"),
        )
        .expect("write journal");

        let reopened = Library::open(&library_path).expect("recover library");
        let entries = reopened.list().expect("list recovered entry");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].id, id);
        assert!(library_path.join(&entries[0].path).is_file());
        assert!(!library_path.join(JOURNAL_FILE_NAME).exists());
        assert!(!staging_path.exists());
    }

    #[test]
    fn a_missing_managed_file_is_reported_instead_of_silently_recreated() {
        let temp = TestDir::new("missing-managed");
        let (source, _) = temp.rom("game.sfc", b"managed bytes");
        let library_path = temp.path.join("library");
        let library = Library::open(&library_path).expect("open library");
        let entry = library.import(&source).expect("import source");
        fs::remove_file(library.resolve(&entry).expect("resolve entry"))
            .expect("remove managed copy");

        let error = Library::open(&library_path).expect_err("missing managed file should fail");
        assert_eq!(
            error,
            Error::ManagedFileMissing {
                id: entry.id.clone()
            }
        );
    }

    #[test]
    fn rejects_a_file_above_the_import_bound_without_reading_it() {
        let temp = TestDir::new("large");
        let source = temp.path.join("large.sfc");
        let file = File::create(&source).expect("create sparse source");
        file.set_len(MAX_ROM_SIZE_BYTES + 1)
            .expect("create bounded oversized source");
        let library = Library::open(temp.path.join("library")).expect("open library");

        assert!(matches!(
            library.import(&source),
            Err(Error::FileTooLarge { size, max })
                if size == MAX_ROM_SIZE_BYTES + 1 && max == MAX_ROM_SIZE_BYTES
        ));
    }
}
