import 'package:dart_tui/dart_tui.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/search_result.dart';

import 'mpv_player.dart';
import 'tui_api.dart';

// ── 消息 ──────────────────────────────────────────────────────────────────

final class SearchDoneMsg extends Msg {
  SearchDoneMsg({
    required this.results,
    required this.page,
    required this.numPages,
    required this.keyword,
    required this.append,
    this.error,
  });

  final List<SearchResult> results;
  final int page;
  final int numPages;
  final String keyword;
  final bool append;
  final String? error;
}

final class RecsDoneMsg extends Msg {
  RecsDoneMsg({required this.recs, this.error});
  final List<SearchResult> recs;
  final String? error;
}

final class ResolvedMsg extends Msg {
  ResolvedMsg(this.music, {required this.page, required this.index});
  final Music music;
  final TuiPage page;
  final int index;
}

final class ResolveFailMsg extends Msg {
  ResolveFailMsg(this.message);
  final String message;
}

// ── 视觉 ──────────────────────────────────────────────────────────────────

/// Catppuccin Mocha,与 dart_tui bubbles 的默认配色一致。
abstract final class Palette {
  static const accent = RgbColor(203, 166, 247); // 焦点边框 / 快捷键
  static const blue = RgbColor(137, 180, 250); // 播放面板
  static const green = RgbColor(166, 227, 161); // 播放中标记
  static const red = RgbColor(243, 139, 168); // 错误
  static const yellow = RgbColor(249, 226, 175); // 已暂停
  static const surface = RgbColor(88, 91, 112); // 非焦点边框
  static const overlay = RgbColor(127, 132, 156); // 状态 / 说明文字
  static const text = RgbColor(205, 214, 244); // 正文
}

/// 页面:主页(搜索框 + 官方推荐) / 搜索结果页(搜索框 + 结果列表)。
enum TuiPage { home, search }

/// 面板焦点。
enum Pane { search, list }

// ── 根模型 ────────────────────────────────────────────────────────────────

/// bilimusic TUI 根模型。
///
/// 两个页面共用一个搜索框与一个播放队列,布局自上而下:
/// 标题行 → 搜索面板 → 状态行 → 内容面板(首页为官方推荐列表,搜索页为结果列表,
/// 兼播放队列) → 播放面板(有曲目后出现) → 帮助行。
///
/// 键位路由:搜索框聚焦时等任意页都只进输入框;
/// 列表聚焦时处理播放控制快捷键,其余透传 [ListModel](含 / 过滤)。
/// 搜索(enter)切到结果页;结果页搜索框/列表按 esc 回主页。
final class AppModel extends Model {
  AppModel({required this.api});

  final TuiApi api;
  final MpvPlayer mpv = MpvPlayer();

  TextInputModel _input = TextInputModel(
    placeholder: '关键词 / BV / AV 号,回车搜索',
    focused: true,
  );
  ListModel _homeList = ListModel(items: const [], showStatusBar: false);
  ListModel _searchList = ListModel(items: const [], showStatusBar: false);
  SpinnerModel _spinner = SpinnerModel();

  TuiPage _page = TuiPage.home;
  Pane _pane = Pane.search;
  int _w = 80;
  int _h = 24;
  int _ticks = 0; // 每 3 帧(≈360ms)轮询一次 mpv

  // 主页:官方推荐(音乐分区 rcmd)。类型统一为 SearchResult,
  // 与搜索结果共用一套列表渲染与取流路径。
  List<SearchResult> _recs = const [];
  List<ListItem> _homeItems = const [];
  bool _recsLoading = false;

  // 搜索页
  List<SearchResult> _results = const [];
  List<ListItem> _searchItems = const [];
  String _keyword = '';
  int _pageNo = 1;
  int _numPages = 1;
  bool _searching = false;

  bool _resolving = false;
  int _playingIdx = -1;
  TuiPage _queuePage = TuiPage.home; // 当前播放队列所属页面

  Music? _nowPlaying;
  MpvState _player = const MpvState();
  bool _endedHandled = false;
  String _status = '就绪';
  bool _isError = false;

