//! FFI bindings for Dart/Flutter integration.
//!
//! This module provides C-compatible FFI functions that can be called
//! from Dart using dart:ffi.
//!
//! Function names use `cw_pivx_*` prefix for Cake Wallet compatibility.

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::slice;
use lazy_static::lazy_static;
use std::sync::Mutex;
use group::GroupEncoding;

use sapling::{
    keys::PreparedIncomingViewingKey,
    note::ExtractedNoteCommitment,
    note_encryption::{SaplingDomain, try_sapling_note_decryption, Zip212Enforcement},
};
use zcash_note_encryption::{EphemeralKeyBytes, ShieldedOutput, ENC_CIPHERTEXT_SIZE};

use crate::keys::{SaplingKeyManager, validate_address};
use crate::types::Network;
use crate::sync::SyncState;
use crate::notes::SpendableNote;

/// A simple output wrapper that implements ShieldedOutput for trial decryption.
/// This allows us to trial decrypt outputs from raw bytes without needing
/// a full OutputDescription with proof.
struct TrialDecryptionOutput {
    ephemeral_key: EphemeralKeyBytes,
    cmu: ExtractedNoteCommitment,
    enc_ciphertext: [u8; ENC_CIPHERTEXT_SIZE],
}

impl ShieldedOutput<SaplingDomain, ENC_CIPHERTEXT_SIZE> for TrialDecryptionOutput {
    fn ephemeral_key(&self) -> EphemeralKeyBytes {
        self.ephemeral_key.clone()
    }

    fn cmstar_bytes(&self) -> [u8; 32] {
        self.cmu.to_bytes()
    }

    fn enc_ciphertext(&self) -> &[u8; ENC_CIPHERTEXT_SIZE] {
        &self.enc_ciphertext
    }
}

lazy_static! {
    static ref KEY_MANAGERS: Mutex<Vec<Option<SaplingKeyManager>>> = Mutex::new(Vec::new());
    static ref SYNC_STATES: Mutex<Vec<Option<SyncState>>> = Mutex::new(Vec::new());
    static ref LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);
}

/// Helper macro for acquiring mutex locks with poison handling.
/// If a mutex is poisoned (thread panicked while holding it), this returns
/// an appropriate error value instead of panicking the entire application.
///
/// Usage: lock_or_fail!(MUTEX, error_return_value)
macro_rules! lock_or_fail {
    ($mutex:expr, $error_return:expr) => {
        match $mutex.lock() {
            Ok(guard) => guard,
            Err(_poisoned) => {
                // Mutex is poisoned - a previous thread panicked while holding it.
                // We cannot safely use the data, so return an error.
                // Use set_error_safe to avoid recursive poison if LAST_ERROR is also poisoned.
                set_error_safe("Internal state corrupted (mutex poisoned). Please restart wallet.");
                return $error_return;
            }
        }
    };
}

/// Safely set error message, handling the case where LAST_ERROR mutex itself is poisoned.
/// This prevents cascading panics when reporting errors.
fn set_error_safe(msg: &str) {
    if let Ok(mut error) = LAST_ERROR.lock() {
        *error = Some(msg.to_string());
    }
    // If LAST_ERROR is poisoned, silently fail - we cannot report the error,
    // but at least we don't crash the application.
}

/// Set the last error message.
/// Use this for normal error reporting. If the mutex is poisoned, this will
/// set a generic "corrupted state" error instead of the specific message.
fn set_error(msg: &str) {
    let mut error = lock_or_fail!(LAST_ERROR, ());
    *error = Some(msg.to_string());
}

/// Safely convert an i64 handle to usize index with validation.
/// Returns None if the handle is negative or too large for usize.
fn handle_to_index(handle: i64) -> Option<usize> {
    if handle < 0 {
        return None;
    }
    // On 32-bit systems, check if handle fits in usize
    #[cfg(target_pointer_width = "32")]
    {
        if handle > usize::MAX as i64 {
            return None;
        }
    }
    Some(handle as usize)
}

/// Macro to validate a handle and get the corresponding item from a Vec<Option<T>>.
/// Returns with error_return if handle is invalid or out of bounds.
macro_rules! get_from_handle {
    ($handle:expr, $vec:expr, $error_return:expr, $item_name:expr) => {
        {
            let idx = match handle_to_index($handle) {
                Some(i) => i,
                None => {
                    set_error(&format!("Invalid {}: must be non-negative", $item_name));
                    return $error_return;
                }
            };
            match $vec.get(idx).and_then(|item| item.as_ref()) {
                Some(item) => item,
                None => {
                    if idx >= $vec.len() {
                        set_error(&format!("Invalid {}: out of range", $item_name));
                    } else {
                        set_error(&format!("{} has been disposed", $item_name));
                    }
                    return $error_return;
                }
            }
        }
    };
}

/// Get and clear the last error message.
#[no_mangle]
pub extern "C" fn cw_pivx_get_last_error() -> *mut c_char {
    let mut error = lock_or_fail!(LAST_ERROR, ptr::null_mut());
    match error.take() {
        Some(msg) => {
            // Replace null bytes with spaces if any (should never happen in error messages)
            let sanitized = msg.replace('\0', " ");
            CString::new(sanitized)
                .expect("Error message sanitized: no null bytes")
                .into_raw()
        }
        None => ptr::null_mut(),
    }
}

/// Helper to safely extract fixed-size byte array from FFI pointer.
/// Returns error string if pointer is null or size doesn't match.
unsafe fn bytes_from_ffi_ptr<const N: usize>(
    ptr: *const u8,
    param_name: &str,
) -> Result<[u8; N], String> {
    if ptr.is_null() {
        return Err(format!("{} is null", param_name));
    }
    let slice = slice::from_raw_parts(ptr, N);
    slice.try_into()
        .map_err(|_| format!("{} size mismatch (expected {} bytes)", param_name, N))
}

