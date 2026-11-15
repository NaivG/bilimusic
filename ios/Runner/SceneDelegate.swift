import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var nativeTabBarHost: NativeTabBarHost?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // iPhone（iOS 26+）用原生 Liquid Glass 标签栏；其他设备保持原样。
    guard let window else { return }
    nativeTabBarHost = NativeTabBarHost.install(in: window)
  }
}
