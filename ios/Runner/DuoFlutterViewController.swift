import Flutter
import UIKit

/// 根视图控制器：把 iPhone Duo 的系统布局数值推给 Dart。
///
/// Flutter 只拿得到普通安全区。iPhone Duo 上，竖栏在哪一边、栏该放在哪、
/// 状态栏 / 摄像头 / 折痕占了哪些地方，都由 UIKit 给出（iOS 27.1）：
///
/// - `traitCollection.verticalBarEdge`：竖栏在哪一边（没有竖栏时为 unspecified）；
/// - `edgeInsets(for: .bar(onEdge:extent:))`：一条栏放在某条边上时该占的区域；
/// - `reservedRegions(kind:options:)`：系统占用的区域（状态栏、摄像头）和
///   分割区域（折痕）。
///
/// 每次布局后读取，有变化才通过 `bilimusic/duo_layout` 通道发给 Dart；
/// Dart 启动时也可以主动取一次。
class DuoFlutterViewController: FlutterViewController {
  static let channelName = "bilimusic/duo_layout"

  /// 竖栏里放一条栏用的宽度：竖栏按钮的大小。
  private static let sideBarExtent: CGFloat = 48
  /// 顶部栏的两种高度：页头按钮行、导航栏工具栏。
  private static let topBarExtents: [CGFloat] = [44, 56]

  private var channel: FlutterMethodChannel?
  private var lastPayload: NSDictionary?

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "get" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.currentPayload())
    }
    self.channel = channel

    if #available(iOS 27.1, *) {
      registerForTraitChanges(
        UITraitCollection.systemTraitsAffectingVerticalBarEdge
      ) { (controller: DuoFlutterViewController, _) in
        controller.view.setNeedsLayout()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // 安全区变化的回调来得早，那时占用区域可能还没算出来；在布局之后读取。
    guard let payload = currentPayload() else { return }
    let dictionary = payload as NSDictionary
    guard lastPayload != dictionary else { return }
    lastPayload = dictionary
    channel?.invokeMethod("update", arguments: payload)
  }

  /// 当前的系统布局数值；iOS 27.1 以下或视图还没加载时为 nil。
  private func currentPayload() -> [String: Any]? {
    guard #available(iOS 27.1, *), let view = viewIfLoaded else { return nil }

    func insets(_ value: UIEdgeInsets) -> [Double] {
      [value.top, value.left, value.bottom, value.right].map { Double($0) }
    }
    func regions(_ kind: UIView.ReservedRegion.Kind) -> [[Double]] {
      view.reservedRegions(kind: kind, options: .includeInactive).map { region in
        let frame = region.frame
        return [frame.minX, frame.minY, frame.width, frame.height, region.isActive ? 1 : 0]
          .map { Double($0) }
      }
    }

    let rightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
    let edge: String
    switch traitCollection.verticalBarEdge {
    case .leading: edge = rightToLeft ? "right" : "left"
    case .trailing: edge = rightToLeft ? "left" : "right"
    default: edge = "none"
    }

    var payload: [String: Any] = [
      "size": [Double(view.bounds.width), Double(view.bounds.height)],
      "safeArea": insets(view.safeAreaInsets),
      "verticalBarEdge": edge,
      "topBars": Self.topBarExtents.map {
        insets(view.edgeInsets(for: .bar(onEdge: UIRectEdge.top, extent: $0)))
      },
      "occlusions": regions(.occlusion),
      "divisions": regions(.division),
      "statusBarHidden":
        view.window?.windowScene?.statusBarManager?.isStatusBarHidden ?? false,
    ]
    if edge != "none" {
      let side: UIRectEdge = edge == "right" ? UIRectEdge.right : UIRectEdge.left
      payload["sideBar"] = insets(
        view.edgeInsets(for: .bar(onEdge: side, extent: Self.sideBarExtent))
      )
    }
    return payload
  }
}