  // ── 生命周期 ────────────────────────────────────────────────────────────

  @override
  Cmd? init() {
    _status = api.hasLoginCookies
        ? '就绪 · 已从桌面 App 导入登录态'
        : '就绪 · 未登录(部分内容不可搜)';
    try {
      mpv.load();
    } catch (e) {
      _status = 'mpv 加载失败(仍可搜索):$e';
      _isError = true;
    }
    _recsLoading = true;
    return _recsCmd();
  }

  // ── update ──────────────────────────────────────────────────────────────

  @override
  (Model, Cmd?) update(Msg msg) {
    switch (msg) {
      case WindowSizeMsg(:final width, :final height):
        _w = width;
        _h = height;
        _homeList = _reheight(_homeList);
        _searchList = _reheight(_searchList);
        return (this, null);
      case TickMsg():
        return _onTick(msg);
      case SearchDoneMsg():
        return _onSearchDone(msg);
      case RecsDoneMsg():
        return _onRecsDone(msg);
      case ResolvedMsg():
        return _onResolved(msg);
      case ResolveFailMsg():
        _resolving = false;
        _status = '取流失败:${msg.message}';
        _isError = true;
        return (this, null);
      case MouseClickMsg():
        final (next, _) = _activeList.update(msg);
        _writeBackList(next as ListModel);
        return (this, null);
      case KeyMsg():
        return _onKey(msg);
      case PasteMsg(:final content):
        return _onPaste(content);
      default:
        return (this, null);
    }
  }

  (Model, Cmd?) _onTick(TickMsg msg) {
    _ticks++;
    if (_searching || _resolving || _recsLoading) {
      _spinner = _spinner.update(msg).$1 as SpinnerModel;
    }
    if (_ticks % 3 != 0 || _nowPlaying == null || !mpv.isReady) {
      return (this, null);
    }
    _player = mpv.pollState();
    if (_player.ended && !_endedHandled) {
      _endedHandled = true;
      final next = _playingIdx + 1;
      final len = _queueLen(_queuePage);
      if (_playingIdx >= 0 && next < len) {
        return _playAt(next, page: _queuePage, hint: '自动播放下一首');
      }
      _status = '队列播放结束';
    }
    return (this, null);
  }

  (Model, Cmd?) _onRecsDone(RecsDoneMsg msg) {
    _recsLoading = false;
    if (msg.error != null) {
      if (!_searching && !_resolving) {
        _status = '官方推荐加载失败:${msg.error} · 按 r 重试';
        _isError = true;
      }
      return (this, null);
    }
    _recs = msg.recs;
    _rebuildHomeItems();
    if (!_searching && !_resolving && _page == TuiPage.home) {
      _status = '官方推荐 · ${_recs.length} 首 · tab 浏览推荐';
      _isError = false;
    }
    return (this, null);
  }

  (Model, Cmd?) _onSearchDone(SearchDoneMsg msg) {
    _searching = false;
    if (msg.error != null) {
      _status = '搜索失败:${msg.error}';
      _isError = true;
      return (this, null);
    }
    if (msg.append) {
      _results = [..._results, ...msg.results];
      _pageNo = msg.page;
    } else {
      _results = msg.results;
      _pageNo = msg.page;
      _numPages = msg.numPages;
      _keyword = msg.keyword;
      // 新搜索结果成为当前队列:清掉旧播放标记
      _playingIdx = -1;
      _queuePage = TuiPage.search;
      _page = TuiPage.search;
      _focusList();
    }
    _rebuildSearchItems();
    if (!msg.append) {
      // 全新结果:重置过滤与游标
      _searchList = ListModel(
        items: _searchItems,
        height: _listRows(),
        showStatusBar: false,
        viewOffsetY: _listOffsetY,
      );
    }
    _status = '找到 ${_results.length} 条 · enter 播放 · n 下一页';
    _isError = false;
    return (this, null);
  }

