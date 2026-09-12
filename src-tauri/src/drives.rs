//! Drive enumeration.
//!
//! Every platform implementation has the same contract: return only removable
//! external media, and never the disk the system booted from. A wrong entry
//! here ends with somebody's disk overwritten, so each backend filters at the
//! source and the result is filtered again before it reaches the UI.

use serde::Serialize;
use std::process::Command;

#[derive(Debug, Clone, Serialize)]
pub struct Drive {
    /// Stable per-platform identifier: `disk4`, `sdb`, or the Windows disk
    /// number as a string.
    pub id: String,
    pub name: String,
    pub byte_size: u64,
    /// Path the raw read and write go through.
    pub device_path: String,
}

#[derive(Debug, thiserror::Error)]
pub enum DriveError {
    #[error("could not list drives: {0}")]
    Enumeration(String),
}

pub fn list() -> Result<Vec<Drive>, DriveError> {
    platform::list()
}

pub fn find(id: &str) -> Result<Option<Drive>, DriveError> {
    Ok(list()?.into_iter().find(|drive| drive.id == id))
}

fn run(program: &str, args: &[&str]) -> Result<Vec<u8>, DriveError> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| DriveError::Enumeration(format!("{program}: {error}")))?;

    if !output.status.success() {
        return Err(DriveError::Enumeration(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    Ok(output.stdout)
}

// ---------------------------------------------------------------- macOS

#[cfg(target_os = "macos")]
mod platform {
    use super::*;

    pub fn list() -> Result<Vec<Drive>, DriveError> {
        // `external physical` already excludes internal media and disk images;
        // each device is then checked again below.
        let listing = run(
            "/usr/sbin/diskutil",
            &["list", "-plist", "external", "physical"],
        )?;
        let json = plist_to_json(&listing)?;

        let whole = json
            .get("WholeDisks")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();

        let mut drives = Vec::new();
        for entry in whole {
            let Some(bsd) = entry.as_str() else { continue };
            if let Some(drive) = describe(bsd)? {
                drives.push(drive);
            }
        }
        Ok(drives)
    }

    fn describe(bsd: &str) -> Result<Option<Drive>, DriveError> {
        let info = run("/usr/sbin/diskutil", &["info", "-plist", bsd])?;
        let device = plist_to_json(&info)?;

        let is_internal = device
            .get("Internal")
            .and_then(|value| value.as_bool())
            .unwrap_or(true);
        let is_os = device
            .get("OSInternal")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let is_virtual = device
            .get("VirtualOrPhysical")
            .and_then(|value| value.as_str())
            .map(|kind| kind.eq_ignore_ascii_case("Virtual"))
            .unwrap_or(false);
        if is_internal || is_os || is_virtual {
            return Ok(None);
        }

        let size = device
            .get("TotalSize")
            .or_else(|| device.get("Size"))
            .and_then(|value| value.as_u64())
            .unwrap_or(0);
        if size == 0 {
            return Ok(None);
        }

        let name = device
            .get("MediaName")
            .and_then(|value| value.as_str())
            .unwrap_or(bsd)
            .trim()
            .to_string();

        Ok(Some(Drive {
            id: bsd.to_string(),
            name,
            byte_size: size,
            // The raw device is markedly faster for block-sized transfers.
            device_path: format!("/dev/r{bsd}"),
        }))
    }

    /// `plutil` is always present on macOS, which avoids taking a plist crate
    /// just to read two keys.
    fn plist_to_json(data: &[u8]) -> Result<serde_json::Value, DriveError> {
        use std::io::Write;

        let mut child = std::process::Command::new("/usr/bin/plutil")
            .args(["-convert", "json", "-o", "-", "-"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|error| DriveError::Enumeration(format!("plutil: {error}")))?;

        child
            .stdin
            .as_mut()
            .ok_or_else(|| DriveError::Enumeration("plutil stdin".into()))?
            .write_all(data)
            .map_err(|error| DriveError::Enumeration(format!("plutil: {error}")))?;

        let output = child
            .wait_with_output()
            .map_err(|error| DriveError::Enumeration(format!("plutil: {error}")))?;

        serde_json::from_slice(&output.stdout)
            .map_err(|error| DriveError::Enumeration(format!("plutil json: {error}")))
    }
}

// ---------------------------------------------------------------- Linux

#[cfg(target_os = "linux")]
mod platform {
    use super::*;

    pub fn list() -> Result<Vec<Drive>, DriveError> {
        let output = run(
            "lsblk",
            &["-J", "-b", "-o", "NAME,MODEL,SIZE,RM,TYPE,MOUNTPOINTS,TRAN"],
        )?;
        let json: serde_json::Value = serde_json::from_slice(&output)
            .map_err(|error| DriveError::Enumeration(format!("lsblk json: {error}")))?;

        let devices = json
            .get("blockdevices")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();

        let mut drives = Vec::new();
        for device in devices {
            if device.get("type").and_then(|v| v.as_str()) != Some("disk") {
                continue;
            }

            // Removable, or attached over a bus that only carries external
            // media. Internal NVMe and SATA disks never qualify.
            let removable = device.get("rm").and_then(|v| v.as_bool()).unwrap_or(false);
            let transport = device.get("tran").and_then(|v| v.as_str()).unwrap_or("");
            if !removable && !matches!(transport, "usb" | "ieee1394") {
                continue;
            }

            if holds_root(&device) {
                continue;
            }

            let size = device.get("size").and_then(|v| v.as_u64()).unwrap_or(0);
            if size == 0 {
                continue;
            }

            let name = device.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let model = device
                .get("model")
                .and_then(|v| v.as_str())
                .unwrap_or(name)
                .trim();

            drives.push(Drive {
                id: name.to_string(),
                name: if model.is_empty() {
                    name.to_string()
                } else {
                    model.to_string()
                },
                byte_size: size,
                device_path: format!("/dev/{name}"),
            });
        }
        Ok(drives)
    }

    /// Walks the device and every partition under it looking for `/` or
    /// `/boot`. lsblk reports a removable flag, but a USB-booted system is
    /// still a system the user does not want overwritten.
    fn holds_root(device: &serde_json::Value) -> bool {
        fn mounted_at_root(node: &serde_json::Value) -> bool {
            let mounts = node
                .get("mountpoints")
                .and_then(|value| value.as_array())
                .cloned()
                .unwrap_or_default();

            if mounts
                .iter()
                .filter_map(|m| m.as_str())
                .any(|mount| mount == "/" || mount.starts_with("/boot") || mount == "/nix/store")
            {
                return true;
            }

            node.get("children")
                .and_then(|value| value.as_array())
                .map(|children| children.iter().any(mounted_at_root))
                .unwrap_or(false)
        }
        mounted_at_root(device)
    }
}

// ---------------------------------------------------------------- Windows

#[cfg(target_os = "windows")]
mod platform {
    use super::*;

    pub fn list() -> Result<Vec<Drive>, DriveError> {
        // Get-Disk carries the two flags that matter (IsBoot, IsSystem) plus
        // the bus type, which is what separates an enclosure from an internal
        // drive.
        let script = "Get-Disk | Select-Object Number,FriendlyName,Size,BusType,IsBoot,IsSystem,\
                      IsOffline | ConvertTo-Json -Compress -Depth 3";
        let output = run(
            "powershell",
            &["-NoProfile", "-NonInteractive", "-Command", script],
        )?;

        let text = String::from_utf8_lossy(&output);
        let parsed: serde_json::Value = serde_json::from_str(text.trim())
            .map_err(|error| DriveError::Enumeration(format!("Get-Disk json: {error}")))?;

        // A single disk comes back as an object rather than an array.
        let disks = match parsed {
            serde_json::Value::Array(items) => items,
            other => vec![other],
        };

        let mut drives = Vec::new();
        for disk in disks {
            let is_boot = disk.get("IsBoot").and_then(|v| v.as_bool()).unwrap_or(true);
            let is_system = disk
                .get("IsSystem")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            if is_boot || is_system {
                continue;
            }

            // BusType is an enum; 7 is USB and 8 is RAID, the rest of the
            // external-capable values come through by name on newer builds.
            let bus = disk
                .get("BusType")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let external = match &bus {
                serde_json::Value::Number(number) => number.as_u64() == Some(7),
                serde_json::Value::String(name) => {
                    name.eq_ignore_ascii_case("USB") || name.eq_ignore_ascii_case("SCSI")
                }
                _ => false,
            };
            if !external {
                continue;
            }

            let Some(number) = disk.get("Number").and_then(|v| v.as_u64()) else {
                continue;
            };
            let size = disk.get("Size").and_then(|v| v.as_u64()).unwrap_or(0);
            if size == 0 {
                continue;
            }

            let name = disk
                .get("FriendlyName")
                .and_then(|v| v.as_str())
                .unwrap_or("Disk")
                .trim()
                .to_string();

            drives.push(Drive {
                id: number.to_string(),
                name,
                byte_size: size,
                device_path: format!("\\\\.\\PhysicalDrive{number}"),
            });
        }
        Ok(drives)
    }
}
