//! Raw reads and writes against a whole disk, each one behind the operating
//! system's own elevation prompt.
//!
//! The password is always typed by the person into a dialog the OS puts up.
//! Nothing here ever sees or stores a credential.

use crate::drives::Drive;
use std::path::Path;
use std::process::Command;

#[derive(Debug, thiserror::Error)]
pub enum PatchError {
    #[error("the image is larger than the destination drive")]
    ImageTooLarge,
    #[error("could not read the image: {0}")]
    UnreadableImage(String),
    #[error("{0}")]
    Elevation(String),
    #[error("cancelled")]
    Cancelled,
}

/// Read-only capture of the leading sectors of a donor drive.
pub fn capture(drive: &Drive, bytes: u64, destination: &Path) -> Result<(), PatchError> {
    let megabytes = (bytes / (1024 * 1024)).max(1);
    elevate(&platform::capture_command(
        &drive.device_path,
        &destination.to_string_lossy(),
        megabytes,
    ))
}

pub fn write(image: &Path, drive: &Drive) -> Result<(), PatchError> {
    let prepared = prepare_image(image)?;

    if prepared.byte_size > drive.byte_size {
        return Err(PatchError::ImageTooLarge);
    }

    let result = elevate(&platform::write_command(
        &prepared.path.to_string_lossy(),
        &drive.device_path,
        &drive.id,
    ));

    if prepared.is_padded_copy {
        let _ = std::fs::remove_file(&prepared.path);
    }
    result
}

/// Every sector size in use (512 and 4096) divides this.
const SECTOR_ALIGNMENT: u64 = 4096;

pub(crate) struct PreparedImage {
    pub path: std::path::PathBuf,
    pub byte_size: u64,
    pub is_padded_copy: bool,
}

/// Raw devices refuse a write whose length is not a whole number of sectors:
/// macOS `dd` to `/dev/rdiskN` fails the trailing partial block with EINVAL,
/// and `\\.\PhysicalDriveN` on Windows behaves the same. Hand-trimmed header
/// images carry no alignment guarantee, so they are zero-padded to the next
/// 4 KiB boundary in a temporary copy. The original file is never modified.
pub(crate) fn prepare_image(image: &Path) -> Result<PreparedImage, PatchError> {
    let size = std::fs::metadata(image)
        .map_err(|error| PatchError::UnreadableImage(error.to_string()))?
        .len();

    let remainder = size % SECTOR_ALIGNMENT;
    if remainder == 0 {
        return Ok(PreparedImage {
            path: image.to_path_buf(),
            byte_size: size,
            is_padded_copy: false,
        });
    }

    let padded_size = size + (SECTOR_ALIGNMENT - remainder);
    let padded = std::env::temp_dir().join(format!(
        "sigil-aligned-{}-{}.img",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_nanos())
            .unwrap_or_default()
    ));

    std::fs::copy(image, &padded)
        .map_err(|error| PatchError::UnreadableImage(error.to_string()))?;
    std::fs::OpenOptions::new()
        .write(true)
        .open(&padded)
        .and_then(|file| file.set_len(padded_size))
        .map_err(|error| PatchError::UnreadableImage(error.to_string()))?;

    Ok(PreparedImage {
        path: padded,
        byte_size: padded_size,
        is_padded_copy: true,
    })
}

fn elevate(command: &platform::ElevatedCommand) -> Result<(), PatchError> {
    let output = Command::new(&command.program)
        .args(&command.args)
        .output()
        .map_err(|error| PatchError::Elevation(error.to_string()))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    // Every platform reports "the person clicked cancel" as a plain failure,
    // so it has to be recognised by text or a cancelled prompt looks like a
    // real error.
    if stderr.contains("-128")
        || stderr.to_lowercase().contains("cancel")
        || stderr.contains("dismissed")
        || stderr.contains("Request dismissed")
    {
        return Err(PatchError::Cancelled);
    }

    Err(PatchError::Elevation(stderr.trim().to_string()))
}

// ---------------------------------------------------------------- macOS

#[cfg(target_os = "macos")]
mod platform {
    pub struct ElevatedCommand {
        pub program: String,
        pub args: Vec<String>,
    }

    pub fn capture_command(device: &str, destination: &str, megabytes: u64) -> ElevatedCommand {
        shell(&capture_shell(device, destination, megabytes))
    }

    pub fn write_command(image: &str, device: &str, _id: &str) -> ElevatedCommand {
        shell(&write_shell(image, device))
    }