  (Model, Cmd?) _onResolved(ResolvedMsg msg) {
    _resolving = false;
    _queuePage = msg.page;
    _playingIdx = msg.index;
    _nowPlaying = msg.music;
    _player = const MpvState();
    _endedHandled = false;
    try {
      mpv.play(msg.music.audioUrl);
      _status = '正在播放';
      _isError = false;
    } catch (e) {
      _status = '播放失败:$e';
      _isError = true;
    }
    _rebuildHomeItems();
    _rebuildSearchItems();
    return (this, null);
  }

  (Model, Cmd?) _onKey(KeyMsg msg) {
    final key = msg.key;
    if (key == 'ctrl+c') return (this, () => quit());

    if (_pane == Pane.search) {
      switch (key) {
        case 'enter':
          return _submitSearch();
        case 'tab':
          _focusList();
          return (this, null);
        case 'esc':
          if (_page == TuiPage.search) {
            // 结果页退回主页(输入内容保留,为下次搜索的默认词)
            _page = TuiPage.home;
            _focusSearch();
          } else {
            _focusList();
          }
          return (this, null);
      }
      final (next, _) = _input.update(msg);
      _input = next as TextInputModel;
      return (this, null);
    }

    // 列表焦点:过滤模式下按键全部交给列表,避免误触发播放控制
    final list = _activeList;
    if (list.filterMode) {
      final (next, _) = list.update(msg);
      _writeBackList(next as ListModel);
      return (this, null);
    }
    if (key == 'esc' && list.filter.isEmpty) {
      _focusSearch();
      return (this, null);
    }
    switch (key) {
      case 'tab':
        _focusSearch();
        return (this, null);
      case 'q':
        return (this, () => quit());
      case 'enter':
        final idx = _queueIndexFromSelection();
        return idx == null ? (this, null) : _playAt(idx, page: _page);
      case 'space' || 'p':
        if (_nowPlaying != null && mpv.isReady && !_player.ended) {
          mpv.pause(!_player.paused);
          _player = _player.copyWith(paused: !_player.paused);
        }
        return (this, null);
      case 'left':
        if (_nowPlaying != null && mpv.isReady) mpv.seekRelative(-10);
        return (this, null);
      case 'right':
        if (_nowPlaying != null && mpv.isReady) mpv.seekRelative(10);
        return (this, null);
      case '+' || '=':
        if (_nowPlaying != null && mpv.isReady) mpv.bumpVolume(5);
        return (this, null);
      case '-':
        if (_nowPlaying != null && mpv.isReady) mpv.bumpVolume(-5);
        return (this, null);
      case ',':
        return _playingIdx > 0
            ? _playAt(_playingIdx - 1, page: _queuePage)
            : (this, null);
      case '.':
        final next = _playingIdx + 1;
        return _playingIdx >= 0 && next < _queueLen(_queuePage)
            ? _playAt(next, page: _queuePage)
            : (this, null);
      case 'n':
        if (_page == TuiPage.search &&
            _pageNo < _numPages &&
            !_searching &&
            _keyword.isNotEmpty) {
          _searching = true;
          _status = '加载第 ${_pageNo + 1} 页…';
          _isError = false;
          return (this, _searchCmd(_keyword, _pageNo + 1, append: true));
        }
        return (this, null);
      case 'r':
        if (_page == TuiPage.home) return _reloadRecs();
        return (this, null);
    }
    final (next, cmd) = list.update(msg);
    _writeBackList(next as ListModel);
    return (this, cmd);
  }

  // ── 动作 ────────────────────────────────────────────────────────────────

  (Model, Cmd?) _submitSearch() {
    final q = _input.value.trim();
    if (q.isEmpty || _searching) return (this, null);
    _searching = true;
    _status = '搜索「$q」…';
    _isError = false;
    return (this, _searchCmd(q, 1, append: false));
  }

  (Model, Cmd?) _reloadRecs() {
    if (_recsLoading) return (this, null);
    _recsLoading = true;
    _status = '加载官方推荐…';
    _isError = false;
    return (this, _recsCmd());
  }