/// Validate amount is within reasonable bounds.
/// PIVX uses 8 decimal places. Max reasonable: 100 billion PIV = 10^19 zatoshis.
/// This prevents overflow and unreasonable amounts.
fn validate_amount(amount: u64, param_name: &str) -> Result<(), String> {
    const MAX_REASONABLE: u64 = 10_000_000_000_000_000_000; // 100 billion PIV
    const DUST_THRESHOLD: u64 = 10_000; // 0.0001 PIV
    
    if amount == 0 {
        return Err(format!("{} cannot be zero", param_name));
    }
    if amount < DUST_THRESHOLD {
        return Err(format!("{} is below dust threshold ({} zatoshis)", param_name, DUST_THRESHOLD));
    }
    if amount > MAX_REASONABLE {
        return Err(format!("{} exceeds maximum reasonable amount", param_name));
    }
    Ok(())
}

/// Validate fee is reasonable.
/// Fee should be at least 1000 zatoshis (0.00001 PIV) and at most 1 PIV.
fn validate_fee(fee: u64) -> Result<(), String> {
    const MIN_FEE: u64 = 1_000; // 0.00001 PIV
    const MAX_FEE: u64 = 100_000_000; // 1 PIV
    
    if fee < MIN_FEE {
        return Err(format!("Fee too low (min {} zatoshis)", MIN_FEE));
    }
    if fee > MAX_FEE {
        return Err(format!("Fee too high (max {} zatoshis)", MAX_FEE));
    }
    Ok(())
}

/// Validate string length is within reasonable bounds.
/// This prevents DoS attacks via extremely long strings.
fn validate_string_length(s: &str, max_len: usize, param_name: &str) -> Result<(), String> {
    if s.len() > max_len {
        return Err(format!("{} too long (max {} chars, got {})", param_name, max_len, s.len()));
    }
    Ok(())
}

/// Validate memo length (max 512 bytes for Sapling).
fn validate_memo(memo: Option<&str>) -> Result<(), String> {
    if let Some(m) = memo {
        if m.len() > 512 {
            return Err(format!("Memo too long (max 512 bytes, got {})", m.len()));
        }
    }
    Ok(())
}

/// Get the library version.
#[no_mangle]
pub extern "C" fn cw_pivx_version() -> *mut c_char {
    CString::new(env!("CARGO_PKG_VERSION"))
        .expect("Version string is valid: no null bytes")
        .into_raw()
}

/// Free a string allocated by this library.
#[no_mangle]
pub extern "C" fn cw_pivx_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// Also provide the old name for compatibility
#[no_mangle]
pub extern "C" fn pivx_sapling_free_string(ptr: *mut c_char) {
    cw_pivx_free_string(ptr);
}

/// FFI buffer for returning binary data.
#[repr(C)]
pub struct FFIBuffer {
    pub data: *mut u8,
    pub len: usize,
}

/// Free a buffer allocated by this library.
#[no_mangle]
pub extern "C" fn cw_pivx_free_buffer(buffer: FFIBuffer) {
    if !buffer.data.is_null() && buffer.len > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(buffer.data, buffer.len, buffer.len);
        }
    }
}

/// Initialize keys from a seed.
/// Returns a handle for future operations, or -1 on error.
#[no_mangle]
pub extern "C" fn cw_pivx_init_keys(
    seed: *const u8,
    seed_len: usize,
    is_testnet: u8,
) -> i64 {
    if seed.is_null() || seed_len < 32 {
        set_error("Invalid seed");
        return -1;
    }
    
    let seed_slice = unsafe { slice::from_raw_parts(seed, seed_len) };
    let network = if is_testnet != 0 { Network::Testnet } else { Network::Mainnet };
    
    match SaplingKeyManager::from_seed(seed_slice, network) {
        Ok(manager) => {
            let mut managers = lock_or_fail!(KEY_MANAGERS, -1);
            
            // Find first available slot (reuse disposed handles) or create new
            let id = managers.iter().position(|m| m.is_none())
                .unwrap_or_else(|| {
                    managers.push(None);
                    managers.len() - 1
                }) as i64;
            
            managers[id as usize] = Some(manager);
            
            // Also create a sync state at same index
            let mut states = lock_or_fail!(SYNC_STATES, -1);
            // Ensure states vec is large enough
            while states.len() <= id as usize {
                states.push(None);
            }
            states[id as usize] = Some(SyncState::new());
            
            id
        }
        Err(e) => {
            set_error(&format!("Failed to create key manager: {:?}", e));
            -1
        }
    }
}

/// Dispose keys.
#[no_mangle]
pub extern "C" fn cw_pivx_dispose_keys(handle: i64) {
    let idx = match handle_to_index(handle) {
        Some(i) => i,
        None => {
            set_error("Invalid handle: must be non-negative");
            return;
        }
    };
    
    let mut managers = lock_or_fail!(KEY_MANAGERS, ());
    if idx < managers.len() {
        managers[idx] = None;
    }
}

/// Get the default payment address.
#[no_mangle]
pub extern "C" fn cw_pivx_get_default_address(handle: i64) -> *mut c_char {
    let managers = lock_or_fail!(KEY_MANAGERS, ptr::null_mut());
    let manager = get_from_handle!(handle, managers, ptr::null_mut(), "key handle");
    
    match manager.default_address() {
        Ok(addr) => {
            let encoded = manager.encode_payment_address(&addr);
            CString::new(encoded)
                .expect("Address encoding is valid: no null bytes")
                .into_raw()
        }
        Err(e) => {
            set_error(&format!("Failed to get address: {:?}", e));
            ptr::null_mut()
        }
    }
}

