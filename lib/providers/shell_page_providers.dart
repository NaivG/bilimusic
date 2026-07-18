import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

class ShellPageState {
  final List<ShellPage> pageStack;
  final Map<String, dynamic> pageArgs;

  const ShellPageState({
    this.pageStack = const [ShellPage.home],
    this.pageArgs = const {},
  });

  ShellPage get currentPage => pageStack.last;
  bool get canPop => pageStack.length > 1;

  int get selectedTabIndex {
    switch (pageStack.last) {
      case ShellPage.home:
        return 0;
      case ShellPage.search:
      case ShellPage.searchResults:
        return 1;
      case ShellPage.profile:
        return 2;
      case ShellPage.settings:
        return 3;
      default:
        return 0;
    }
  }

  ShellPageState copyWith({
    List<ShellPage>? pageStack,
    Map<String, dynamic>? pageArgs,
  }) {
    return ShellPageState(
      pageStack: pageStack ?? this.pageStack,
      pageArgs: pageArgs ?? this.pageArgs,
    );
  }
}

class ShellPageManagerNotifier extends Notifier<ShellPageState> {
  @override
  ShellPageState build() => const ShellPageState();

  void push(ShellPage page, {Map<String, dynamic>? args}) {
    final newStack = [...state.pageStack, page];
    final newArgs = Map<String, dynamic>.from(state.pageArgs);
    if (args != null) newArgs.addAll(args);
    state = ShellPageState(pageStack: newStack, pageArgs: newArgs);
  }

  void pop() {
    if (state.pageStack.length > 1) {
      final newStack = List<ShellPage>.from(state.pageStack)
        ..removeLast();
      state = ShellPageState(pageStack: newStack, pageArgs: state.pageArgs);
    }
  }

  void popUntil(ShellPage page) {
    final newStack = List<ShellPage>.from(state.pageStack);
    while (newStack.length > 1 && newStack.last != page) {
      newStack.removeLast();
    }
    state = ShellPageState(pageStack: newStack, pageArgs: state.pageArgs);
  }

  void replace(ShellPage page, {Map<String, dynamic>? args}) {
    final newStack = List<ShellPage>.from(state.pageStack);
    if (newStack.isNotEmpty) newStack.removeLast();
    newStack.add(page);
    final newArgs = Map<String, dynamic>.from(state.pageArgs);
    if (args != null) newArgs.addAll(args);
    state = ShellPageState(pageStack: newStack, pageArgs: newArgs);
  }

  void goToTab(int index) {
    final page = switch (index) {
      0 => ShellPage.home,
      1 => ShellPage.search,
      2 => ShellPage.profile,
      3 => ShellPage.settings,
      _ => ShellPage.home,
    };
    replace(page);
  }

  void goToPlaylist({
    required String playlistId,
    List<Music>? songs,
    String? playlistName,
  }) {
    push(
      ShellPage.playlist,
      args: {
        'playlistId': playlistId,
        'songs': songs,
        'playlistName': playlistName,
      },
    );
  }

  void goToDetail() {
    push(ShellPage.detail);
  }

  T? getArgs<T>(String key) => state.pageArgs[key] as T?;

  void clearArgs() {
    state = ShellPageState(pageStack: state.pageStack, pageArgs: {});
  }
}

final shellPageProvider =
    NotifierProvider<ShellPageManagerNotifier, ShellPageState>(
  ShellPageManagerNotifier.new,
);