  /// 粘贴:框架默认开启 bracketed paste(?2004h),解码器把
  /// ESC[200~…ESC[201~ 包裹的内容发成 [PasteMsg],但 TextInputModel
  /// 只认 KeyMsg —— 这里展平后合成一次 rune 键入(图素级插入,
  /// 由输入框自己处理光标与 charLimit)。
  (Model, Cmd?) _onPaste(String raw) {
    // 换行折成空格并去掉首尾空段:尾部换行是复制时最常见的杂质,
    // 不丢掉会立刻触发一次回车搜索
    final text = raw
        .split(RegExp(r'\r\n|\r|\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' ');
    if (text.isEmpty) return (this, null);
    _focusSearch();
    final (next, _) = _input.update(
      KeyPressMsg(TeaKey(code: KeyCode.rune, text: text)),
    );
    _input = next as TextInputModel;
    return (this, null);
  }

  (Model, Cmd?) _playAt(
    int index, {
    required TuiPage page,
    String hint = '',
  }) {
    final queue = page == TuiPage.home ? _recs : _results;
    if (index < 0 || index >= queue.length) return (this, null);
    final r = queue[index];
    _resolving = true;
    _isError = false;
    _status = hint.isEmpty ? '解析「${r.title}」…' : '$hint:${r.title}';
    if (page == TuiPage.home) {
      _homeList = _homeList.select(index);
    } else {
      _searchList = _searchList.select(index);
    }
    return (this, _resolveCmd(r, index: index, page: page));
  }

  Cmd _searchCmd(String query, int page, {required bool append}) {
    return () async {
      try {
        final (results, cur, numPages) = await api.search(query, page: page);
        return SearchDoneMsg(
          results: results,
          page: cur,
          numPages: numPages,
          keyword: query,
          append: append,
        );
      } catch (e) {
        return SearchDoneMsg(
          results: const [],
          page: page,
          numPages: 1,
          keyword: query,
          append: false,
          error: '$e',
        );
      }
    };
  }

  Cmd _recsCmd() {
    return () async {
      try {
        return RecsDoneMsg(recs: await api.recommendations());
      } catch (e) {
        return RecsDoneMsg(recs: const [], error: '$e');
      }
    };
  }

  Cmd _resolveCmd(
    SearchResult result, {
    required int index,
    required TuiPage page,
  }) {
    return () async {
      try {
        final music = await api.resolveAudio(result);
        if (music.audioUrl.isEmpty) return ResolveFailMsg('无音频流');
        return ResolvedMsg(music, page: page, index: index);
      } catch (e) {
        return ResolveFailMsg('$e');
      }
    };
  }

  // ── 状态辅助 ────────────────────────────────────────────────────────────

  ListModel get _activeList =>
      _page == TuiPage.home ? _homeList : _searchList;

  List<ListItem> get _activeItems =>
      _page == TuiPage.home ? _homeItems : _searchItems;

  int _queueLen(TuiPage page) =>
      page == TuiPage.home ? _recs.length : _results.length;

  void _writeBackList(ListModel list) {
    if (_page == TuiPage.home) {
      _homeList = list;
    } else {
      _searchList = list;
    }
  }

  void _rebuildHomeItems() {
    final maxW = (_w - 12).clamp(16, 200);
    _homeItems = [
      for (var i = 0; i < _recs.length; i++)
        _toItem(
          _recs[i],
          i,
          maxW,
          playing: _queuePage == TuiPage.home && _playingIdx == i,
        ),
    ];
    _homeList = _homeList.withItems(_homeItems);
  }

  void _rebuildSearchItems() {
    final maxW = (_w - 12).clamp(16, 200);
    _searchItems = [
      for (var i = 0; i < _results.length; i++)
        _toItem(
          _results[i],
          i,
          maxW,
          playing: _queuePage == TuiPage.search && _playingIdx == i,
        ),
    ];
    _searchList = _searchList.withItems(_searchItems);
  }

  ListItem _toItem(SearchResult r, int i, int maxW, {required bool playing}) {
    final mark = playing ? '▶' : ' ';
    final num = '${i + 1}'.padLeft(2);
    return ListItem(
      title: truncate('$mark $num. ${r.title}', maxW),
      description: '   ${r.subtitle}',
      filterValue: '${r.title} ${r.subtitle}',
    );
  }

  /// 选中的列表项 → 当前页队列下标。靠 ListItem 实例同一性映射:
  /// 过滤态下游标是过滤后下标,不能直接当队列下标用。
  int? _queueIndexFromSelection() {
    final sel = _activeList.selected;
    if (sel == null) return null;
    final idx = _activeItems.indexOf(sel);
    return idx < 0 ? null : idx;
  }

  void _focusSearch() {
    _pane = Pane.search;
    _input = _input.copyWith(focused: true);
  }

  void _focusList() {
    _pane = Pane.list;
    _input = _input.copyWith(focused: false);
  }

  /// 内容列表可视条目数:固定区(标题 1 + 搜索 3 + 状态 1 + 列表边框 2 + 帮助 1
  /// + 播放面板 4)= 12 行,再加 2 行余量(少显示一条),其余给列表,每条占 2 行。
  int _listRows() => ((_h - 14) ~/ 2).clamp(2, 40);

  /// 列表内容的屏幕起始行(供列表点击选中换算):
  /// 标题 1 行 + 搜索面板 3 行 + 状态行 1 行 + 列表上边框 1 行。
  int get _listOffsetY => 6;

  ListModel _reheight(ListModel l) => ListModel(
        items: l.items,
        cursor: l.selectedIndex,
        height: _listRows(),
        filter: l.filter,
        filterMode: l.filterMode,
        styles: l.styles,
        showStatusBar: false,
        viewOffsetY: _listOffsetY,
      );

  // ── view ────────────────────────────────────────────────────────────────

  @override
  View view() {
    final b = StringBuffer();
    b.writeln(_titleLine());
    b.writeln(_searchPane());
    b.writeln(_statusLine());
    b.writeln(_page == TuiPage.home ? _homePane() : _resultPane());
    final playing = _nowPlaying;
    if (playing != null) b.writeln(_playerPane(playing));
    b.write(_helpLine());
    return newView(b.toString());
  }

  /// 标题行:应用名(粗体 Mauve)。
  String _titleLine() {
    return ' ${Style(foregroundRgb: Palette.accent, isBold: true).render('♪ bilimusic TUI')}';
  }

  String _frame(String title, String content, {required RgbColor border}) {
    return Style(
      border: Border.rounded,
      borderForeground: border,
      borderTitle: ' $title ',
      width: _w - 2,
    ).render(content);
  }

  String _searchPane() {
    final focused = _pane == Pane.search;
    // 空输入时也显示占位提示(聚焦态光标由终端渲染,提示文案更重要)
    final content = _input.value.isEmpty
        ? Style(foregroundRgb: Palette.surface).render(_input.placeholder)
        : _input.view().content;
    return _frame(
      '搜索 · $_pageTag',
      content,
      border: focused ? Palette.accent : Palette.surface,
    );
  }

  String _statusLine() {
    final busy = _searching || _resolving || _recsLoading;
    final color = _isError
        ? Palette.red
        : busy
            ? Palette.text
            : Palette.overlay;
    final body =
        ' ${Style(foregroundRgb: color).render(truncate(_status, _w - 5))}';
    // spinner 自带样式,与正文并列拼接,避免 ANSI 状态互相覆盖
    return busy ? ' ${_spinner.view().content}$body' : body;
  }

  /// 主页:官方推荐(音乐分区)列表。
  String _homePane() {
    final focused = _pane == Pane.list;
    final title = _recs.isEmpty
        ? '♪ 官方推荐 · 音乐'
        : '♪ 官方推荐 · 音乐 (${_recs.length} 首)';
    final String body;
    if (_recsLoading && _recs.isEmpty) {
      body = '  ${Style(foregroundRgb: Palette.overlay).render('正在加载官方推荐…')}';
    } else if (_recs.isEmpty) {
      body = '  ${Style(foregroundRgb: Palette.surface).render('暂无推荐 · 按 r 刷新')}';
    } else {
      body = _homeList.view().content;
    }
    return _frame(
      truncate(title, _w - 10),
      body,
      border: focused ? Palette.accent : Palette.surface,
    );
  }

  /// 当前页面名,用于搜索面板标题。
  String get _pageTag => _page == TuiPage.home ? '主页' : '结果页';

  String _resultPane() {
    final focused = _pane == Pane.list;
    final title = _keyword.isEmpty
        ? '结果'
        : '结果 · $_keyword (第 $_pageNo/$_numPages 页 · ${_results.length} 条)';
    return _frame(
      truncate(title, _w - 10),
      _searchList.view().content,
      border: focused ? Palette.accent : Palette.surface,
    );
  }

  String _playerPane(Music m) {
    final paused = _player.paused && !_player.ended;
    final (icon, iconColor) = _player.ended
        ? ('⏹', Palette.surface)
        : paused
            ? ('⏸', Palette.yellow)
            : ('▶', Palette.green);
    final artist = m.artist.isEmpty ? '' : ' — ${m.artist}';
    final head =
        '${Style(foregroundRgb: iconColor).render(icon)} ${m.title}$artist';

    final cur = _fmt(_player.position);
    final dur = _fmt(_player.duration);
    final vol = 'vol ${_player.volume.round()}%';
    // 行结构: 2缩进 + cur + 2 + [barW + 1空格 + 4百分比] + 2 + dur + 2 + vol,
    // 加左右边框共 _w 列 → barW = _w - 15 - 三段文本宽
    final barW = (_w - 15 - cur.length - dur.length - vol.length)
        .clamp(8, 64);
    final frac = _player.duration > 0
        ? (_player.position / _player.duration).clamp(0.0, 1.0)
        : 0.0;
    final bar = ProgressModel(fraction: frac, width: barW).view().content;
    final line2 = '  $cur  $bar  $dur  $vol';

    final body = Style(
      width: _w - 2,
      foregroundRgb: paused ? Palette.overlay : Palette.text,
    ).render('$head\n$line2');
    return _frame(
      '♪ 正在播放',
      body,
      border: paused ? Palette.surface : Palette.blue,
    );
  }

  String _helpLine() {
    final List<(String, String)> keys;
    if (_pane == Pane.search) {
      keys = _page == TuiPage.home
          ? const [('enter', '搜索'), ('tab/esc', '推荐'), ('ctrl+c', '退出')]
          : const [('enter', '搜索'), ('tab', '结果'), ('esc', '主页'), ('ctrl+c', '退出')];
    } else if (_page == TuiPage.home) {
      keys = _w >= 100
          ? const [
              ('enter', '播放'),
              ('space', '暂停'),
              ('←→', '±10s'),
              ('+-', '音量'),
              (',/.', '上下首'),
              ('/', '过滤'),
              ('r', '刷新'),
              ('tab', '搜索'),
              ('q', '退出'),
            ]
          : const [
              ('enter', '播放'),
              ('space', '暂停'),
              ('←→', '快进'),
              ('r', '刷新'),
              ('tab', '搜索'),
              ('q', '退出'),
            ];
    } else if (_w >= 100) {
      keys = const [
        ('enter', '播放'),
        ('space', '暂停'),
        ('←→', '±10s'),
        ('+-', '音量'),
        (',/.', '上下首'),
        ('/', '过滤'),
        ('n', '下一页'),
        ('tab', '搜索'),
        ('q', '退出'),
      ];
    } else {
      keys = const [
        ('enter', '播放'),
        ('space', '暂停'),
        ('←→', '快进'),
        ('n', '下一页'),
        ('tab', '搜索'),
        ('q', '退出'),
      ];
    }
    final keyStyle = Style(foregroundRgb: Palette.accent);
    final sep = Style(foregroundRgb: Palette.surface).render(' · ');
    return ' ${truncate(keys.map((e) => '${keyStyle.render(e.$1)} ${e.$2}').join(sep), _w - 2)}';
  }

  static String _fmt(double seconds) {
    if (seconds.isNaN || seconds < 0) return '--:--';
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── 设计预览(无终端静态输出) ────────────────────────────────────────────

  /// 伪造一帧界面,供 `--preview` 设计审阅:无网络、无 mpv、无终端。
  static List<SearchResult> _seedRecs() => [
        for (final (t, a) in const [
          ('晴天', '周杰伦 - 音乐 · 525.1万 播放'),
          ('【4K】久石让《天空之城》', '久石让 - 音乐 · 312.6万 播放'),
          ('《Bad Apple!!》钢琴版', '触手猴 - 音乐 · 180.2万 播放'),
          ('夜空中最亮的星 (Live)', '逃跑计划 - 音乐 · 96.8万 播放'),
          ('【治愈钢琴】告白之夜', 'Ayasa - 音乐 · 88.3万 播放'),
          ('王菲《如愿》完整版', '王菲 - 音乐 · 71.5万 播放'),
          ('少女与战车 めぐみん Ver.', 'Rina - 音乐 · 55.0万 播放'),
          ('《孤勇者》翻唱', '小石头 - 音乐 · 42.7万 播放'),
        ])
          SearchResult(
            id: 'BV1xx411c7mD',
            title: t,
            subtitle: a,
            coverUrl: '',
            type: SearchResultType.video,
          ),
      ];

  static List<SearchResult> _seedResults() => [
        for (final (t, a) in const [
          ('晴天', '周杰伦 - 华语 流行'),
          ('晴天 (Live 版)', '周杰伦 - 演唱会'),
          ('晴天 · 钢琴独奏', 'Piano Covers - 钢琴'),
          ('晴天 吉他指弹', '指弹中国 - 指弹 吉他'),
          ('【治愈钢琴】晴天', 'pure music - 轻音乐'),
          ('晴天 合唱版', '校园之声 - 合唱'),
          ('晴天 (Remix)', 'DJ Wet - 电子'),
          ('双簧管版晴天', '管乐团 - 古典'),
        ])
          SearchResult(
            id: 'BV1xx411c7mD',
            title: t,
            subtitle: a,
            coverUrl: '',
            type: SearchResultType.video,
          ),
      ];

  static Music _seedPlaying() => Music(
        id: 'BV1xx411c7mD',
        cid: '1',
        title: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        coverUrl: '',
        duration: const Duration(seconds: 269),
        audioUrl: '',
      );

  static const _seedPlayer =
      MpvState(position: 83, duration: 269, volume: 80);

  /// 主页 · 空态(官方推荐加载中)。
  static String previewHomeEmpty({int width = 100, int height = 26}) {
    final m = AppModel(api: TuiApi());
    m._w = width;
    m._h = height;
    m._homeList = m._reheight(m._homeList);
    m._searchList = m._reheight(m._searchList);
    m._recsLoading = true;
    m._status = '就绪 · 已从桌面 App 导入登录态';
    return m.view().content;
  }

  /// 主页 · 官方推荐(播放中,列表焦点)。
  static String previewHome({int width = 100, int height = 26}) {
    final m = AppModel(api: TuiApi());
    m._w = width;
    m._h = height;
    m._recs = _seedRecs();
    m._queuePage = TuiPage.home;
    m._playingIdx = 0;
    m._status = '官方推荐 · ${m._recs.length} 首 · tab 浏览推荐';
    m._rebuildHomeItems();
    m._homeList = m._reheight(m._homeList).select(0);
    m._searchList = m._reheight(m._searchList);
    m._pane = Pane.list;
    m._nowPlaying = _seedPlaying();
    m._player = _seedPlayer;
    return m.view().content;
  }

  /// 搜索页 · 结果(播放中,列表焦点)。
  static String previewSearch({int width = 100, int height = 26}) {
    final m = AppModel(api: TuiApi());
    m._w = width;
    m._h = height;
    m._page = TuiPage.search;
    m._input = m._input.copyWith(value: '晴天');
    m._results = _seedResults();
    m._keyword = '晴天';
    m._pageNo = 1;
    m._numPages = 3;
    m._queuePage = TuiPage.search;
    m._playingIdx = 0;
    m._status = '找到 ${m._results.length} 条 · enter 播放 · n 下一页';
    m._rebuildSearchItems();
    m._searchList = m._reheight(m._searchList).select(0);
    m._homeList = m._reheight(m._homeList);
    m._pane = Pane.list;
    m._nowPlaying = _seedPlaying();
    m._player = _seedPlayer;
    return m.view().content;
  }
}