/// Derive an address at a specific index.
#[no_mangle]
pub extern "C" fn cw_pivx_derive_address(handle: i64, index: u64) -> *mut c_char {
    let managers = lock_or_fail!(KEY_MANAGERS, ptr::null_mut());
    let idx = handle as usize;
    
    if idx >= managers.len() {
        set_error("Invalid handle");
        return ptr::null_mut();
    }
    
    let manager = match &managers[idx] {
        Some(m) => m,
        None => {
            set_error("Handle disposed");
            return ptr::null_mut();
        }
    };
    
    // Convert index to DiversifierIndex
    let mut div_bytes = [0u8; 11];
    div_bytes[0..8].copy_from_slice(&(index as u64).to_le_bytes());
    let div_index = zcash_primitives::zip32::DiversifierIndex::from(div_bytes);
    
    match manager.derive_address(div_index) {
        Ok(addr) => {
            let encoded = manager.encode_payment_address(&addr);
            CString::new(encoded)
                .expect("Address encoding is valid: no null bytes")
                .into_raw()
        }
        Err(e) => {
            set_error(&format!("Failed to derive address: {:?}", e));
            ptr::null_mut()
        }
    }
}

/// Get the full viewing key.
#[no_mangle]
pub extern "C" fn cw_pivx_get_viewing_key(handle: i64) -> *mut c_char {
    let managers = lock_or_fail!(KEY_MANAGERS, ptr::null_mut());
    let idx = handle as usize;
    
    if idx >= managers.len() {
        set_error("Invalid handle");
        return ptr::null_mut();
    }
    
    let manager = match &managers[idx] {
        Some(m) => m,
        None => {
            set_error("Handle disposed");
            return ptr::null_mut();
        }
    };
    
    let encoded = manager.encode_full_viewing_key();
    CString::new(encoded)
        .expect("FVK encoding is valid: no null bytes")
        .into_raw()
}

/// Validate a Sapling address.
#[no_mangle]
pub extern "C" fn cw_pivx_validate_address(address: *const c_char, is_testnet: u8) -> u8 {
    if address.is_null() {
        return 0;
    }
    
    let address_str = unsafe {
        match CStr::from_ptr(address).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };
    
    let network = if is_testnet != 0 { Network::Testnet } else { Network::Mainnet };
    
    if validate_address(address_str, network) { 1 } else { 0 }
}

/// Initialize sync engine.
#[no_mangle]
pub extern "C" fn cw_pivx_init_sync_engine(_is_testnet: u8) -> i64 {
    let mut states = lock_or_fail!(SYNC_STATES, -1);
    let id = states.len() as i64;
    states.push(Some(SyncState::new()));
    id
}

/// Dispose sync engine.
#[no_mangle]
pub extern "C" fn cw_pivx_dispose_sync_engine(handle: i64) {
    let idx = handle as usize;
    let mut states = lock_or_fail!(SYNC_STATES, ());
    if idx < states.len() {
        states[idx] = None;
    }
}

/// Get the current sync height.
#[no_mangle]
pub extern "C" fn cw_pivx_get_sync_height(handle: i64) -> u32 {
    let states = lock_or_fail!(SYNC_STATES, 0);
    let idx = handle as usize;
    
    match states.get(idx).and_then(|s| s.as_ref()) {
        Some(state) => state.sync_height(),
        None => 0,
    }
}

/// Get the shielded balance.
#[no_mangle]
pub extern "C" fn cw_pivx_get_shielded_balance(handle: i64) -> u64 {
    let states = lock_or_fail!(SYNC_STATES, 0);
    let idx = handle as usize;
    
    match states.get(idx).and_then(|s| s.as_ref()) {
        Some(state) => state.shielded_balance(),
        None => 0,
    }
}

/// Get the number of unspent notes.
#[no_mangle]
pub extern "C" fn cw_pivx_get_unspent_note_count(handle: i64) -> usize {
    let states = lock_or_fail!(SYNC_STATES, 0);
    let idx = handle as usize;
    
    match states.get(idx).and_then(|s| s.as_ref()) {
        Some(state) => state.unspent_notes().len(),
        None => 0,
    }
}

/// Reset sync state.
#[no_mangle]
pub extern "C" fn cw_pivx_reset_sync(handle: i64) {
    let mut states = lock_or_fail!(SYNC_STATES, ());
    let idx = handle as usize;
    
    if let Some(Some(state)) = states.get_mut(idx) {
        *state = SyncState::new();
    }
}

