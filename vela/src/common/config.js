/**
 * 全局配置与常量
 * 用户级配置走 @system.storage。
 */
export const CONFIG = {
  // B 站主站 API
  BILI_API: 'https://api.bilibili.com',
  // 通行证（扫码登录）
  BILI_PASSPORT: 'https://passport.bilibili.com',
  // 防盗链相关请求头：B 站 CDN 会校验 Referer
  BILI_REFERER: 'https://www.bilibili.com',
  BILI_ORIGIN: 'https://www.bilibili.com',

  // 默认 UA（部分接口对 UA 有要求）
  USER_AGENT:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',

  // 二维码轮询
  QR_POLL_INTERVAL: 2000,
  // 二维码有效期（官方为 180 秒，留一点余量）
  QR_TIMEOUT: 175000,

  LOGIN: {
    /**
     * 扫码登录只有 TV 端一条路（passport-tv-login）：登录票据 Cookie 直接在响应体
     * cookie_info.cookies[] 里返回，不依赖 Set-Cookie，也不依赖跨域地址。
     */
    // TV 端 appkey/appsec
    TV_APPKEY: '4409e2ce8ffd12b8',
    TV_APPSEC: '59b43e04ad6965f34319062b478f83dd',
    TV_LOCAL_ID: 0,
  },

  // 播放进度轮询间隔（Vela 无 ontimeupdate，需轮询 getPlayState）
  PROGRESS_INTERVAL: 1000,

  // 音量页可见时的系统音量对账间隔。
  // 音量真相在 @system.volume（外部实体键/系统设置改的就是它），
  // onMediaValueChanged 在老机型上可能不触发，故可见期间按这个间隔回读一次。
  VOLUME_POLL_INTERVAL: 1000,

  // WBI 口令缓存时长（官方为每日更替，这里缓存 6 小时）
  WBI_CACHE_TTL: 6 * 60 * 60 * 1000,

  /**
   * 网络通道选择
   *
   *   'auto'  —— 有 @system.fetch 就用原生；没有这条能力的机型（Redmi Watch 4、
   *              Xiaomi Watch H1 E 等，官方支持明细里就没有）自动改走 interconnect
   *              网桥：手机/PC 端的 AstroBox「网桥 FetchBridge」插件代发 HTTP。
   *   'force' —— 强制走网桥。验证网桥链路时用。
   *   'off'   —— 只用原生 fetch（网桥代码不参与）。
   * 
   * 不清楚的请勿修改。
   */
  FETCH_BRIDGE: 'auto',

  /**
   * interconnect 网桥参数
   */
  BRIDGE: {
    // 握手超时。最常见故障就是这里超时：手机没连，或 AstroBox 里没给本应用打开「监听」
    HANDSHAKE_TIMEOUT: 4000,
    // 单笔请求超时（含分片重组全过程）
    REQUEST_TIMEOUT: 20000,
    // 本端声明的分片大小（编码前字节数；插件会夹到 [256, 65536]）
    CHUNK_SIZE: 4096,
    // 在途分片窗口：手表内存紧张，4 片 × 4 KB ≈ 16 KB 在途
    ACK_WINDOW: 4,
    // 只声明这两条：text 给正常 JSON、base64 给含非 ASCII 的响应；顺序即偏好
    ENCODINGS: ['text', 'base64'],
    // 不声明 deflate/lz4：省掉 JS 侧解压依赖 —— 分片本身就够过 16 KB 单消息保护线
    COMPRESSIONS: ['none'],
    // 本端协议版本：4 = 分片 + 累计 ACK + v4 开放长度流。
    // v4 流只给「音频落盘」用（fetchbridge.buildFetchRequest 对普通请求显式 stream:false，
    // 插件对 Content-Length >= 64KiB 的自动流式不会影响 JSON 链路）。
    PROTOCOL_VERSION: 4,
    // v4 流能力声明（false 时整端退回 v3 行为，网桥机型音频落盘随之不可用）
    STREAM: true,
    // 流帧空闲超时：连续这么久没收到任何帧/没推进 ACK 就判死并取消。
    // 大文件传输**不设总时长上限**（蓝牙上一首 3 MB 的歌可能要几分钟），只看是否还活着。
    STREAM_IDLE_TIMEOUT: 20000,
  },

  /**
   * 音频本地缓存（B 档：网桥机型唯一能出声的方式 = 落盘后播本地文件）
   *
   * 目录、命名、清理策略统一由 services/audioCache.js 管理 —— 别处不要直接
   * 拿 @system.file 往这个目录写东西。
   */
  AUDIO_CACHE: {
    // 缓存目录（internal://cache 由系统在空间紧张时可回收，适合放可再生的音频缓存）
    DIR: 'internal://cache/bilimusic_audio/',
    // 文件名：<PREFIX><key><EXT>，key 来自曲目 bvid/avid（见 audioCache.buildCacheKey）。
    // 下载中的文件追加 .part 后缀，完整落盘后才改名 —— 残片永远不会被当成可播缓存。
    PREFIX: 'bm_a_',
    EXT: '.m4a',
    // 常驻保留份数：当前曲目 + 预取的下一首 + 刚播的上一首，超出即删。
    MAX_KEEP: 5,
    /**
     * 原生机型（有 @system.fetch）的分块下载大小。
     *
     * 为什么必须分块：Vela 的 fetch 失败码透传 libcurl，28 = CURLE_OPERATION_TIMEDOUT
     * 是**单次操作**超时。走蓝牙的机型实测整文件下载只有 60-70 KiB/s，
     * 一首 2.5 MB 的歌要 37 秒、5 MB 要 74 秒 —— 必超时；而一次超时什么都没留下。
     *
     * 改成 Range 分块后：单块 256 KB 在 60 KiB/s 下约 4 秒完成，稳在超时窗口内；
     * 落点由我们自己记（written），于是①失败能从断点续传，②同一首第二次播直接命中缓存。
     */
    CHUNK_BYTES: 256 * 1024,
    /**
     * Range 档位阶梯（首档 = CHUNK_BYTES）：上一档「2xx 却没有字节」就往下走一档。
     *
     * 为什么要阶梯：部分机型上 `responseType:'arraybuffer'` 对 256 KB 的响应会回
     * **206 + 合法 Content-Range + 空 data** —— 传输明显是通的（头都对），更像运行时
     * 把太大的响应体丢了。快应用规范里 fetch 就明写着「**数据大小不能超过 100k**」
     * （widget 变体甚至「不返回 internal 文件」），256 KB 正好越线。档位越小越安全，
     * 但请求数越多，所以从大到小试、探明后锁存，healthy 机型不受影响。
     */
    CHUNK_STEPS: [256 * 1024, 64 * 1024, 32 * 1024, 16 * 1024],
    // 单块重试次数（含首次）。蓝牙抖动导致单块超时很常见，重试一块远比整首重来便宜。
    CHUNK_RETRIES: 4,
    /**
     * `@system.request.download` 整份原生下载的两道时间闸（见 audioCache.downloadViaRequest）。
     *
     * 这条路是**兜底通道**：fetch 分块在这台机型上取不到字节时改用它（原生下载管理器
     * 自己把字节写进应用缓存目录，不经 tmp 分区、不占 JS 堆）。它没有进度回调，
     * 我们靠轮询文件大小报进度，所以必须自己设闸：任务迟迟不结束不能让页面挂着。
     */
    // 总时长上限（一首 3 MB 在 60-70 KiB/s 上要几十秒，蓝牙抖动时更久）
    WHOLE_DOWNLOAD_TIMEOUT: 5 * 60 * 1000,
    // 建任务的闸门：`download` 既不回 success 也不回 fail 时不能把页面挂住
    // （这条闸门比总时长那条更靠前 —— 拿不到 token 就还轮不到下载过程的闸门）
    WHOLE_DOWNLOAD_CREATE: 15 * 1000,
    // 已经看到文件在长、却连续这么久没长过 → 判死（没看到文件时不受这条约束）
    WHOLE_DOWNLOAD_IDLE: 60 * 1000,
    // 进度轮询间隔（同时用来发现"文件到底落在哪"）
    WHOLE_DOWNLOAD_POLL: 1000,
    /**
     * 边下边播（progressive）。
     *
     * `@system.request.download` 没有 Range、没有进度回调，官方不给任何分片能力；
     * 但它的落点文件是**边下边写**的（waitDownloadComplete 每秒轮询落点大小就是证据）。
     * 落够 PROGRESSIVE_MIN 字节就把落点直接交给 audio.src 开播，剩余字节在播放的
     * 同时继续落 —— 蓝牙总时长一点没省（带宽是物理上限），但**出声时间**从几十秒
     * 缩到几秒（512 KB ≈ 60 KiB/s × 8 s），而且这首下完进缓存，第二次播零等待。
     *
     *   PROGRESSIVE     总开关：若机型出现「起播即报错 / 播 30 秒就停」（音频服务不认
     *                   还在长的文件），置 false 退回整份等待，不用改代码。
     *   PROGRESSIVE_MIN 起播阈值。取值考虑：①必须盖过 m4a 的 moov 头（几十 KB 量级）；
     *                   ②给解码器留出领先下载速度的余量 —— 播放每秒只吃 ~16 KB
     *                   （132 Kbps），下载每秒给 60 KB，512 KB 的跑道足够熬过蓝牙抖动。
     *                   只对「正式播放」生效；预取仍静默整份。总长不足阈值两倍的曲子
     *                   不启用（几秒就下完了，没必要赌 growing file 的兼容性）。
     *                   网桥机型不启用（v4 流走 JS 堆分帧 + WRITE_BATCH 攒批，那是另一套写盘节奏；
     *                   而且它的交付点由帧层决定，攒批只推迟字节落盘、不推迟交付）。
     */
    PROGRESSIVE: true,
    PROGRESSIVE_MIN: 512 * 1024,
    /**
     * `responseType:'file'` 读法下，把框架落下的临时文件搬进 .part 时每次读多少字节。
     *
     * 这条路是**给「arraybuffer 拿不到字节」的机型兜底的**（实测：206 +
     * 合法 Content-Range，data 却是空的）：框架原生把这一段落盘不占 JS 堆，
     * 我们分片读回再追加 —— 每片只占 READ_SLICE 字节堆。手表堆小（页面 VM 都会 OOM），
     * 一次把整段读回堆里正是当初要分块下载的原因，所以这里必须小于 CHUNK_BYTES。
     *
     * 注意框架落的是 **tmp 分区**（`internal://tmp/…`），`readArrayBuffer` 直接
     * 读它回 202 参数错误 —— 那就先 `file.copy` 原生整份拷进缓存目录再按这个粒度读
     * （两条路子都在 VM 上锁存一次，见 audioCache.pumpTmpFile）。拷贝本身不占 JS 堆，
     * 所以照样"小口吃"。
     */
    READ_SLICE: 64 * 1024,
    /**
     * 网桥 v4 流落盘时**攒够这么多字节才写一次盘**（见 audioCache.streamToFile）。
     *
     * 为什么要攒：v4 流是 4 KB 一帧（BRIDGE.CHUNK_SIZE），一首 3 MB 的歌约 750 帧/首，
     * 逐帧一次 `file.writeArrayBuffer` 就是 750 次原生 IPC + 750 个短命 Promise。
     * 攒到 32 KB 再写 = 每 8 帧一次，写次数降 8 倍：IPC 往返、Promise 分配、
     * 文件系统每次打开/定位/追加的固定开销一起摊薄 —— 对手表这种小堆设备，
     * 省的不只是 CPU，还有 GC 压力。
     *
     * 为什么 32 KB（而不是更大）：
     *   ① 攒批不改交付时机 —— `sendWithProgress` 在**每次写成功后**报进度，
     *      写是按批做的，所以进度粒度 = 一批，32 KB 对「进度条跳动」完全无感；
     *   ② 内存上限 = 本值 + 一帧（4 KB），与 ACK 窗口那 16 KB 同量级；
     *   ③ 攒批只影响落盘节奏，不影响出声时机：网桥机型**本来就不启用边下边播**
     *      （makeProgressive 对网桥返回 null），播放器依然要等整份下完才拿到落点。
     */
    WRITE_BATCH: 32 * 1024,
  },

  // 收藏夹列表每页条数（接口定义域 1-20）
  FAV_PAGE_SIZE: 20,

  // 官方推荐流每页条数（rcmd 推荐流与热门兜底共用；热门接口上限 20）
  RECOMMEND_PAGE_SIZE: 12,

  STORAGE_KEYS: {
    AUTH: 'bilimusic_auth',
    PLAYLIST: 'bilimusic_playlist',
    // 跨 VM 共享播放态：Vela 每个 page 一个独立 JS VM，模块级变量不跨页共享，
    // 「当前播哪首 / 播没在播」只能落盘后各 VM 自己读回来对账。
    // 音量**不在这里**：唯一真相是系统媒体音量（@system.volume），见 playerService 的音量小节。
    PLAY_STATE: 'bilimusic_play_state',
    // 设备下载能力锁存（见 audioCache.loadDlCaps）：「fetch 链路取不到字节」「下载器认哪种
    // header 打包形态」是**这台机的运行时事实**，不是这次网络的状态 —— 探明一次就写下来，
    // 以后每个页面 VM、每次启动都不再把整条探测阶梯撞一遍（蓝牙上那是好几秒的白白下载）。
    DL_CAPS: 'bilimusic_dl_caps',
    // 历史遗留：老版本把音量存在 `bilimusic_settings_volume`（SETTINGS + '_volume'）里，
    // 现已废弃（启动时清理，见 retireLegacyVolume）
    LEGACY_VOLUME: 'bilimusic_settings_volume',
  },
}

