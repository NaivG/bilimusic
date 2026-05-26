package github.naivg.just_aaudio;

import androidx.annotation.NonNull;

import java.util.HashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** JustAaudioFlutterPlugin */
public class JustAaudioFlutterPlugin implements FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private FlutterPlugin.FlutterPluginBinding flutterPluginBinding;
  private final HashMap<String, AAudioPlayer> audioPlayers = new HashMap<>();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding;
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "just_aaudio");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("Android " + android.os.Build.VERSION.RELEASE);
        break;
      case "createPlayer": {
        String playerId = call.argument("playerId");
        if (playerId == null) {
          result.error("NoPlayerId", "Player ID is required", null);
          return;
        }

        if (audioPlayers.containsKey(playerId)) {
          result.error("PlayerExists", "Player with ID " + playerId + " already exists", null);
          return;
        }

        AAudioPlayer player;
        try {
            player = new AAudioPlayer(
                flutterPluginBinding.getApplicationContext(),
                flutterPluginBinding.getBinaryMessenger(),
                playerId);
        } catch (RuntimeException e) {
            result.error("EngineInitFailed", e.getMessage(), null);
            return;
        }
        audioPlayers.put(playerId, player);
        result.success(null);
        break;
      }
      case "disposePlayer": {
        String playerId = call.argument("playerId");
        if (playerId == null) {
          result.error("NoPlayerId", "Player ID is required", null);
          return;
        }

        AAudioPlayer player = audioPlayers.remove(playerId);
        if (player != null) {
          player.disposeWithoutResult();
          result.success(null);
        } else {
          result.error("PlayerNotFound", "Player with ID " + playerId + " not found", null);
        }
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
    // 释放所有播放器
    for (AAudioPlayer player : audioPlayers.values()) {
      player.disposeWithoutResult();
    }
    audioPlayers.clear();
  }
}