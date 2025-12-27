/// Sapling note storage.
/// 
/// Provides persistent storage for Sapling notes discovered during
/// blockchain sync. Notes are stored as JSON in a file.

import 'dart:convert';
import 'dart:io';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

/// Represents a stored Sapling note.
class StoredSaplingNote {
  /// Unique identifier (txid:index).
  final String id;
  
  /// The value in zatoshis.
  final int value;
  
  /// Block height where this note was created.
  final int height;
  
  /// Transaction ID that created this note.
  final String txid;
  
  /// Output index within the transaction.
  final int outputIndex;
  
  /// Position in the commitment tree.
  final int treePosition;
  
  /// Note commitment (cmu) as hex.
  final String cmu;
  
  /// Nullifier as hex (computed when we have spending key).
  final String? nullifier;
  
  /// Whether this note has been spent.
  bool isSpent;
  
  /// Transaction ID that spent this note (if spent).
  String? spendingTxid;
  
  /// Timestamp when the note was discovered.
  final DateTime discoveredAt;
  
  /// Optional memo.
  final String? memo;
  
  // Cryptographic data needed to restore note to native engine
  /// Random seed (rseed) as hex - 32 bytes
  final String? rseed;
  
  /// Diversifier as hex - 11 bytes
  final String? diversifier;
  
  /// Diversified transmission key (pk_d) as hex - 32 bytes
  final String? pkD;
  
  /// Recipient address as hex
  final String? address;
  
  /// Transaction index within the block
  final int? txIndex;

