//! Core compatibility binds code/data, not the replaceable macOS signing envelope.
//! Unsupported executable layouts deliberately retain their full-file hash.
use crate::EmulationError;
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::Read;
use std::path::Path;

const MAX_CORE_BYTES: usize = 256 * 1024 * 1024;
const MACH_64: u32 = 0xfeedfacf;
const CPU_ARM64: u32 = 0x0100000c;
const CPU_X86_64: u32 = 0x01000007;

pub(crate) fn hash_core_file(path: &Path) -> Result<String, EmulationError> {
    let file = File::open(path).map_err(|_| identity_error())?;
    let mut bytes = Vec::new();
    file.take(MAX_CORE_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| identity_error())?;
    if bytes.len() > MAX_CORE_BYTES {
        return Err(identity_error());
    }
    Ok(fingerprint(&bytes))
}

fn identity_error() -> EmulationError {
    EmulationError::Checkpoint(
        "The core binary could not be identified within its size limit.".into(),
    )
}

fn fingerprint(bytes: &[u8]) -> String {
    let canonical = native_slice(bytes).and_then(canonical_mach64);
    format!(
        "{:x}",
        Sha256::digest(canonical.as_deref().unwrap_or(bytes))
    )
}

fn little32(bytes: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(at..at.checked_add(4)?)?.try_into().ok()?,
    ))
}
fn little64(bytes: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_le_bytes(
        bytes.get(at..at.checked_add(8)?)?.try_into().ok()?,
    ))
}
fn big32(bytes: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_be_bytes(
        bytes.get(at..at.checked_add(4)?)?.try_into().ok()?,
    ))
}
fn big64(bytes: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_be_bytes(
        bytes.get(at..at.checked_add(8)?)?.try_into().ok()?,
    ))
}

// Only the architecture dyld executes contributes to a universal core's state
// format. A universal file with ambiguous/unsupported slices uses its exact hash.
fn native_slice(bytes: &[u8]) -> Option<&[u8]> {
    if little32(bytes, 0)? == MACH_64 {
        return Some(bytes);
    }
    let fat64 = match big32(bytes, 0)? {
        0xcafebabe => false,
        0xcafebabf => true,
        _ => return None,
    };
    let target = match std::env::consts::ARCH {
        "aarch64" => CPU_ARM64,
        "x86_64" => CPU_X86_64,
        _ => return None,
    };
    let count = big32(bytes, 4)? as usize;
    if count == 0 || count > 32 {
        return None;
    }
    let entry = if fat64 { 32 } else { 20 };
    let table_end = 8 + count * entry;
    bytes.get(..table_end)?;
    let mut found = None;
    let mut ranges = Vec::new();
    for index in 0..count {
        let at = 8 + index * entry;
        let cpu = big32(bytes, at)?;
        let (offset, size) = if fat64 {
            (big64(bytes, at + 8)?, big64(bytes, at + 16)?)
        } else {
            (
                u64::from(big32(bytes, at + 8)?),
                u64::from(big32(bytes, at + 12)?),
            )
        };
        let start = usize::try_from(offset).ok()?;
        let end = start.checked_add(usize::try_from(size).ok()?)?;
        if start < table_end
            || end <= start
            || ranges
                .iter()
                .any(|&(left, right)| start < right && end > left)
        {
            return None;
        }
        let slice = bytes.get(start..end)?;
        ranges.push((start, end));
        if cpu == target {
            if found.is_some() || little32(slice, 4)? != target {
                return None;
            }
            found = Some(slice);
        }
    }
    found
}

