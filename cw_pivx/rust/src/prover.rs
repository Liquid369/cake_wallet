//! Sapling prover using Groth16 proofs.
//!
//! This module handles loading proving parameters and generating
//! zero-knowledge proofs for Sapling transactions.

use std::path::Path;
use std::sync::Mutex;
use std::fs;

use lazy_static::lazy_static;
use sha2::{Sha256, Digest};
use zcash_proofs::prover::LocalTxProver;

use crate::error::SaplingError;

lazy_static! {
    /// Global prover instance (expensive to create, reuse across transactions).
    static ref PROVER: Mutex<Option<LocalTxProver>> = Mutex::new(None);
}

/// Expected SHA256 hash of sapling-spend.params (Zcash Sapling parameters).
/// These parameters are the same for PIVX as they are based on the Zcash Sapling protocol.
/// Source: https://github.com/zcash/zcash/blob/master/zcutil/fetch-params.sh
const EXPECTED_SPEND_HASH: &str = "8270785a1a0d0bc77196f000ee6d221c9c9894f55307bd9357c3f0105d31ca63991";

/// Expected SHA256 hash of sapling-output.params.
const EXPECTED_OUTPUT_HASH: &str = "657e3d38dbb5cb5e7dd2970e8b03d69b4787dd907285b5a7f0790dcc8072f60f";

/// Verify parameter file hash matches expected value.
fn verify_param_hash(path: &str, expected: &str) -> Result<(), SaplingError> {
    // Read the entire file
    let data = fs::read(path)
        .map_err(|e| SaplingError::InvalidInput(
            format!("Failed to read parameter file {}: {}", path, e)
        ))?;
    
    // Compute SHA256 hash
    let hash = Sha256::digest(&data);
    let hash_hex = hex::encode(hash);
    
    // Compare with expected hash
    if hash_hex != expected {
        return Err(SaplingError::InvalidInput(
            format!(
                "Parameter file {} hash mismatch.\nExpected: {}\nGot: {}\n\
                This could indicate a corrupted or malicious parameter file. \
                Please re-download the proving parameters.",
                path, expected, hash_hex
            )
        ));
    }
    
    Ok(())
}

/// Initialize the prover with parameters from a directory.
/// 
/// The directory should contain:
/// - sapling-spend.params (47 MB, verified by SHA256)
/// - sapling-output.params (3.6 MB, verified by SHA256)
/// 
/// Hash verification prevents the use of corrupted or backdoored parameters.
pub fn init_prover(params_dir: &str) -> Result<(), SaplingError> {
    let spend_path = format!("{}/sapling-spend.params", params_dir);
    let output_path = format!("{}/sapling-output.params", params_dir);
    
    // Check files exist
    if !Path::new(&spend_path).exists() {
        return Err(SaplingError::InvalidInput(
            format!("Spend params not found: {}", spend_path)
        ));
    }
    if !Path::new(&output_path).exists() {
        return Err(SaplingError::InvalidInput(
            format!("Output params not found: {}", output_path)
        ));
    }
    
    // Verify parameter file hashes (CRITICAL SECURITY CHECK)
    verify_param_hash(&spend_path, EXPECTED_SPEND_HASH)?;
    verify_param_hash(&output_path, EXPECTED_OUTPUT_HASH)?;
    
    // Load the prover
    let prover = LocalTxProver::new(
        Path::new(&spend_path),
        Path::new(&output_path),
    );
    
    let mut global = PROVER.lock().map_err(|_| 
        SaplingError::InvalidInput("Failed to lock prover mutex".into())
    )?;
    *global = Some(prover);
    
    Ok(())
}

/// Check if the prover is initialized.
pub fn is_prover_initialized() -> bool {
    PROVER.lock().map(|p| p.is_some()).unwrap_or(false)
}

/// Get a reference to the global prover.
/// Returns an error if the prover is not initialized.
pub fn get_prover() -> Result<std::sync::MutexGuard<'static, Option<LocalTxProver>>, SaplingError> {
    let guard = PROVER.lock().map_err(|_| 
        SaplingError::InvalidInput("Failed to lock prover mutex".into())
    )?;
    
    if guard.is_none() {
        return Err(SaplingError::ProverNotInitialized);
    }
    
    Ok(guard)
}

/// Free the prover and release memory.
pub fn dispose_prover() {
    if let Ok(mut guard) = PROVER.lock() {
        *guard = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_prover_not_initialized() {
        assert!(!is_prover_initialized());
    }
}