/// Try to decrypt a Sapling output and add to sync state if successful.
/// 
/// This is the core function for detecting incoming shielded transactions.
/// It attempts trial decryption of a Sapling output using the wallet's
/// incoming viewing key.
/// 
/// # Parameters
/// * `key_handle` - Handle from cw_pivx_init_keys
/// * `sync_handle` - Handle from cw_pivx_init_sync_engine  
/// * `cmu` - Note commitment (32 bytes)
/// * `epk` - Ephemeral public key (32 bytes)
/// * `enc_ciphertext` - Encrypted ciphertext (580 bytes)
/// * `height` - Block height
/// * `tx_index` - Transaction index in block
/// * `output_index` - Output index in transaction
/// * `position` - Position in commitment tree
/// 
/// # Returns
/// The note value in zatoshis if decryption succeeds, 0 otherwise.
#[no_mangle]
pub extern "C" fn cw_pivx_try_decrypt_output(
    key_handle: i64,
    sync_handle: i64,
    cmu: *const u8,
    epk: *const u8,
    enc_ciphertext: *const u8,
    height: u32,
    tx_index: u32,
    output_index: u32,
    position: u64,
) -> u64 {
    // Validate inputs
    if cmu.is_null() || epk.is_null() || enc_ciphertext.is_null() {
        set_error("Null pointer provided");
        return 0;
    }
    
    // Get key manager
    let managers = lock_or_fail!(KEY_MANAGERS, 0);
    let key_manager = match managers.get(key_handle as usize).and_then(|m| m.as_ref()) {
        Some(m) => m,
        None => {
            set_error("Invalid key handle");
            return 0;
        }
    };
    
    // Parse cmu (note commitment) - 32 bytes
    let cmu_bytes: [u8; 32] = match unsafe { bytes_from_ffi_ptr(cmu, "cmu") } {
        Ok(bytes) => bytes,
        Err(e) => {
            set_error(&e);
            return 0;
        }
    };
    
    let cmu_extracted = match ExtractedNoteCommitment::from_bytes(&cmu_bytes).into_option() {
        Some(c) => c,
        None => {
            set_error("Invalid note commitment (cmu)");
            return 0; // Invalid commitment - this IS an error, not just "not for us"
        }
    };
    
    // Parse epk (ephemeral public key) - 32 bytes
    let epk_bytes: [u8; 32] = match unsafe { bytes_from_ffi_ptr(epk, "epk") } {
        Ok(bytes) => bytes,
        Err(e) => {
            set_error(&e);
            return 0;
        }
    };
    let ephemeral_key = EphemeralKeyBytes(epk_bytes);
    
    // Get encrypted ciphertext (580 bytes)
    let enc_bytes: [u8; ENC_CIPHERTEXT_SIZE] = match unsafe { bytes_from_ffi_ptr(enc_ciphertext, "enc_ciphertext") } {
        Ok(bytes) => bytes,
        Err(e) => {
            set_error(&e);
            return 0;
        }
    };
    
    // Create our trial decryption output
    let output = TrialDecryptionOutput {
        ephemeral_key,
        cmu: cmu_extracted,
        enc_ciphertext: enc_bytes,
    };
    
    // Get the incoming viewing key from the key manager and prepare it
    let dfvk = key_manager.diversifiable_full_viewing_key();
    let ivk = dfvk.fvk().vk.ivk();
    let prepared_ivk = PreparedIncomingViewingKey::new(&ivk);
    
    // PIVX does NOT enforce ZIP-212 (unlike Zcash post-Canopy)
    // librustpivx's zip212_enforcement() always returns Off for PIVX
    let zip212 = Zip212Enforcement::Off;
    
    // Try trial decryption
    let result = try_sapling_note_decryption(
        &prepared_ivk,
        &output,
        zip212,
    );
    
    match result {
        Some((note, address, _memo)) => {
            // Success! We received this note.
            let value = note.value().inner();
            
            // Compute nullifier for spending later
            let nf = note.nf(&dfvk.fvk().vk.nk, position);
            
            // Create spendable note
            let spendable_note = SpendableNote::new(
                note,
                address,
                position,
                nf,
                height,
                tx_index,
                output_index,
            );
            
            // Add to sync state
            drop(managers); // Release lock before acquiring another
            let mut states = lock_or_fail!(SYNC_STATES, 0);
            if let Some(Some(state)) = states.get_mut(sync_handle as usize) {
                let _ = state.add_note(spendable_note);
            }
            
            value
        }
        None => {
            // Not for us, or decryption failed
            0
        }
    }
}

/// Check if a nullifier matches any of our notes and mark them spent.
/// 
/// # Parameters
/// * `sync_handle` - Handle from cw_pivx_init_sync_engine
/// * `nullifier` - 32-byte nullifier to check
/// 
/// # Returns
/// 1 if a note was marked spent, 0 otherwise.
#[no_mangle]
pub extern "C" fn cw_pivx_check_nullifier(
    sync_handle: i64,
    nullifier: *const u8,
) -> u8 {
    if nullifier.is_null() {
        return 0;
    }
    
    let nf_bytes: [u8; 32] = unsafe { slice::from_raw_parts(nullifier, 32) }
        .try_into()
        .unwrap_or([0u8; 32]);
    
    let nf = match sapling::Nullifier::from_slice(&nf_bytes) {
        Ok(n) => n,
        Err(_) => return 0,
    };
    
    let mut states = lock_or_fail!(SYNC_STATES, 0);
    if let Some(Some(state)) = states.get_mut(sync_handle as usize) {
        if state.is_nullifier_spent(&nf) {
            return 0; // Already known
        }
        state.add_spent_nullifier(nf);
        return 1;
    }
    
    0
}

/// Update sync height after processing a block.
#[no_mangle]
pub extern "C" fn cw_pivx_set_sync_height(sync_handle: i64, height: u32) {
    let mut states = lock_or_fail!(SYNC_STATES, ());
    if let Some(Some(state)) = states.get_mut(sync_handle as usize) {
        state.set_sync_height(height);
    }
}

/// Estimate transaction fee.
/// Returns the estimated fee in zatoshis, or u64::MAX if overflow would occur.
#[no_mangle]
pub extern "C" fn cw_pivx_estimate_fee(
    spends: usize,
    outputs: usize,
    t_inputs: usize,
    t_outputs: usize,
) -> u64 {
    // PIVX fee calculation with overflow protection:
    // Base fee + per-input/output fees
    const BASE_FEE: u64 = 10_000; // 0.0001 PIVX
    const PER_SPEND: u64 = 10_000;
    const PER_OUTPUT: u64 = 5_000;
    const PER_TRANSPARENT: u64 = 2_000;
    
    // Validate inputs are in reasonable range (prevent overflow attacks)
    const MAX_INPUTS: usize = 10_000;
    if spends > MAX_INPUTS || outputs > MAX_INPUTS || 
       t_inputs > MAX_INPUTS || t_outputs > MAX_INPUTS {
        set_error("Too many inputs/outputs for fee calculation");
        return u64::MAX; // Signal error with saturated value
    }
    
    // Use checked arithmetic to prevent overflow
    let spend_fee = (spends as u64).checked_mul(PER_SPEND);
    let output_fee = (outputs as u64).checked_mul(PER_OUTPUT);
    let transparent_fee = ((t_inputs + t_outputs) as u64).checked_mul(PER_TRANSPARENT);
    
    match (spend_fee, output_fee, transparent_fee) {
        (Some(s), Some(o), Some(t)) => {
            // Now sum with saturation (safer than checked_add which can still fail)
            BASE_FEE.saturating_add(s).saturating_add(o).saturating_add(t)
        }
        _ => {
            set_error("Fee calculation overflow");
            u64::MAX
        }
    }
}