fn canonical_mach64(bytes: &[u8]) -> Option<Vec<u8>> {
    if little32(bytes, 0)? != MACH_64 || bytes.len() < 32 {
        return None;
    }
    let page_size = match little32(bytes, 4)? {
        CPU_ARM64 => 16384_u64,
        CPU_X86_64 => 4096_u64,
        _ => return None,
    };
    let count = little32(bytes, 16)? as usize;
    let commands_size = little32(bytes, 20)? as usize;
    if count > 4096 {
        return None;
    }
    let commands_end = 32_usize.checked_add(commands_size)?;
    bytes.get(..commands_end)?;
    let mut at = 32;
    let mut signature = None;
    let mut linkedit = None;
    for index in 0..count {
        let kind = little32(bytes, at)?;
        let size = little32(bytes, at + 4)? as usize;
        let end = at.checked_add(size)?;
        if size < 8 || !size.is_multiple_of(8) || end > commands_end {
            return None;
        }
        if kind == 0x1d {
            // Current Apple linkers put this last. Refuse to normalize a novel
            // layout rather than risk discarding an unrelated command or data.
            if signature.is_some() || size != 16 || index + 1 != count {
                return None;
            }
            signature = Some((
                at,
                little32(bytes, at + 8)? as usize,
                little32(bytes, at + 12)? as usize,
            ));
        }
        if kind == 0x19 && bytes.get(at + 8..at + 24)? == b"__LINKEDIT\0\0\0\0\0\0" {
            if linkedit.is_some() || size != 72 || little32(bytes, at + 64)? != 0 {
                return None;
            }
            linkedit = Some(at);
        }
        at = end;
    }
    if at != commands_end {
        return None;
    }
    let Some((command, signature_start, signature_size)) = signature else {
        return Some(bytes.to_vec());
    };
    if signature_size == 0
        || signature_start < commands_end
        || signature_start.checked_add(signature_size)? != bytes.len()
    {
        return None;
    }
    let segment = linkedit?;
    let file_start = little64(bytes, segment + 40)?;
    let file_size = little64(bytes, segment + 48)?;
    let vm_size = little64(bytes, segment + 32)?;
    if file_start < commands_end as u64
        || file_start > signature_start as u64
        || file_start.checked_add(file_size)? != bytes.len() as u64
    {
        return None;
    }
    let round_page = |size: u64| {
        size.checked_add(page_size - 1)
            .map(|value| value & !(page_size - 1))
    };
    // Normalize only page growth caused by the trailing signature. Preserve
    // unusual virtual layouts with an exact hash instead of guessing.
    if round_page(file_size)? != vm_size {
        return None;
    }
    let unsigned_size = (signature_start as u64).checked_sub(file_start)?;
    let mut canonical = bytes[..signature_start].to_vec();
    canonical[16..20].copy_from_slice(&((count - 1) as u32).to_le_bytes());
    canonical[20..24].copy_from_slice(&((commands_size - 16) as u32).to_le_bytes());
    // Zeroing retains command-padding offsets; all section, import, symbol,
    // relocation and non-signature linkedit bytes stay in the digest.
    canonical[command..command + 16].fill(0);
    canonical[segment + 32..segment + 40]
        .copy_from_slice(&round_page(unsigned_size)?.to_le_bytes());
    canonical[segment + 48..segment + 56].copy_from_slice(&unsigned_size.to_le_bytes());
    Some(canonical)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn put32(bytes: &mut [u8], at: usize, value: u32) {
        bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
    }
    fn put64(bytes: &mut [u8], at: usize, value: u64) {
        bytes[at..at + 8].copy_from_slice(&value.to_le_bytes());
    }
    fn signed(signature_size: usize) -> Vec<u8> {
        let mut bytes = vec![0; 512 + signature_size];
        put32(&mut bytes, 0, MACH_64);
        put32(&mut bytes, 4, CPU_ARM64);
        put32(&mut bytes, 16, 2);
        put32(&mut bytes, 20, 88);
        put32(&mut bytes, 32, 0x19);
        put32(&mut bytes, 36, 72);
        bytes[40..56].copy_from_slice(b"__LINKEDIT\0\0\0\0\0\0");
        put64(
            &mut bytes,
            64,
            (128 + signature_size as u64).div_ceil(16384) * 16384,
        );
        put64(&mut bytes, 72, 384);
        put64(&mut bytes, 80, 128 + signature_size as u64);
        put32(&mut bytes, 104, 0x1d);
        put32(&mut bytes, 108, 16);
        put32(&mut bytes, 112, 512);
        put32(&mut bytes, 116, signature_size as u32);
        bytes[256..384].fill(0x42);
        bytes[384..512].fill(0x57);
        bytes[512..].fill(0xaa);
        bytes
    }
    #[test]
    fn signature_size_contents_and_linkedit_page_growth_do_not_change_identity() {
        let first = signed(64);
        let mut second = signed(20000);
        second[512..].fill(0x12);
        assert_eq!(fingerprint(&first), fingerprint(&second));
        assert_eq!(
            fingerprint(&first),
            fingerprint(&canonical_mach64(&first).unwrap())
        );
        for at in [256, 400, 24, 88] {
            let mut changed = first.clone();
            changed[at] ^= 1;
            assert_ne!(
                fingerprint(&first),
                fingerprint(&changed),
                "changed byte {at}"
            );
        }
    }
    #[test]
    fn unexpected_signature_or_virtual_layout_uses_exact_hash() {
        let first = signed(64);
        for field in [112, 116, 64] {
            let mut malformed = first.clone();
            malformed[field] ^= 1;
            assert!(canonical_mach64(&malformed).is_none());
            assert_eq!(
                fingerprint(&malformed),
                format!("{:x}", Sha256::digest(&malformed))
            );
        }
        assert_eq!(
            fingerprint(b"ELF binary"),
            format!("{:x}", Sha256::digest(b"ELF binary"))
        );
    }
    #[test]
    fn universal_container_hashes_the_native_slice_and_rejects_overlaps() {
        let target = match std::env::consts::ARCH {
            "aarch64" => CPU_ARM64,
            "x86_64" => CPU_X86_64,
            _ => return,
        };
        let mut thin = signed(64);
        if target == CPU_X86_64 {
            put32(&mut thin, 4, target);
            put64(&mut thin, 64, 4096);
        }
        let mut fat = vec![0; 4096];
        fat[..4].copy_from_slice(&0xcafebabe_u32.to_be_bytes());
        fat[4..8].copy_from_slice(&1_u32.to_be_bytes());
        fat[8..12].copy_from_slice(&target.to_be_bytes());
        fat[16..20].copy_from_slice(&4096_u32.to_be_bytes());
        fat[20..24].copy_from_slice(&(thin.len() as u32).to_be_bytes());
        fat.extend_from_slice(&thin);
        assert_eq!(fingerprint(&fat), fingerprint(&thin));
        fat[16..20].copy_from_slice(&0_u32.to_be_bytes());
        assert!(native_slice(&fat).is_none());
    }
    #[cfg(target_os = "macos")]
    #[test]
    fn apple_signing_changes_preserve_a_compiled_fixture_identity() {
        use std::process::Command;
        let root = std::env::temp_dir().join(format!("retrolife-identity-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let source = root.join("fixture.c");
        let binary = root.join("fixture.dylib");
        std::fs::write(
            &source,
            "int checkpoint_identity_fixture(void) { return 42; }\n",
        )
        .unwrap();
        assert!(
            Command::new("cc")
                .args(["-dynamiclib", "-o"])
                .arg(&binary)
                .arg(&source)
                .status()
                .unwrap()
                .success()
        );
        let original = hash_core_file(&binary).unwrap();
        for id in [
            "org.retrolife.fixture.one",
            "org.retrolife.fixture.two.much.longer.identifier",
        ] {
            assert!(
                Command::new("codesign")
                    .args(["--force", "--sign", "-", "--identifier", id])
                    .arg(&binary)
                    .status()
                    .unwrap()
                    .success()
            );
            assert_eq!(hash_core_file(&binary).unwrap(), original);
        }
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    #[ignore = "needs two local builds of the same pinned core"]
    fn prepared_and_installed_core_have_equal_code_identity() {
        let first = std::env::var_os("RETROLIFE_IDENTITY_CORE_A").expect("first core path");
        let second = std::env::var_os("RETROLIFE_IDENTITY_CORE_B").expect("second core path");
        let a = hash_core_file(Path::new(&first)).unwrap();
        let b = hash_core_file(Path::new(&second)).unwrap();
        println!("first core identity: {a}; second core identity: {b}");
        assert_eq!(a, b);
    }
}