  StoredSaplingNote({
    required this.id,
    required this.value,
    required this.height,
    required this.txid,
    required this.outputIndex,
    required this.treePosition,
    required this.cmu,
    this.nullifier,
    this.isSpent = false,
    this.spendingTxid,
    DateTime? discoveredAt,
    this.memo,
    this.rseed,
    this.diversifier,
    this.pkD,
    this.address,
    this.txIndex,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  /// Create from JSON.
  factory StoredSaplingNote.fromJson(Map<String, dynamic> json) {
    return StoredSaplingNote(
      id: json['id'] as String,
      value: json['value'] as int,
      height: json['height'] as int,
      txid: json['txid'] as String,
      outputIndex: json['outputIndex'] as int,
      treePosition: json['treePosition'] as int,
      cmu: json['cmu'] as String,
      nullifier: json['nullifier'] as String?,
      isSpent: json['isSpent'] as bool? ?? false,
      spendingTxid: json['spendingTxid'] as String?,
      discoveredAt: json['discoveredAt'] != null 
          ? DateTime.parse(json['discoveredAt'] as String)
          : null,
      memo: json['memo'] as String?,
      rseed: json['rseed'] as String?,
      diversifier: json['diversifier'] as String?,
      pkD: json['pk_d'] as String? ?? json['pkD'] as String?,
      address: json['address'] as String?,
      txIndex: json['tx_index'] as int? ?? json['txIndex'] as int?,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'value': value,
      'height': height,
      'txid': txid,
      'outputIndex': outputIndex,
      'treePosition': treePosition,
      'cmu': cmu,
      'nullifier': nullifier,
      'isSpent': isSpent,
      'spendingTxid': spendingTxid,
      'discoveredAt': discoveredAt.toIso8601String(),
      'memo': memo,
      'rseed': rseed,
      'diversifier': diversifier,
      'pk_d': pkD,
      'address': address,
      'tx_index': txIndex,
    };
  }
  
  /// Convert to JSON format needed by native restore API.
  /// Uses the exact keys expected by cw_pivx_restore_note.
  Map<String, dynamic> toNativeRestoreJson() {
    // The address field should be diversifier + pk_d concatenated (43 bytes as hex = 86 chars)
    final addressHex = address ?? ((diversifier ?? '') + (pkD ?? ''));
    
    return {
      'value': value,
      'position': treePosition,
      'height': height,
      'tx_index': txIndex ?? 0,
      'output_index': outputIndex,
      'nullifier': nullifier ?? '',
      'rseed': rseed ?? '',
      'address': addressHex,
      'diversifier': diversifier ?? '',
      'pk_d': pkD ?? '',
      'cmu': cmu,
    };
  }
  
  /// Check if this note has all the cryptographic data needed for spending.
  bool get hasSpendingData => 
      rseed != null && 
      diversifier != null && 
      pkD != null && 
      nullifier != null;

  /// The value in PIVX.
  double get valuePivx => value / 100000000.0;
}

/// Represents a stored shielded address.
class StoredShieldedAddress {
  /// The diversifier index used to derive this address.
  final int diversifierIndex;
  
  /// The encoded address (ps1...).
  final String address;
  
  /// Optional label for this address.
  String? label;
  
  /// Whether this is the default address (index 0).
  final bool isDefault;
  
  /// Timestamp when this address was created.
  final DateTime createdAt;

  StoredShieldedAddress({
    required this.diversifierIndex,
    required this.address,
    this.label,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create from JSON.
  factory StoredShieldedAddress.fromJson(Map<String, dynamic> json) {
    return StoredShieldedAddress(
      diversifierIndex: json['diversifierIndex'] as int,
      address: json['address'] as String,
      label: json['label'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'diversifierIndex': diversifierIndex,
      'address': address,
      'label': label,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Storage for Sapling notes.
class SaplingNoteStorage {
  final String walletId;
  final bool isTestnet;
  
  List<StoredSaplingNote> _notes = [];
  List<StoredShieldedAddress> _addresses = [];
  int _lastSyncedHeight = 0;
  int _nextDiversifierIndex = 1; // 0 is the default address
  bool _isLoaded = false;
  final Lock _lock = Lock(); // Thread safety for concurrent access

  SaplingNoteStorage({
    required this.walletId,
    this.isTestnet = false,
  });

  /// Get all notes.
  List<StoredSaplingNote> get notes => List.unmodifiable(_notes);

  /// Get all shielded addresses.
  List<StoredShieldedAddress> get addresses => List.unmodifiable(_addresses);

  /// Get the next diversifier index to use.
  int get nextDiversifierIndex => _nextDiversifierIndex;

  /// Get unspent notes.
  List<StoredSaplingNote> get unspentNotes => 
      _notes.where((n) => !n.isSpent).toList();

  /// Get total balance (unspent notes).
  /// Note: For thread-safe balance in concurrent scenarios, use getBalanceSafe()
  int get balance => unspentNotes.fold<int>(0, (sum, n) => sum + n.value);
  
  /// Get total balance (thread-safe version for concurrent access).
  Future<int> getBalanceSafe() async {
    return await _lock.synchronized<int>(() {
      return unspentNotes.fold<int>(0, (sum, n) => sum + n.value);
    });
  }

  /// Get last synced height.
  int get lastSyncedHeight => _lastSyncedHeight;

  /// Get the storage file path.
  Future<String> get _storagePath async {
    final dir = await getApplicationDocumentsDirectory();
    final network = isTestnet ? 'testnet' : 'mainnet';
    return '${dir.path}/pivx_sapling_${walletId}_$network.json';
  }

  /// Load notes from storage.
  Future<void> load() async {
    if (_isLoaded) return;
    
    try {
      final path = await _storagePath;
      final file = File(path);
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents) as Map<String, dynamic>;
        
        _lastSyncedHeight = data['lastSyncedHeight'] as int? ?? 0;
        _nextDiversifierIndex = data['nextDiversifierIndex'] as int? ?? 1;
        _notes = (data['notes'] as List<dynamic>?)
            ?.map((e) => StoredSaplingNote.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
        _addresses = (data['addresses'] as List<dynamic>?)
            ?.map((e) => StoredShieldedAddress.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
      }
      
      _isLoaded = true;
    } catch (e) {
      printV('[PIVX Sapling Storage] Failed to load: $e');
      _notes = [];
      _addresses = [];
      _lastSyncedHeight = 0;
      _nextDiversifierIndex = 1;
      _isLoaded = true;
    }
  }

  /// Save notes to storage (thread-safe public method).
  Future<void> save() async {
    await _lock.synchronized(() async {
      await _save();
    });
  }
  
  /// Internal save method (must be called within lock).
  Future<void> _save() async {
    try {
      final path = await _storagePath;
      final file = File(path);
      
      final data = {
        'lastSyncedHeight': _lastSyncedHeight,
        'nextDiversifierIndex': _nextDiversifierIndex,
        'notes': _notes.map((n) => n.toJson()).toList(),
        'addresses': _addresses.map((a) => a.toJson()).toList(),
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      printV('[PIVX Sapling Storage] Failed to save: $e');
    }
  }
  
  /// Clear all notes and reset sync state.
  /// Used for rescanning the blockchain.
  Future<void> clear() async {
    _notes = [];
    _lastSyncedHeight = 0;
    // Keep addresses, they're derived deterministically
    await save();
    printV('[PIVX Sapling Storage] Cleared all notes for rescan');
  }

  /// Add a new note (thread-safe).
  Future<void> addNote(StoredSaplingNote note) async {
    await _lock.synchronized(() async {
      // Check if note already exists
      final existing = _notes.indexWhere((n) => n.id == note.id);
      if (existing >= 0) {
        // Update existing
        _notes[existing] = note;
      } else {
        _notes.add(note);
      }
      await _save();
    });
  }

  /// Mark a note as spent (thread-safe).
  Future<void> markSpent(String noteId, String spendingTxid) async {
    await _lock.synchronized(() async {
      final note = _notes.firstWhere((n) => n.id == noteId);
      note.isSpent = true;
      note.spendingTxid = spendingTxid;
      await _save();
    });
  }

  /// Mark notes spent by nullifier (thread-safe).
  Future<bool> markSpentByNullifier(String nullifier, String spendingTxid) async {
    return await _lock.synchronized(() async {
      final note = _notes.cast<StoredSaplingNote?>().firstWhere(
        (n) => n?.nullifier == nullifier,
        orElse: () => null,
      );
      
      if (note != null) {
        note.isSpent = true;
        note.spendingTxid = spendingTxid;
        await _save();
        return true;
      }
      return false;
    });
  }

  /// Update the last synced height (thread-safe).
  Future<void> setLastSyncedHeight(int height) async {
    await _lock.synchronized(() async {
      _lastSyncedHeight = height;
      await _save();
    });
  }

  /// Get notes in a height range.
  List<StoredSaplingNote> getNotesInRange(int startHeight, int endHeight) {
    return _notes.where((n) => n.height >= startHeight && n.height <= endHeight).toList();
  }

  // ============================================================================
  // Shielded Address Management
  // ============================================================================

  /// Add a new shielded address.
  Future<void> addAddress(StoredShieldedAddress address) async {
    // Check if address already exists
    final existing = _addresses.indexWhere((a) => a.address == address.address);
    if (existing >= 0) {
      // Update existing
      _addresses[existing] = address;
    } else {
      _addresses.add(address);
    }
    // Update next index if needed
    if (address.diversifierIndex >= _nextDiversifierIndex) {
      _nextDiversifierIndex = address.diversifierIndex + 1;
    }
    await save();
  }

  /// Get the next diversifier index and increment it.
  int getAndIncrementDiversifierIndex() {
    final index = _nextDiversifierIndex;
    _nextDiversifierIndex++;
    return index;
  }

  /// Update an address label.
  Future<void> updateAddressLabel(String address, String? label) async {
    final stored = _addresses.cast<StoredShieldedAddress?>().firstWhere(
      (a) => a?.address == address,
      orElse: () => null,
    );
    if (stored != null) {
      stored.label = label;
      await save();
    }
  }

  /// Get an address by its encoded form.
  StoredShieldedAddress? getAddressByEncoded(String address) {
    return _addresses.cast<StoredShieldedAddress?>().firstWhere(
      (a) => a?.address == address,
      orElse: () => null,
    );
  }

  /// Clear addresses (keeps notes and sync state).
  Future<void> clearAddresses() async {
    _addresses.clear();
    _nextDiversifierIndex = 1;
    await save();
  }
}