/**
 * 取流参数
 */
export const PLAY = {
  // fnval=16 → DASH（含独立音轨）；4048 → 全部 DASH 选项
  FNVAL_DASH: 16,
  // fnval=0 → MP4 合流（带 durl），部分机型对 .m4s 音轨支持不佳时可切到这条
  FNVAL_MP4: 0,
  // 调试开关：true 时强制走 MP4/durl 取流（排查 .m4s 音轨播不动的问题）
  FORCE_DURL: false,
  // 音频码率档位：30280(192K) > 30232(132K) > 30216(64K)
  AUDIO_QUALITY: { 30280: 3, 30232: 2, 30216: 1 },
  // 边播边预取下一首（B 档：网桥机型上落盘一首要十几秒到几十秒，预取是听感的关键）
  PREFETCH: true,
  /**
   * 直链最多试几条候选（详见 common/parse.js 的 directLinkBudget）。
   *
   * 为什么要设上限：候选是「所有音质档 × 每档 3 个节点」，最多能有 9 条，而每次直链
   * 失败都要走一遍 `onerror` → 界面上闪一次错误态。上限 3 是「值得多试」与
   * 「别让用户干等」之间的折中；另外只要候选里**一条 mcdn 都没有**，就自动降到 1
   * —— upos/edge 直链必 403（它们校验 Referer，而 audio.src 发不出请求头）。
   */
  DIRECT_TRIES: 3,
  /**
   * 取流地址的有效期余量（秒）。B 站 CDN 地址带 `deadline`（实测 120 分钟），
   * 剩余时间少于这个余量就当成过期、重新取流：蓝牙链路上一首要下几十秒，
   * 卡在过期前一分钟开工必然半路 403。
   */
  URL_TTL_MARGIN: 300,
}
