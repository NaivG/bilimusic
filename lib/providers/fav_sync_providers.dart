import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/bili_fav_folder.dart';
import 'package:bilimusic/models/fav_import_record.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';

@immutable
class FavSyncState {
  final List<FavImportRecord> records;
  final bool isLoading;

  const FavSyncState({
    this.records = const [],
    this.isLoading = false,
  });

  FavSyncState copyWith({
    List<FavImportRecord>? records,
    bool? isLoading,
  }) {
    return FavSyncState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FavSyncStateNotifier extends Notifier<FavSyncState> {
  @override
  FavSyncState build() {
    final fm = sl.favSyncManager;
    fm.addListener(_onFavSyncChanged);
    ref.onDispose(() => fm.removeListener(_onFavSyncChanged));
    return _readFromManager();
  }

  FavSyncState _readFromManager() {
    final fm = sl.favSyncManager;
    return FavSyncState(
      records: fm.records,
      isLoading: fm.isLoading,
    );
  }

  void _onFavSyncChanged() {
    state = _readFromManager();
  }

  Future<Map<String, List<BiliFavFolder>>> fetchAllFolders(int upMid) async {
    return sl.favSyncManager.fetchAllFolders(upMid);
  }

  Future<ImportResult> importFolderAsNewPlaylist(
    BiliFavFolder folder, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    return sl.favSyncManager.importFolderAsNewPlaylist(
      folder,
      onProgress: onProgress,
    );
  }

  Future<ImportResult> appendFolderToPlaylist(
    BiliFavFolder folder,
    String playlistId, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    return sl.favSyncManager.appendFolderToPlaylist(
      folder,
      playlistId,
      onProgress: onProgress,
    );
  }

  Future<void> removeImportRecord(int folderMediaId) async {
    await sl.favSyncManager.removeImportRecord(folderMediaId);
  }
}

final favSyncStateProvider =
    NotifierProvider<FavSyncStateNotifier, FavSyncState>(
  FavSyncStateNotifier.new,
);
