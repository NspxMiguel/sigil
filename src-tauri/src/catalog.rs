//! The published header images, fetched from the project repository.
//!
//! Nothing downloaded here is usable until its checksum matches what the
//! manifest declares. The file ends up written to a block device, so a
//! corrupted or swapped download is not something to find out about
//! afterwards.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

pub const MANIFEST_URL: &str =
    "https://raw.githubusercontent.com/NspxMiguel/sigil/main/headers/manifest.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CatalogEntry {
    pub id: String,
    pub title: String,
    pub firmware: String,
    #[serde(default)]
    pub drive_bytes: Option<u64>,
    pub byte_size: u64,
    pub sha256: String,
    pub url: String,
}

#[derive(Debug, Deserialize)]
struct Manifest {
    #[allow(dead_code)]
    version: u32,
    headers: Vec<CatalogEntry>,
}

#[derive(Debug, thiserror::Error)]
pub enum CatalogError {
    #[error("could not reach GitHub: {0}")]
    Unreachable(String),
    #[error("GitHub answered {0}")]
    BadStatus(u16),
    #[error("the downloaded file does not match its published checksum")]
    ChecksumMismatch,
    #[error("could not write the download: {0}")]
    Storage(String),
}

pub async fn load() -> Result<Vec<CatalogEntry>, CatalogError> {
    let client = client()?;
    let response = client
        .get(MANIFEST_URL)
        .send()
        .await
        .map_err(|error| CatalogError::Unreachable(error.to_string()))?;

    let status = response.status();
    if !status.is_success() {
        return Err(CatalogError::BadStatus(status.as_u16()));
    }

    let manifest: Manifest = response
        .json()
        .await
        .map_err(|error| CatalogError::Unreachable(error.to_string()))?;
    Ok(manifest.headers)
}

pub async fn download(entry: &CatalogEntry) -> Result<PathBuf, CatalogError> {
    let client = client()?;
    let response = client
        .get(&entry.url)
        .send()
        .await
        .map_err(|error| CatalogError::Unreachable(error.to_string()))?;

    let status = response.status();
    if !status.is_success() {
        return Err(CatalogError::BadStatus(status.as_u16()));
    }

    let bytes = response
        .bytes()
        .await
        .map_err(|error| CatalogError::Unreachable(error.to_string()))?;

    let digest = Sha256::digest(&bytes);
    let hex = digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    if !hex.eq_ignore_ascii_case(&entry.sha256) {
        return Err(CatalogError::ChecksumMismatch);
    }

    let destination = std::env::temp_dir().join(format!("sigil-{}.img", entry.id));
    std::fs::write(&destination, &bytes)
        .map_err(|error| CatalogError::Storage(error.to_string()))?;
    Ok(destination)
}

fn client() -> Result<reqwest::Client, CatalogError> {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .user_agent(concat!("Sigil/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|error| CatalogError::Unreachable(error.to_string()))
}
