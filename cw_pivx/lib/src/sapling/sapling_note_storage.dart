/// Sapling note storage.
///
/// Provides persistent storage for Sapling notes discovered during
/// blockchain sync. Notes are stored as JSON in a file.

import 'dart:convert';
import 'dart:io';
import 'package:cw_core/encryption_file_utils.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

/// Provisional PIVX shielded confirmation policy used by wallet-side balance
/// separation until release owner/canonical Core policy is confirmed.
class PivxShieldedConfirmationPolicy {
  static const int receiveConfirmations = 6;
  static const int spendConfirmations = 6;
}

/// Count-only shielded spend eligibility diagnostics.
///
/// This intentionally avoids values, txids, commitments, nullifiers, and
/// addresses so release/debug logs can explain selection failures without
/// exposing wallet metadata.
class PivxShieldedSpendEligibilitySummary {
  final int chainHeight;
  final int minConfirmations;
  final int totalUnspent;
  final int spendable;
  final int pendingConfirmation;
  final int pendingSpend;
  final int missingSpendingData;

  const PivxShieldedSpendEligibilitySummary({
    required this.chainHeight,
    required this.minConfirmations,
    required this.totalUnspent,
    required this.spendable,
    required this.pendingConfirmation,
    required this.pendingSpend,
    required this.missingSpendingData,
  });