/// Check if proving parameters are available.
#[no_mangle]
pub extern "C" fn cw_pivx_has_proving_params(path: *const c_char) -> u8 {
    if path.is_null() {
        return 0;
    }
    
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };
    
    // Check if the spend and output params files exist
    let spend_path = format!("{}/sapling-spend.params", path_str);
    let output_path = format!("{}/sapling-output.params", path_str);
    
    if std::path::Path::new(&spend_path).exists() && std::path::Path::new(&output_path).exists() {
        1
    } else {
        0
    }
}

/// Initialize the Groth16 prover with the proving parameters.
/// 
/// This loads the ~50MB proving parameter files into memory.
/// Should be called once before any transaction building.
/// 
/// # Parameters
/// * `params_dir` - Path to directory containing sapling-spend.params and sapling-output.params
/// 
/// # Returns
/// 0 on success, negative on error
#[no_mangle]
pub extern "C" fn cw_pivx_init_prover(params_dir: *const c_char) -> i32 {
    if params_dir.is_null() {
        set_error("Null params directory");
        return -1;
    }
    
    let dir_str = unsafe {
        match CStr::from_ptr(params_dir).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid path encoding");
                return -1;
            }
        }
    };
    
    match crate::prover::init_prover(dir_str) {
        Ok(()) => 0,
        Err(e) => {
            set_error(&format!("Failed to init prover: {}", e));
            -1
        }
    }
}

/// Check if the prover is initialized.
#[no_mangle]
pub extern "C" fn cw_pivx_is_prover_initialized() -> u8 {
    if crate::prover::is_prover_initialized() { 1 } else { 0 }
}

/// Free the prover and release memory (~50MB).
#[no_mangle]
pub extern "C" fn cw_pivx_dispose_prover() {
    crate::prover::dispose_prover();
}

/// Get all spendable notes from the sync state as JSON.
/// 
/// Returns a JSON array of note objects, each containing all data
/// needed for transaction building including the rseed and diversifier.
/// 
/// # Parameters
/// * `sync_handle` - Handle from cw_pivx_init_sync_engine
/// 
/// # Returns
/// JSON string with note data, or null on error.
/// Caller must free with cw_pivx_free_string.
#[no_mangle]
pub extern "C" fn cw_pivx_get_spendable_notes(sync_handle: i64) -> *mut c_char {
    let states = lock_or_fail!(SYNC_STATES, ptr::null_mut());
    
    let sync_state = match states.get(sync_handle as usize).and_then(|s| s.as_ref()) {
        Some(s) => s,
        None => {
            set_error("Invalid sync handle");
            return ptr::null_mut();
        }
    };
    
    // Get unspent notes
    let notes = sync_state.unspent_notes();
    
    // Build JSON array
    let notes_json: Vec<serde_json::Value> = notes.iter().map(|note| {
        // Get the raw note components for serialization
        // For BeforeZip212, rseed is an Fr scalar (32 bytes)
        // For AfterZip212, rseed is raw [u8; 32]
        let rseed_bytes = match note.note.rseed() {
            sapling::Rseed::BeforeZip212(fr_value) => {
                // Convert Fr to bytes using to_bytes() if available, or serialize
                // The Fr type from jubjub should have to_bytes() 
                hex::encode(fr_value.to_bytes())
            },
            sapling::Rseed::AfterZip212(bytes) => hex::encode(bytes),
        };
        
        // Get recipient address bytes
        let recipient = note.note.recipient();
        let addr_bytes = recipient.to_bytes();
        
        // Get diversifier
        let diversifier_bytes = recipient.diversifier().0;
        
        // Compute note commitment (cmu) for witness fetching
        // This is the hash of the note that goes into the commitment tree
        let cmu = note.note.cmu();
        let cmu_bytes = cmu.to_bytes();
        
        // Get pk_d (diversified transmission key) for note reconstruction
        // Use inner() to get the jubjub point, then serialize it
        let pk_d = recipient.pk_d();
        let pk_d_bytes = pk_d.inner().to_bytes();
        
        // For rcm, we use rseed in BeforeZip212 mode (PIVX)
        // In this mode, rcm == rseed
        let rcm_bytes = match note.note.rseed() {
            sapling::Rseed::BeforeZip212(fr_value) => hex::encode(fr_value.to_bytes()),
            sapling::Rseed::AfterZip212(bytes) => hex::encode(bytes),
        };
        
        serde_json::json!({
            "value": note.value(),
            "position": note.position,
            "height": note.height,
            "tx_index": note.tx_index,
            "output_index": note.output_index,
            "nullifier": hex::encode(note.nullifier.0),
            "rseed": rseed_bytes,
            "rcm": rcm_bytes,
            "address": hex::encode(addr_bytes),
            "diversifier": hex::encode(diversifier_bytes),
            "pk_d": hex::encode(pk_d_bytes),
            "cmu": hex::encode(cmu_bytes),
        })
    }).collect();
    
    let json_str = serde_json::to_string(&notes_json).unwrap_or_else(|_| "[]".to_string());
    CString::new(json_str)
        .expect("JSON string is valid: no null bytes")
        .into_raw()
}

