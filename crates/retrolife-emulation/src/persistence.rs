use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static TEMPORARY_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

/// Replace a save file without exposing a partially written file to the core.
///
/// The temporary file is created beside the destination, flushed, and then
/// renamed into place. `create_new` keeps two concurrent writers from sharing
/// a temporary name. The caller owns session serialization; this function only
/// provides the filesystem boundary.
pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;

    let temporary = temporary_path(path);
    let write_result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)?;

        // Syncing the directory is supported on Unix and harmlessly skipped
        // elsewhere. The rename itself is the atomic visibility boundary.
        #[cfg(unix)]
        {
            let directory = OpenOptions::new().read(true).open(parent)?;
            directory.sync_all()?;
        }
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    write_result
}

fn temporary_path(destination: &Path) -> PathBuf {
    let sequence = TEMPORARY_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let name = destination
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("save");
    destination
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(format!(
            ".{name}.tmp-{stamp}-{}-{sequence}",
            std::process::id()
        ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_directory() -> PathBuf {
        let sequence = TEMPORARY_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "retrolife-emulation-test-{}-{sequence}",
            std::process::id()
        ))
    }

    #[test]
    fn atomic_write_replaces_destination_and_leaves_no_temporary_file() {
        let directory = test_directory();
        let destination = directory.join("nested").join("battery.srm");

        atomic_write(&destination, b"first").expect("first atomic write");
        atomic_write(&destination, b"second").expect("replacement atomic write");

        assert_eq!(fs::read(&destination).expect("destination"), b"second");
        let entries = fs::read_dir(destination.parent().expect("parent"))
            .expect("save directory")
            .collect::<Result<Vec<_>, _>>()
            .expect("directory entries");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].file_name(), "battery.srm");

        fs::remove_dir_all(directory).expect("test cleanup");
    }
}