    pub(crate) fn capture_shell(device: &str, destination: &str, megabytes: u64) -> String {
        format!(
            "/bin/dd if={} of={} bs=1m count={}",
            quote(device),
            quote(destination),
            megabytes
        )
    }

    pub(crate) fn write_shell(image: &str, device: &str) -> String {
        // diskutil wants the buffered device (/dev/diskN); dd gets the raw one
        // (/dev/rdiskN), which is far faster for block-sized transfers.
        let buffered = device.replace("/dev/r", "/dev/");
        format!(
            "/usr/sbin/diskutil unmountDisk {} && /bin/dd if={} of={} bs=1m",
            quote(&buffered),
            quote(image),
            quote(device)
        )
    }

    fn shell(command: &str) -> ElevatedCommand {
        let script = format!(
            "do shell script \"{}\" with administrator privileges with prompt \
             \"Sigil needs permission to access the drive.\"",
            command.replace('\\', "\\\\").replace('"', "\\\"")
        );
        ElevatedCommand {
            program: "/usr/bin/osascript".into(),
            args: vec!["-e".into(), script],
        }
    }

    fn quote(value: &str) -> String {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

// ---------------------------------------------------------------- Linux

#[cfg(target_os = "linux")]
mod platform {
    pub struct ElevatedCommand {
        pub program: String,
        pub args: Vec<String>,
    }

    pub fn capture_command(device: &str, destination: &str, megabytes: u64) -> ElevatedCommand {
        shell(&format!(
            "dd if={} of={} bs=1M count={} && chown \"$PKEXEC_UID\" {}",
            quote(device),
            quote(destination),
            megabytes,
            quote(destination)
        ))
    }

    pub fn write_command(image: &str, device: &str, _id: &str) -> ElevatedCommand {
        // Unmount whatever is mounted off the disk first; a mounted filesystem
        // would write its own cached metadata back over ours.
        shell(&format!(
            "umount {}* 2>/dev/null; dd if={} of={} bs=1M conv=fsync",
            quote(device),
            quote(image),
            quote(device)
        ))
    }

    fn shell(command: &str) -> ElevatedCommand {
        ElevatedCommand {
            program: "pkexec".into(),
            args: vec!["/bin/sh".into(), "-c".into(), command.to_string()],
        }
    }

    fn quote(value: &str) -> String {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

// ---------------------------------------------------------------- Windows

#[cfg(target_os = "windows")]
mod platform {
    pub struct ElevatedCommand {
        pub program: String,
        pub args: Vec<String>,
    }

    pub fn capture_command(device: &str, destination: &str, megabytes: u64) -> ElevatedCommand {
        // No dd on Windows. FileStream against the physical drive handle is
        // the equivalent, and reading needs FileShare::ReadWrite or the open
        // fails while the disk is in use.
        let inner = format!(
            r#"$total = {megabytes}MB
$src = [System.IO.File]::Open('{device}', 'Open', 'Read', 'ReadWrite')
$dst = [System.IO.File]::Open('{destination}', 'Create', 'Write')
$buffer = New-Object byte[] 1MB
$read = 0
while ($read -lt $total) {{
  $n = $src.Read($buffer, 0, $buffer.Length)
  if ($n -le 0) {{ break }}
  $dst.Write($buffer, 0, $n)
  $read += $n
}}
$dst.Close(); $src.Close()"#
        );
        elevated(&inner)
    }

    pub fn write_command(image: &str, device: &str, id: &str) -> ElevatedCommand {
        // Windows will refuse the write while the volume is mounted, so the
        // disk is taken offline first and put back afterwards.
        let inner = format!(
            r#"Set-Disk -Number {id} -IsOffline $true
$src = [System.IO.File]::Open('{image}', 'Open', 'Read')
$dst = [System.IO.File]::Open('{device}', 'Open', 'Write', 'ReadWrite')
$buffer = New-Object byte[] 1MB
while (($n = $src.Read($buffer, 0, $buffer.Length)) -gt 0) {{
  $dst.Write($buffer, 0, $n)
}}
$dst.Flush(); $dst.Close(); $src.Close()
Set-Disk -Number {id} -IsOffline $false"#
        );
        elevated(&inner)
    }

    /// Relaunches PowerShell through the UAC prompt. `-Wait` is what makes the
    /// outer process able to report a result instead of returning immediately.
    fn elevated(script: &str) -> ElevatedCommand {
        let encoded = {
            let utf16: Vec<u8> = script
                .encode_utf16()
                .flat_map(|unit| unit.to_le_bytes())
                .collect();
            base64(&utf16)
        };

        let outer = format!(
            "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden \
             -ArgumentList '-NoProfile','-EncodedCommand','{encoded}'"
        );

        ElevatedCommand {
            program: "powershell".into(),
            args: vec![
                "-NoProfile".into(),
                "-NonInteractive".into(),
                "-Command".into(),
                outer,
            ],
        }
    }

    fn base64(data: &[u8]) -> String {
        const TABLE: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in data.chunks(3) {
            let b = [
                chunk[0],
                *chunk.get(1).unwrap_or(&0),
                *chunk.get(2).unwrap_or(&0),
            ];
            let triple = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
            out.push(TABLE[(triple >> 18 & 0x3F) as usize] as char);
            out.push(TABLE[(triple >> 12 & 0x3F) as usize] as char);
            out.push(if chunk.len() > 1 {
                TABLE[(triple >> 6 & 0x3F) as usize] as char
            } else {
                '='
            });
            out.push(if chunk.len() > 2 {
                TABLE[(triple & 0x3F) as usize] as char
            } else {
                '='
            });
        }
        out
    }
}

/// Round-trips the exact shell commands the app runs against real block
/// devices. Opt-in only: the test writes to whatever the two variables point
/// at, so it must never run by default. Point them at attached disk images:
///
/// ```sh
/// SIGIL_DISK_TEST_DONOR=/dev/rdisk14 SIGIL_DISK_TEST_TARGET=/dev/rdisk15 cargo test disk_ -- --nocapture
/// ```
#[cfg(all(test, target_os = "macos"))]
mod disk_tests {
    use super::platform::{capture_shell, write_shell};
    use std::process::Command;

    fn devices() -> Option<(String, String)> {
        let donor = std::env::var("SIGIL_DISK_TEST_DONOR").ok()?;
        let target = std::env::var("SIGIL_DISK_TEST_TARGET").ok()?;
        Some((donor, target))
    }

    fn pattern(len: usize, seed: u32) -> Vec<u8> {
        let mut state = seed;
        (0..len)
            .map(|_| {
                state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                (state >> 24) as u8
            })
            .collect()
    }

    fn sh(command: &str) {
        let output = Command::new("/bin/sh")
            .arg("-c")
            .arg(command)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "command failed: {command}\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    #[test]
    fn disk_capture_reads_exactly_the_leading_sectors() {
        let Some((donor, _)) = devices() else { return };
        let dir = tempdir();
        let seed_path = dir.join("seed.bin");
        let seed = pattern(4 * 1024 * 1024, 7);
        std::fs::write(&seed_path, &seed).unwrap();
        sh(&format!(
            "/bin/dd if='{}' of='{donor}' bs=1m",
            seed_path.display()
        ));

        let out = dir.join("captured.img");
        sh(&capture_shell(&donor, &out.to_string_lossy(), 4));

        assert_eq!(
            std::fs::read(&out).unwrap(),
            seed,
            "capture did not match donor"
        );
    }

    #[test]
    fn disk_write_lands_an_image_that_is_not_block_aligned() {
        let Some((_, target)) = devices() else { return };
        let dir = tempdir();
        // Deliberately not a multiple of the 512-byte sector: hand-trimmed
        // header images are not guaranteed to be aligned.
        let image = pattern(1_500_123, 11);
        let image_path = dir.join("header.img");
        std::fs::write(&image_path, &image).unwrap();

        let prepared = super::prepare_image(&image_path).unwrap();
        assert!(prepared.is_padded_copy);
        assert_eq!(prepared.byte_size % 4096, 0);
        assert_eq!(
            std::fs::read(&image_path).unwrap(),
            image,
            "original was modified"
        );

        sh(&write_shell(&prepared.path.to_string_lossy(), &target));

        let back = dir.join("readback.bin");
        sh(&format!(
            "/bin/dd if='{target}' of='{}' bs=1m count=2",
            back.display()
        ));
        let read = std::fs::read(&back).unwrap();
        assert_eq!(
            &read[..image.len()],
            &image[..],
            "target does not hold the image"
        );
        assert!(
            read[image.len()..prepared.byte_size as usize]
                .iter()
                .all(|&byte| byte == 0),
            "padding past the image is not zeroed"
        );
    }

    #[test]
    fn disk_images_are_never_listed_as_targets() {
        let Some((donor, target)) = devices() else {
            return;
        };
        let listed = crate::drives::list().unwrap();
        for device in [donor, target] {
            let bsd = device.trim_start_matches("/dev/r").to_string();
            assert!(
                !listed.iter().any(|drive| drive.id == bsd),
                "{bsd} is a disk image and must not be offered as a target"
            );
        }
    }

    fn tempdir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "sigil-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }
}