/// Restore a note from JSON data.
/// 
/// This allows restoring notes from persistent storage after app restart.
/// The JSON should contain the same fields returned by cw_pivx_get_spendable_notes.
/// 
/// # Parameters
/// * `key_handle` - Handle from cw_pivx_init_keys  
/// * `sync_handle` - Handle from cw_pivx_init_sync_engine
/// * `note_json` - JSON string with note data
/// 
/// # Returns
/// 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn cw_pivx_restore_note(
    key_handle: i64,
    sync_handle: i64,
    note_json: *const c_char,
) -> i32 {
    if note_json.is_null() {
        set_error("Null note JSON");
        return 0;
    }
    
    let json_str = match unsafe { CStr::from_ptr(note_json).to_str() } {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid UTF-8 in note JSON");
            return 0;
        }
    };
    
    // Parse JSON
    let note_data: serde_json::Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            set_error(&format!("Invalid JSON: {}", e));
            return 0;
        }
    };
    
    // Extract fields
    let value = note_data["value"].as_u64().unwrap_or(0);
    let position = note_data["position"].as_u64().unwrap_or(0);
    let height = note_data["height"].as_u64().unwrap_or(0) as u32;
    let tx_index = note_data["tx_index"].as_u64().unwrap_or(0) as u32;
    let output_index = note_data["output_index"].as_u64().unwrap_or(0) as u32;
    
    // Get hex-encoded fields
    let rseed_hex = note_data["rseed"].as_str().unwrap_or("");
    let address_hex = note_data["address"].as_str().unwrap_or("");
    let nullifier_hex = note_data["nullifier"].as_str().unwrap_or("");
    
    // Parse rseed (32 bytes Fr scalar for BeforeZip212)
    let rseed_bytes: [u8; 32] = match hex::decode(rseed_hex) {
        Ok(bytes) if bytes.len() == 32 => bytes.try_into()
            .expect("Length checked: rseed is exactly 32 bytes"),
        _ => {
            set_error("Invalid rseed");
            return 0;
        }
    };
    
    // Parse address (43 bytes - 11 byte diversifier + 32 byte pk_d)
    let address_bytes: [u8; 43] = match hex::decode(address_hex) {
        Ok(bytes) if bytes.len() == 43 => bytes.try_into()
            .expect("Length checked: address is exactly 43 bytes"),
        _ => {
            set_error(&format!("Invalid address: expected 43 bytes, got {} from '{}'", 
                hex::decode(address_hex).map(|b| b.len()).unwrap_or(0), address_hex));
            return 0;
        }
    };
    
    // Parse nullifier (32 bytes)
    let nullifier_bytes: [u8; 32] = match hex::decode(nullifier_hex) {
        Ok(bytes) if bytes.len() == 32 => bytes.try_into()
            .expect("Length checked: nullifier is exactly 32 bytes"),
        _ => {
            set_error("Invalid nullifier");
            return 0;
        }
    };
    
    // Reconstruct the note components
    use sapling::{PaymentAddress, Rseed, value::NoteValue};
    
    // Parse payment address from bytes (includes diversifier + pk_d)
    let address = match PaymentAddress::from_bytes(&address_bytes) {
        Some(a) => a,
        None => {
            set_error("Invalid payment address bytes");
            return 0;
        }
    };
    
    // Create rseed - PIVX uses BeforeZip212
    let rseed_fr = match jubjub::Fr::from_bytes(&rseed_bytes).into_option() {
        Some(fr) => fr,
        None => {
            set_error("Invalid rseed Fr");
            return 0;
        }
    };
    let rseed = Rseed::BeforeZip212(rseed_fr);
    
    // Create the note
    let note = sapling::Note::from_parts(
        address,
        NoteValue::from_raw(value),
        rseed,
    );
    
    // Create nullifier
    let nullifier = sapling::Nullifier(nullifier_bytes);
    
    // Create spendable note
    let spendable_note = SpendableNote::new(
        note,
        address,
        position,
        nullifier,
        height,
        tx_index,
        output_index,
    );
    
    // Add to sync state
    let mut states = lock_or_fail!(SYNC_STATES, -1);
    if let Some(Some(state)) = states.get_mut(sync_handle as usize) {
        let _ = state.add_note(spendable_note);
        1
    } else {
        set_error("Invalid sync handle");
        0
    }
}

/// Create a shielded transaction.
/// Returns an FFIBuffer containing the raw transaction bytes.
#[no_mangle]
pub extern "C" fn cw_pivx_create_transaction(
    key_handle: i64,
    sync_handle: i64,
    to_address: *const c_char,
    amount: u64,
    memo: *const c_char,
    height: u32,
    proving_params_path: *const c_char,
) -> FFIBuffer {
    let empty_result = FFIBuffer { data: ptr::null_mut(), len: 0 };
    
    if to_address.is_null() || proving_params_path.is_null() {
        set_error("Invalid parameters");
        return empty_result;
    }
    
    let _to_str = unsafe {
        match CStr::from_ptr(to_address).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid address encoding");
                return empty_result;
            }
        }
    };
    
    let _memo_str = if memo.is_null() {
        None
    } else {
        unsafe {
            match CStr::from_ptr(memo).to_str() {
                Ok(s) => Some(s.to_string()),
                Err(_) => None,
            }
        }
    };
    
    let _params_path = unsafe {
        match CStr::from_ptr(proving_params_path).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid params path");
                return empty_result;
            }
        }
    };
    
    // Get key manager and sync state
    let managers = lock_or_fail!(KEY_MANAGERS, empty_result);
    let states = lock_or_fail!(SYNC_STATES, empty_result);
    
    let _key_manager = match managers.get(key_handle as usize).and_then(|m| m.as_ref()) {
        Some(m) => m,
        None => {
            set_error("Invalid key handle");
            return empty_result;
        }
    };
    
    let _sync_state = match states.get(sync_handle as usize).and_then(|s| s.as_ref()) {
        Some(s) => s,
        None => {
            set_error("Invalid sync handle");
            return empty_result;
        }
    };
    
    // Transaction building requires:
    // 1. Note selection from sync state
    // 2. Witness generation
    // 3. Proof generation using proving params
    // 4. Transaction serialization
    //
    // This is a placeholder - full implementation requires:
    // - Loading proving parameters from files
    // - Creating Groth16 proofs
    // - Building complete PIVX Sapling transaction
    
    // For now, return an error indicating not yet implemented
    set_error(&format!(
        "Transaction building not yet fully implemented. Amount: {}, Height: {}",
        amount, height
    ));
    empty_result
}