  String get sanitizedLogLine =>
      'chain_height=$chainHeight min_confirmations=$minConfirmations '
      'total_unspent=$totalUnspent spendable=$spendable '
      'pending_confirmations=$pendingConfirmation '
      'pending_spend=$pendingSpend missing_spending_data=$missingSpendingData';
}

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

  /// Whether this note is reserved by a locally broadcast shielded spend that
  /// has not been observed in a mined Sapling spend yet.
  bool isPendingSpend;

  /// Transaction ID that spent this note (if spent).
  String? spendingTxid;

  /// Block height where this note's nullifier was mined as spent.
  int? spendingHeight;

  /// Transaction ID that is expected to spend this note, if pending.
  String? pendingSpendingTxid;

  /// Timestamp when the outgoing spend reservation was recorded.
  DateTime? pendingSpendAt;

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
    this.isPendingSpend = false,
    this.spendingTxid,
    this.spendingHeight,
    this.pendingSpendingTxid,
    this.pendingSpendAt,
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
      isPendingSpend: json['isPendingSpend'] as bool? ?? false,
      spendingTxid: json['spendingTxid'] as String?,
      spendingHeight: json['spendingHeight'] as int?,
      pendingSpendingTxid: json['pendingSpendingTxid'] as String?,
      pendingSpendAt: json['pendingSpendAt'] != null
          ? DateTime.parse(json['pendingSpendAt'] as String)
          : null,
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
      'isPendingSpend': isPendingSpend,
      'spendingTxid': spendingTxid,
      'spendingHeight': spendingHeight,
      'pendingSpendingTxid': pendingSpendingTxid,
      'pendingSpendAt': pendingSpendAt?.toIso8601String(),
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
      rseed != null && diversifier != null && pkD != null && nullifier != null;

  /// Confirmation count at [chainHeight]. The block containing the note counts
  /// as the first confirmation.
  int confirmationsAt(int chainHeight) {
    if (height <= 0 || chainHeight < height) return 0;
    return chainHeight - height + 1;
  }

  bool isConfirmedAt(int chainHeight, int minConfirmations) =>
      confirmationsAt(chainHeight) >= minConfirmations;

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
  final EncryptionFileUtils? encryptionFileUtils;
  final String? password;
  final bool allowUnencryptedStorage;

  List<StoredSaplingNote> _notes = [];
  List<StoredShieldedAddress> _addresses = [];
  int _lastSyncedHeight = 0;
  int _nextTreePosition = 0;
  bool _hasPersistedTreePosition = false;
  Map<int, String> _scannedBlockHashes = {};
  int _nextDiversifierIndex = 1; // 0 is the default address
  bool _isLoaded = false;
  final Lock _lock = Lock(); // Thread safety for concurrent access

  SaplingNoteStorage({
    required this.walletId,
    this.isTestnet = false,
    this.encryptionFileUtils,
    this.password,
    this.allowUnencryptedStorage = false,
  });

  /// Get all notes.
  List<StoredSaplingNote> get notes => List.unmodifiable(_notes);

  /// Get all shielded addresses.
  List<StoredShieldedAddress> get addresses => List.unmodifiable(_addresses);

  /// Get the next diversifier index to use.
  int get nextDiversifierIndex => _nextDiversifierIndex;

  /// Get unspent notes.
  List<StoredSaplingNote> get unspentNotes =>
      _notes.where((n) => !n.isSpent && !n.isPendingSpend).toList();

  /// Get notes that can be restored into the native spender and selected.
  List<StoredSaplingNote> get spendableNotes =>
      unspentNotes.where((n) => n.hasSpendingData).toList();

  List<StoredSaplingNote> confirmedNotesAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.receiveConfirmations,
    bool requireSpendingData = false,
  }) {
    return unspentNotes.where((note) {
      if (requireSpendingData && !note.hasSpendingData) return false;
      return note.isConfirmedAt(chainHeight, minConfirmations);
    }).toList();
  }

  List<StoredSaplingNote> pendingReceivedNotesAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.receiveConfirmations,
  }) {
    return unspentNotes
        .where((note) => !note.isConfirmedAt(chainHeight, minConfirmations))
        .toList();
  }

  List<StoredSaplingNote> spendableNotesAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.spendConfirmations,
  }) {
    return confirmedNotesAt(
      chainHeight: chainHeight,
      minConfirmations: minConfirmations,
      requireSpendingData: true,
    );
  }

  /// Get notes reserved by an outgoing transaction awaiting confirmation.
  List<StoredSaplingNote> get pendingSpentNotes =>
      _notes.where((n) => !n.isSpent && n.isPendingSpend).toList();

  /// Get total unreserved observed balance.
  /// Note: For thread-safe balance in concurrent scenarios, use getBalanceSafe()
  int get balance => unspentNotes.fold<int>(0, (sum, n) => sum + n.value);

  /// Get total balance that has enough local data for spending.
  int get spendableBalance =>
      spendableNotes.fold<int>(0, (sum, n) => sum + n.value);

  int confirmedBalanceAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.receiveConfirmations,
    bool requireSpendingData = true,
  }) {
    return confirmedNotesAt(
      chainHeight: chainHeight,
      minConfirmations: minConfirmations,
      requireSpendingData: requireSpendingData,
    ).fold<int>(0, (sum, note) => sum + note.value);
  }

  int pendingReceivedBalanceAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.receiveConfirmations,
  }) {
    return pendingReceivedNotesAt(
      chainHeight: chainHeight,
      minConfirmations: minConfirmations,
    ).fold<int>(0, (sum, note) => sum + note.value);
  }

  int spendableBalanceAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.spendConfirmations,
  }) {
    return spendableNotesAt(
      chainHeight: chainHeight,
      minConfirmations: minConfirmations,
    ).fold<int>(0, (sum, note) => sum + note.value);
  }

  PivxShieldedSpendEligibilitySummary spendEligibilitySummaryAt({
    required int chainHeight,
    int minConfirmations = PivxShieldedConfirmationPolicy.spendConfirmations,
  }) {
    var pendingConfirmation = 0;
    var pendingSpend = 0;
    var missingSpendingData = 0;
    var spendable = 0;

    final unspent = _notes.where((note) => !note.isSpent).toList();
    for (final note in unspent) {
      if (note.isPendingSpend) {
        pendingSpend++;
        continue;
      }
      if (!note.hasSpendingData) {
        missingSpendingData++;
        continue;
      }
      if (!note.isConfirmedAt(chainHeight, minConfirmations)) {
        pendingConfirmation++;
        continue;
      }
      spendable++;
    }

    return PivxShieldedSpendEligibilitySummary(
      chainHeight: chainHeight,
      minConfirmations: minConfirmations,
      totalUnspent: unspent.length,
      spendable: spendable,
      pendingConfirmation: pendingConfirmation,
      pendingSpend: pendingSpend,
      missingSpendingData: missingSpendingData,
    );
  }

  /// Get locally reserved outgoing value.
  int get pendingOutgoingBalance =>
      pendingSpentNotes.fold<int>(0, (sum, n) => sum + n.value);

  /// Get total balance (thread-safe version for concurrent access).
  Future<int> getBalanceSafe() async {
    return await _lock.synchronized<int>(() {
      return balance;
    });
  }

  /// Get last synced height.
  int get lastSyncedHeight => _lastSyncedHeight;

  /// Get the next canonical global Sapling commitment tree position.
  int get nextTreePosition => _nextTreePosition;

  /// Whether the global tree cursor came from current encrypted storage.
  ///
  /// Older sidecars did not persist a global cursor, so loading
  /// max(owned-note-position)+1 is only a legacy hint. It must not be trusted
  /// for resumed post-activation scanning unless the server returns explicit
  /// global output positions.
  bool get hasPersistedTreePosition => _hasPersistedTreePosition;

  /// Block hashes recorded for scanned Sapling heights.
  Map<int, String> get scannedBlockHashes =>
      Map.unmodifiable(_scannedBlockHashes);

  /// Get the storage file path.
  Future<String> get _storagePath async {
    final dir = await getApplicationDocumentsDirectory();
    final network = isTestnet ? 'testnet' : 'mainnet';
    return '${dir.path}/pivx_sapling_${walletId}_$network.json.enc';
  }

  /// Legacy plaintext path used before PIVX Sapling sidecar encryption.
  Future<String> get _legacyPlaintextStoragePath async {
    final dir = await getApplicationDocumentsDirectory();
    final network = isTestnet ? 'testnet' : 'mainnet';
    return '${dir.path}/pivx_sapling_${walletId}_$network.json';
  }

  /// Load notes from storage.
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      _assertEncryptedStorageAvailable();

      final encryptedPath = await _storagePath;
      final encryptedFile = File(encryptedPath);
      final legacyPath = await _legacyPlaintextStoragePath;
      final legacyFile = File(legacyPath);

      if (await encryptedFile.exists()) {
        final contents = allowUnencryptedStorage
            ? await encryptedFile.readAsString()
            : await encryptionFileUtils!
                .read(path: encryptedPath, password: password!);
        final data = jsonDecode(contents) as Map<String, dynamic>;
        _loadFromJson(data);
      } else if (await legacyFile.exists()) {
        if (allowUnencryptedStorage) {
          final contents = await legacyFile.readAsString();
          final data = jsonDecode(contents) as Map<String, dynamic>;
          _loadFromJson(data);
          _isLoaded = true;
          return;
        }

        final contents = await legacyFile.readAsString();
        final data = jsonDecode(contents) as Map<String, dynamic>;
        _loadFromJson(data);

        await _save();
        await legacyFile.delete();
      }

      _isLoaded = true;
    } catch (e) {
      printV('[PIVX Sapling Storage] Failed to load encrypted sidecar');
      _notes = [];
      _addresses = [];
      _lastSyncedHeight = 0;
      _nextTreePosition = 0;
      _hasPersistedTreePosition = false;
      _scannedBlockHashes = {};
      _nextDiversifierIndex = 1;
      _isLoaded = false;
      rethrow;
    }
  }

  void _assertEncryptedStorageAvailable() {
    if (allowUnencryptedStorage) return;
    if (encryptionFileUtils == null || password == null) {
      throw StateError(
          'PIVX Sapling sidecar storage requires wallet encryption');
    }
  }

  void _loadFromJson(Map<String, dynamic> data) {
    _lastSyncedHeight = data['lastSyncedHeight'] as int? ?? 0;
    _nextDiversifierIndex = data['nextDiversifierIndex'] as int? ?? 1;
    _notes = (data['notes'] as List<dynamic>?)
            ?.map((e) => StoredSaplingNote.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    _addresses = (data['addresses'] as List<dynamic>?)
            ?.map((e) =>
                StoredShieldedAddress.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final fallbackTreePosition = _notes.isNotEmpty
        ? _notes.map((n) => n.treePosition).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    final persistedTreePosition = data['nextTreePosition'] as int?;
    _nextTreePosition = persistedTreePosition ?? fallbackTreePosition;
    _hasPersistedTreePosition = persistedTreePosition != null;
    _scannedBlockHashes = _decodeScannedBlockHashes(data['scannedBlockHashes']);
  }

  Map<int, String> _decodeScannedBlockHashes(Object? raw) {
    final hashes = <int, String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final height = entry.key is int
            ? entry.key as int
            : int.tryParse(entry.key.toString());
        final hash = entry.value?.toString();
        if (height != null && hash != null && hash.isNotEmpty) {
          hashes[height] = hash;
        }
      }
    }
    return hashes;
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
      _assertEncryptedStorageAvailable();

      final path = await _storagePath;
      final file = File(path);

      final data = <String, dynamic>{
        'lastSyncedHeight': _lastSyncedHeight,
        'nextDiversifierIndex': _nextDiversifierIndex,
        'notes': _notes.map((n) => n.toJson()).toList(),
        'addresses': _addresses.map((a) => a.toJson()).toList(),
        'scannedBlockHashes': _scannedBlockHashes
            .map((height, hash) => MapEntry('$height', hash)),
      };
      if (_hasPersistedTreePosition) {
        data['nextTreePosition'] = _nextTreePosition;
      }

      final encoded = jsonEncode(data);
      if (allowUnencryptedStorage) {
        await file.writeAsString(encoded);
      } else {
        await encryptionFileUtils!
            .write(path: path, password: password!, data: encoded);
      }
    } catch (e) {
      printV('[PIVX Sapling Storage] Failed to save encrypted sidecar');
      rethrow;
    }
  }

  /// Clear all notes and reset sync state.
  /// Used for rescanning the blockchain.
  Future<void> clear() async {
    _notes = [];
    _lastSyncedHeight = 0;
    _nextTreePosition = 0;
    _hasPersistedTreePosition = false;
    _scannedBlockHashes = {};
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
        final previous = _notes[existing];
        note.isSpent = note.isSpent || previous.isSpent;
        note.isPendingSpend = note.isPendingSpend || previous.isPendingSpend;
        note.spendingTxid ??= previous.spendingTxid;
        note.pendingSpendingTxid ??= previous.pendingSpendingTxid;
        note.pendingSpendAt ??= previous.pendingSpendAt;
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
      note.isPendingSpend = false;
      note.spendingTxid = spendingTxid;
      note.spendingHeight = null;
      note.pendingSpendingTxid = null;
      note.pendingSpendAt = null;
      await _save();
    });
  }

  /// Mark notes spent by nullifier (thread-safe).
  Future<bool> markSpentByNullifier(
    String nullifier,
    String spendingTxid, {
    int? spendingHeight,
  }) async {
    return await _lock.synchronized(() async {
      final note = _notes.cast<StoredSaplingNote?>().firstWhere(
            (n) => n?.nullifier == nullifier,
            orElse: () => null,
          );

      if (note != null) {
        note.isSpent = true;
        note.isPendingSpend = false;
        note.spendingTxid = spendingTxid;
        note.spendingHeight = spendingHeight;
        note.pendingSpendingTxid = null;
        note.pendingSpendAt = null;
        await _save();
        return true;
      }
      return false;
    });
  }

  /// Reserve notes by nullifier after a successful local broadcast.
  ///
  /// Reserved notes are excluded from spendable balance immediately, before the
  /// spending nullifier appears in a later scanned block.
  Future<int> markPendingSpentByNullifiers(
    List<String> nullifiers,
    String pendingTxid,
  ) async {
    if (nullifiers.isEmpty) return 0;

    return await _lock.synchronized(() async {
      final pendingSet = nullifiers.toSet();
      var reservedValue = 0;

      for (final note in _notes) {
        if (note.nullifier == null || !pendingSet.contains(note.nullifier)) {
          continue;
        }
        if (note.isSpent) continue;

        note.isPendingSpend = true;
        note.pendingSpendingTxid = pendingTxid;
        note.pendingSpendAt = DateTime.now();
        reservedValue += note.value;
      }

      if (reservedValue > 0) {
        await _save();
      }

      return reservedValue;
    });
  }

  /// Clear local pending-spend reservations.
  ///
  /// This is intended for debug/test recovery when a locally constructed
  /// transaction was not accepted by the node but older code already reserved
  /// its nullifiers.
  Future<int> clearPendingSpentNotes() async {
    return await _lock.synchronized(() async {
      var clearedValue = 0;

      for (final note in _notes) {
        if (!note.isPendingSpend || note.isSpent) continue;

        note.isPendingSpend = false;
        note.pendingSpendingTxid = null;
        note.pendingSpendAt = null;
        clearedValue += note.value;
      }

      if (clearedValue > 0) {
        await _save();
      }

      return clearedValue;
    });
  }

  /// Update the last synced height (thread-safe).
  Future<void> setLastSyncedHeight(int height) async {
    await _lock.synchronized(() async {
      _lastSyncedHeight = height;
      await _save();
    });
  }

  /// Update the next canonical Sapling tree position after processing outputs.
  Future<void> setNextTreePosition(int position) async {
    await _lock.synchronized(() async {
      if (position > _nextTreePosition) {
        _nextTreePosition = position;
        _hasPersistedTreePosition = true;
        await _save();
      }
    });
  }

  /// Atomically update sync height and global tree cursor.
  Future<void> completeSyncRange({
    required int lastSyncedHeight,
    required int nextTreePosition,
    required bool treePositionIsTrusted,
    Map<int, String> blockHashes = const {},
  }) async {
    await _lock.synchronized(() async {
      _lastSyncedHeight = lastSyncedHeight;
      if (nextTreePosition > _nextTreePosition) {
        _nextTreePosition = nextTreePosition;
      }
      if (treePositionIsTrusted) {
        _hasPersistedTreePosition = true;
      }
      _scannedBlockHashes.addAll(blockHashes);
      _scannedBlockHashes.removeWhere((height, _) => height > lastSyncedHeight);
      await _save();
    });
  }

  /// Rewind shielded state to [height] after a detected reorg.
  ///
  /// Notes created after the rewind point are removed. Spend markers observed
  /// after that point are cleared so the rescan can re-apply the canonical
  /// branch. The global tree cursor is intentionally marked untrusted because
  /// the next sync must rely on explicit server positions after a rollback.
  Future<void> rewindToHeight(int height) async {
    await _lock.synchronized(() async {
      _notes.removeWhere((note) => note.height > height);
      for (final note in _notes) {
        if (note.spendingHeight != null && note.spendingHeight! > height) {
          note.isSpent = false;
          note.spendingTxid = null;
          note.spendingHeight = null;
        }
      }
      _lastSyncedHeight = height;
      _nextTreePosition = 0;
      _hasPersistedTreePosition = false;
      _scannedBlockHashes.removeWhere((blockHeight, _) => blockHeight > height);
      await _save();
    });
  }

  /// Get notes in a height range.
  List<StoredSaplingNote> getNotesInRange(int startHeight, int endHeight) {
    return _notes
        .where((n) => n.height >= startHeight && n.height <= endHeight)
        .toList();
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

  /// Advance the next shielded receive index without moving it backwards.
  Future<void> advanceNextDiversifierIndexAtLeast(int nextIndex) async {
    if (nextIndex <= _nextDiversifierIndex) {
      return;
    }

    _nextDiversifierIndex = nextIndex;
    await save();
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
