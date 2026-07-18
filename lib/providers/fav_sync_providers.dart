import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart' show ImportResult;
import 'package:bilimusic/models/bili_fav_folder.dart';
import 'package:bilimusic/models/fav_import_record.dart';

final _favSyncManagerProvider = favSyncManagerProvider;

@immutable
class FavSyncState {
  final List<FavImportRecord> records;
  final bool isLoading;

  const FavSyncState({this.records = const [], this.isLoading = false});

  FavSyncState copyWith({List<FavImportRecord>? records, bool? isLoading}) {
    return FavSyncState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FavSyncStateNotifier extends Notifier<FavSyncState> {
  @override
  FavSyncState build() {
    final fm = ref.read(_favSyncManagerProvider);
    fm.addListener(_onFavSyncChanged);
    ref.onDispose(() => fm.removeListener(_onFavSyncChanged));
    return _readFromManager();
  }

  FavSyncState _readFromManager() {
    final fm = ref.read(_favSyncManagerProvider);
    return FavSyncState(records: fm.records, isLoading: fm.isLoading);
  }

  void _onFavSyncChanged() {
    state = _readFromManager();
  }

  Future<Map<String, List<BiliFavFolder>>> fetchAllFolders(int upMid) async {
    return ref.read(_favSyncManagerProvider).fetchAllFolders(upMid);
  }

  Future<ImportResult> importFolderAsNewPlaylist(
    BiliFavFolder folder, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    return ref.read(_favSyncManagerProvider).importFolderAsNewPlaylist(
      folder,
      onProgress: onProgress,
    );
  }

  Future<ImportResult> appendFolderToPlaylist(
    BiliFavFolder folder,
    String playlistId, {
    void Function(int processed, int total, int failed)? onProgress,
  }) async {
    return ref.read(_favSyncManagerProvider).appendFolderToPlaylist(
      folder,
      playlistId,
      onProgress: onProgress,
    );
  }

  Future<void> removeImportRecord(int folderMediaId) async {
    await ref.read(_favSyncManagerProvider).removeImportRecord(folderMediaId);
  }
}

final favSyncStateProvider =
    NotifierProvider<FavSyncStateNotifier, FavSyncState>(
      FavSyncStateNotifier.new,
    );