/// Build a shielded transaction with explicit note and witness data.
/// 
/// This is the more complete transaction building function that accepts
/// pre-computed witnesses from the caller (typically fetched from ElectrumX).
/// 
/// # Parameters
/// * `key_handle` - Handle from cw_pivx_init_keys
/// * `notes_json` - JSON array of spendable notes with witnesses
/// * `to_address` - Recipient address (ps1... format)  
/// * `amount` - Amount in zatoshis
/// * `memo` - Optional memo (512 bytes max, null for none)
/// * `fee` - Fee in zatoshis
/// * `anchor_hex` - Current anchor (merkle root) as 32-byte hex
/// 
/// # Returns
/// FFIBuffer containing JSON with txid and tx_hex, or empty on error
#[no_mangle]
pub extern "C" fn cw_pivx_build_shielded_tx(
    key_handle: i64,
    notes_json: *const c_char,
    to_address: *const c_char,
    amount: u64,
    memo: *const c_char,
    fee: u64,
    anchor_hex: *const c_char,
) -> FFIBuffer {
    let empty_result = FFIBuffer { data: ptr::null_mut(), len: 0 };
    
    // Validate inputs
    if notes_json.is_null() || to_address.is_null() || anchor_hex.is_null() {
        set_error("Null parameter provided");
        return empty_result;
    }
    
    // Validate amount and fee ranges
    if let Err(e) = validate_amount(amount, "amount") {
        set_error(&e);
        return empty_result;
    }
    if let Err(e) = validate_fee(fee) {
        set_error(&e);
        return empty_result;
    }
    
    // Check prover is initialized
    if !crate::prover::is_prover_initialized() {
        set_error("Prover not initialized. Call cw_pivx_init_prover first.");
        return empty_result;
    }
    
    // Parse string parameters
    let notes_str = unsafe {
        match CStr::from_ptr(notes_json).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid notes JSON encoding");
                return empty_result;
            }
        }
    };
    
    let to_str = unsafe {
        match CStr::from_ptr(to_address).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid address encoding");
                return empty_result;
            }
        }
    };
    
    let anchor_str = unsafe {
        match CStr::from_ptr(anchor_hex).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid anchor encoding");
                return empty_result;
            }
        }
    };
    
    let memo_str = if memo.is_null() {
        None
    } else {
        unsafe {
            match CStr::from_ptr(memo).to_str() {
                Ok(s) if !s.is_empty() => Some(s.to_string()),
                _ => None,
            }
        }
    };
    
    // Validate memo length
    if let Err(e) = validate_memo(memo_str.as_deref()) {
        set_error(&e);
        return empty_result;
    }
    
    // Validate string lengths to prevent DoS
    if let Err(e) = validate_string_length(notes_str, 1_000_000, "notes_json") {
        set_error(&e);
        return empty_result;
    }
    if let Err(e) = validate_string_length(to_str, 1000, "to_address") {
        set_error(&e);
        return empty_result;
    }
    if let Err(e) = validate_string_length(anchor_str, 100, "anchor_hex") {
        set_error(&e);
        return empty_result;
    }
    
    // Get key manager
    let managers = lock_or_fail!(KEY_MANAGERS, empty_result);
    let key_manager = match managers.get(key_handle as usize).and_then(|m| m.as_ref()) {
        Some(m) => m,
        None => {
            set_error("Invalid key handle");
            return empty_result;
        }
    };
    
    // Parse notes JSON
    let notes_data: Vec<crate::types::SpendableNoteData> = match serde_json::from_str(notes_str) {
        Ok(n) => n,
        Err(e) => {
            set_error(&format!("Failed to parse notes JSON: {}", e));
            return empty_result;
        }
    };
    
    if notes_data.is_empty() {
        set_error("No notes provided");
        return empty_result;
    }
    
    // Validate we have enough balance
    let total_input: u64 = notes_data.iter().map(|n| n.value).sum();
    if total_input < amount + fee {
        set_error(&format!(
            "Insufficient funds: have {} zatoshis, need {} + {} fee",
            total_input, amount, fee
        ));
        return empty_result;
    }
    
    // Parse destination address
    let recipient = match key_manager.decode_payment_address(to_str) {
        Ok(addr) => addr,
        Err(e) => {
            set_error(&format!("Invalid recipient address: {}", e));
            return empty_result;
        }
    };
    
    // Parse anchor
    let anchor_bytes: [u8; 32] = match hex::decode(anchor_str) {
        Ok(bytes) if bytes.len() == 32 => bytes.try_into()
            .expect("Length checked: anchor is exactly 32 bytes"),
        _ => {
            set_error("Invalid anchor: must be 32-byte hex");
            return empty_result;
        }
    };
    
    // Parse the anchor into a sapling Anchor
    let anchor = match sapling::Anchor::from_bytes(anchor_bytes).into_option() {
        Some(a) => a,
        None => {
            set_error("Invalid anchor bytes");
            return empty_result;
        }
    };
    
    // Reconstruct notes and merkle paths from the JSON data
    let mut spendable_notes = Vec::with_capacity(notes_data.len());
    let mut merkle_paths = Vec::with_capacity(notes_data.len());
    
    for (idx, note_data) in notes_data.iter().enumerate() {
        // Reconstruct the Note
        let (note, address) = match crate::notes::note_from_parts(
            &note_data.diversifier,
            &note_data.pk_d,
            note_data.value,
            &note_data.rseed,
        ) {
            Ok(n) => n,
            Err(e) => {
                set_error(&format!("Failed to reconstruct note {}: {}", idx, e));
                return empty_result;
            }
        };
        
        // Parse the nullifier
        let nullifier_bytes: [u8; 32] = match hex::decode(&note_data.nullifier) {
            Ok(bytes) if bytes.len() == 32 => bytes.try_into()
                .expect("Length checked: nullifier is exactly 32 bytes"),
            _ => {
                set_error(&format!("Invalid nullifier for note {}", idx));
                return empty_result;
            }
        };
        let nullifier = sapling::Nullifier(nullifier_bytes);
        
        // Create SpendableNote with position from witness data
        let position = note_data.witness_position;
        let spendable = crate::notes::SpendableNote::new(
            note,
            address,
            position, // Use witness_position from ElectrumX response
            nullifier,
            0, // height - not critical for spending
            0, // tx_index
            0, // output_index  
        );
        spendable_notes.push(spendable);
        
        // Parse merkle path from witness
        // The witness field contains the path elements (32-byte hashes concatenated)
        // Position is now passed separately from the witness_position field
        let path = match crate::notes::parse_merkle_path(&note_data.witness, position) {
            Ok(p) => p,
            Err(e) => {
                set_error(&format!("Failed to parse witness for note {}: {}", idx, e));
                return empty_result;
            }
        };
        merkle_paths.push(path);
    }
    
    // Parse memo if provided
    let memo_bytes: Option<[u8; 512]> = memo_str.as_ref().map(|m| {
        let mut bytes = [0u8; 512];
        let m_bytes = m.as_bytes();
        let len = m_bytes.len().min(512);
        bytes[..len].copy_from_slice(&m_bytes[..len]);
        bytes
    });
    
    // Build the outputs list
    let outputs = vec![(recipient, amount, memo_bytes)];
    
    // Create transaction builder
    let tx_builder = crate::transaction::TransactionBuilder::new(
        key_manager.extended_spending_key().clone(),
        key_manager.diversifiable_full_viewing_key().clone(),
        key_manager.network() == crate::types::Network::Testnet,
    );
    
    // Build the transaction
    match tx_builder.build_transaction(
        spendable_notes,
        merkle_paths,
        anchor,
        outputs,
        fee,
    ) {
        Ok(built_tx) => {
            // Success! Return the transaction
            let result = serde_json::json!({
                "status": "success",
                "txid": hex::encode(built_tx.txid),
                "tx_hex": hex::encode(&built_tx.raw_tx),
                "fee": built_tx.fee,
            });
            
            let result_str = result.to_string();
            let result_bytes = result_str.as_bytes();
            
            let data = unsafe {
                let ptr = libc::malloc(result_bytes.len()) as *mut u8;
                if ptr.is_null() {
                    set_error("Memory allocation failed");
                    return empty_result;
                }
                ptr::copy_nonoverlapping(result_bytes.as_ptr(), ptr, result_bytes.len());
                ptr
            };
            
            FFIBuffer {
                data,
                len: result_bytes.len(),
            }
        }
        Err(e) => {
            // Return error details as JSON so caller can understand what happened
            let result = serde_json::json!({
                "status": "error",
                "error": format!("{}", e),
                "notes_count": notes_data.len(),
                "total_input": total_input,
                "amount": amount,
                "fee": fee,
            });
            
            let result_str = result.to_string();
            let result_bytes = result_str.as_bytes();
            
            let data = unsafe {
                let ptr = libc::malloc(result_bytes.len()) as *mut u8;
                if ptr.is_null() {
                    set_error(&format!("Transaction build failed: {}", e));
                    return empty_result;
                }
                ptr::copy_nonoverlapping(result_bytes.as_ptr(), ptr, result_bytes.len());
                ptr
            };
            
            FFIBuffer {
                data,
                len: result_bytes.len(),
            }
        }
    }
}// ============================================================================
// Legacy function names for backward compatibility
// ============================================================================

