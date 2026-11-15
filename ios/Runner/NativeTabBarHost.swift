import Flutter
import UIKit

/// 把唯一的 Flutter 视图放进系统 `UITabBarController`，让 iPhone 用上原生的
/// Liquid Glass 标签栏：普通 iPhone 在底部，iPhone Duo 合上时在竖状态栏里。
///
/// 页面仍然全部由 Flutter 绘制，只有标签栏是原生的。Flutter 视图控制器跟着
/// 选中的标签页移动到对应的容器里；标签栏何时显示（竖屏外壳的 Tab 页）、
/// 何时收起（二级页、播放详情、横屏外壳）由 Dart 决定。
final class NativeTabBarHost: NSObject, UITabBarControllerDelegate {
  static let channelName = "bilimusic/native_tab_bar"

  /// 设备支持时把宿主装成窗口的根控制器；iPad 和没有 Liquid Glass 标签栏的
  /// 系统返回 nil，保留 Flutter 自己的导航。
  static func install(in window: UIWindow) -> NativeTabBarHost? {
    guard #available(iOS 26.0, *),
          UIDevice.current.userInterfaceIdiom == .phone,
          let flutterController = window.rootViewController as? FlutterViewController else {
      return nil
    }
    let host = NativeTabBarHost(flutterController: flutterController)
    window.rootViewController = host.tabBarController
    return host
  }

  let tabBarController = UITabBarController()
  private let flutterController: FlutterViewController
  private let channel: FlutterMethodChannel
  private let containers: [FlutterTabContainer]

  @available(iOS 26.0, *)
  private init(flutterController: FlutterViewController) {
    self.flutterController = flutterController
    channel = FlutterMethodChannel(
      name: NativeTabBarHost.channelName,
      binaryMessenger: flutterController.binaryMessenger
    )
    // 标题在 Dart 启动后由 setItems 统一下发，这里先放同样的默认值。
    let items: [(String, String, String)] = [
      ("首页", "house", "house.fill"),
      ("发现", "safari", "safari.fill"),
      ("我的", "person", "person.fill"),
      ("设置", "gearshape", "gearshape.fill"),
    ]
    containers = items.map { title, symbol, selectedSymbol in
      let container = FlutterTabContainer()
      container.tabBarItem = UITabBarItem(
        title: title,
        image: UIImage(systemName: symbol),
        selectedImage: UIImage(systemName: selectedSymbol)
      )
      return container
    }
    super.init()

    tabBarController.viewControllers = containers
    tabBarController.delegate = self
    // 等 Flutter 的竖屏外壳要求时再显示。
    tabBarController.setTabBarHidden(true, animated: false)
    embedFlutter(in: containers[0])

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isActive":
      result(true)
    case "setSelectedIndex":
      guard let index = call.arguments as? Int, containers.indices.contains(index) else {
        result(FlutterError(code: "bad_args", message: "Invalid tab index", details: nil))
        return
      }
      if tabBarController.selectedIndex != index {
        tabBarController.selectedIndex = index
        embedFlutter(in: containers[index])
      }
      result(nil)
    case "setTabBarHidden":
      let hidden = call.arguments as? Bool ?? false
      if #available(iOS 18.0, *), tabBarController.isTabBarHidden != hidden {
        tabBarController.setTabBarHidden(hidden, animated: true)
      }
      result(nil)
    case "setTitles":
      let titles = call.arguments as? [String] ?? []
      for (container, title) in zip(containers, titles) {
        container.tabBarItem.title = title
      }
      result(nil)
    case "setTintColor":
      if let argb = call.arguments as? Int {
        // Liquid Glass 标签栏的选中色取自控制器视图的 tintColor。
        let color = UIColor(argb: argb)
        tabBarController.view.tintColor = color
        tabBarController.tabBar.tintColor = color
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    // UIKit 把新容器放上屏幕之后再移动 Flutter 视图；提前移动会让新标签页空白。
    guard let index = containers.firstIndex(where: { $0 === viewController }) else { return }
    embedFlutter(in: containers[index])
    channel.invokeMethod("select", arguments: index)
  }

  private func embedFlutter(in container: FlutterTabContainer) {
    guard flutterController.parent !== container else { return }
    flutterController.willMove(toParent: nil)
    flutterController.view.removeFromSuperview()
    flutterController.removeFromParent()

    container.addChild(flutterController)
    flutterController.view.frame = container.view.bounds
    flutterController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.view.addSubview(flutterController.view)
    flutterController.didMove(toParent: container)
    tabBarController.setNeedsStatusBarAppearanceUpdate()
  }
}

/// 标签页的内容控制器。只在第一次出现时把出现回调转给 Flutter 视图控制器：
/// 之后切换标签页时，同一个一直可见的 Flutter 视图只是换了容器，再转发会让
/// app 每点一次标签就被报告为 inactive / paused。
private final class FlutterTabContainer: UIViewController {
  private static var flutterHasAppeared = false

  override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

  // 状态栏样式 / 显隐、Home 指示条和方向都由 Flutter 视图控制器决定；
  // 不转发的话，Flutter 设置的状态栏文字颜色不会生效。
  override var childForStatusBarStyle: UIViewController? { children.first }
  override var childForStatusBarHidden: UIViewController? { children.first }
  override var childForHomeIndicatorAutoHidden: UIViewController? { children.first }
  override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
    children.first
  }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    children.first?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if !Self.flutterHasAppeared {
      children.forEach { $0.beginAppearanceTransition(true, animated: animated) }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !Self.flutterHasAppeared, !children.isEmpty {
      children.forEach { $0.endAppearanceTransition() }
      Self.flutterHasAppeared = true
    }
  }
}

private extension UIColor {
  /// Flutter `Color.toARGB32()` 的整数值。
  convenience init(argb: Int) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
