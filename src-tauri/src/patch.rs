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
    let size = std::fs::metadata(image)
        .map_err(|error| PatchError::UnreadableImage(error.to_string()))?
        .len();

    if size > drive.byte_size {
        return Err(PatchError::ImageTooLarge);
    }

    elevate(&platform::write_command(
        &image.to_string_lossy(),
        &drive.device_path,
        &drive.id,
    ))
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
        shell(&format!(
            "/bin/dd if={} of={} bs=1m count={}",
            quote(device),
            quote(destination),
            megabytes
        ))
    }

    pub fn write_command(image: &str, device: &str, _id: &str) -> ElevatedCommand {
        // diskutil wants the buffered device (/dev/diskN); dd gets the raw one
        // (/dev/rdiskN), which is far faster for block-sized transfers.
        let buffered = device.replace("/dev/r", "/dev/");
        shell(&format!(
            "/usr/sbin/diskutil unmountDisk {} && /bin/dd if={} of={} bs=1m",
            quote(&buffered),
            quote(image),
            quote(device)
        ))
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
