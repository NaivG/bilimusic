import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/user_info.dart';

final _userManagerProvider = userManagerProvider;

@immutable
class UserState {
  final UserInfo? userInfo;
  final bool isLoggedIn;
  final bool isLoading;

  const UserState({
    this.userInfo,
    this.isLoggedIn = false,
    this.isLoading = false,
  });

  UserState copyWith({UserInfo? userInfo, bool? isLoggedIn, bool? isLoading}) {
    return UserState(
      userInfo: userInfo ?? this.userInfo,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class UserStateNotifier extends Notifier<UserState> {
  @override
  UserState build() {
    final um = ref.read(_userManagerProvider);
    um.addListener(_onUserManagerChanged);
    ref.onDispose(() => um.removeListener(_onUserManagerChanged));
    return _readFromManager();
  }

  UserState _readFromManager() {
    final um = ref.read(_userManagerProvider);
    return UserState(
      userInfo: um.userInfo,
      isLoggedIn: um.isLoggedIn,
      isLoading: !um.isFresh && um.isLoggedIn,
    );
  }

  void _onUserManagerChanged() {
    state = _readFromManager();
  }

  bool checkCookieLogin() {
    final result = ref.read(_userManagerProvider).checkCookieLogin();
    state = _readFromManager();
    return result;
  }

  Future<UserInfo?> getUserInfo({bool forceRefresh = false}) async {
    final result = await ref
        .read(_userManagerProvider)
        .getUserInfo(forceRefresh: forceRefresh);
    state = _readFromManager();
    return result;
  }

  Future<void> clear() async {
    await ref.read(_userManagerProvider).clear();
    state = _readFromManager();
  }
}

final userStateProvider = NotifierProvider<UserStateNotifier, UserState>(
  UserStateNotifier.new,
);