#[no_mangle]
pub extern "C" fn pivx_sapling_init() -> i32 {
    0 // Success
}

#[no_mangle]
pub extern "C" fn pivx_sapling_create_from_seed(
    seed: *const u8,
    seed_len: usize,
    is_testnet: i32,
    session_id: *mut i32,
) -> i32 {
    let handle = cw_pivx_init_keys(seed, seed_len, is_testnet as u8);
    if handle < 0 {
        -1
    } else {
        unsafe { *session_id = handle as i32 };
        0
    }
}

#[no_mangle]
pub extern "C" fn pivx_sapling_destroy(session_id: i32) -> i32 {
    cw_pivx_dispose_keys(session_id as i64);
    0
}

#[no_mangle]
pub extern "C" fn pivx_sapling_get_balance(session_id: i32) -> i64 {
    cw_pivx_get_shielded_balance(session_id as i64) as i64
}

#[no_mangle]
pub extern "C" fn pivx_sapling_get_sync_height(session_id: i32) -> i32 {
    cw_pivx_get_sync_height(session_id as i64) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ffi_init_keys() {
        let seed = [0u8; 64];
        
        let handle = cw_pivx_init_keys(seed.as_ptr(), seed.len(), 0);
        assert!(handle >= 0);
        
        cw_pivx_dispose_keys(handle);
    }
    
    #[test]
    fn test_ffi_get_address() {
        let seed = [1u8; 64];
        
        let handle = cw_pivx_init_keys(seed.as_ptr(), seed.len(), 0);
        assert!(handle >= 0);
        
        let address_ptr = cw_pivx_get_default_address(handle);
        assert!(!address_ptr.is_null());
        
        let address = unsafe { CStr::from_ptr(address_ptr) }
            .to_str()
            .unwrap();
        
        assert!(address.starts_with("ps"));
        
        cw_pivx_free_string(address_ptr);
        cw_pivx_dispose_keys(handle);
    }
    
    #[test]
    fn test_ffi_validate_address() {
        let valid = "ps1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqf0vjel";
        let valid_ptr = CString::new(valid)
            .expect("Test string is valid: no null bytes");
        
        // This will fail validation because it's a dummy address, but the FFI call should work
        let _result = cw_pivx_validate_address(valid_ptr.as_ptr(), 0);
        // Address validation is tested in keys.rs
    }
    
    #[test]
    fn test_ffi_estimate_fee() {
        let fee = cw_pivx_estimate_fee(2, 2, 1, 1);
        assert!(fee > 0);
    }
    
    #[test]
    fn test_ffi_sync_engine() {
        let handle = cw_pivx_init_sync_engine(0);
        assert!(handle >= 0);
        
        let height = cw_pivx_get_sync_height(handle);
        assert_eq!(height, 0); // Fresh sync state
        
        let balance = cw_pivx_get_shielded_balance(handle);
        assert_eq!(balance, 0);
        
        let count = cw_pivx_get_unspent_note_count(handle);
        assert_eq!(count, 0);
        
        cw_pivx_dispose_sync_engine(handle);
    }
}
