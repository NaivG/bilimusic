package github.naivg.just_aaudio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.EventChannel;
import java.io.File;

/**
 * AAudioPlayer - 使用AAudio/Oboe实现低延迟音频播放的播放器
 */
public class AAudioPlayer implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private static final String TAG = "AAudioPlayer";

    private final Context context;
    private final MethodChannel methodChannel;
    private final EventChannel eventChannel;
    private final String playerId;
    private EventChannel.EventSink positionEventSink;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // 位置回调对象（传递给C++层）
    private final PositionCallback positionCallback = new PositionCallback();

    // AAudio相关变量
    private long aaudioEngineHandle = 0;
    // 当前加载的WAV缓存文件路径
    private String currentWavCachePath = null;
    
    public AAudioPlayer(final Context applicationContext,
            final BinaryMessenger messenger,
            final String id) {
        this.context = applicationContext;
        this.playerId = id;
        this.methodChannel = new MethodChannel(messenger, "github.naivg.just_aaudio.methods." + id);
        this.methodChannel.setMethodCallHandler(this);
        this.eventChannel = new EventChannel(messenger, "github.naivg.just_aaudio.events." + id);
        this.eventChannel.setStreamHandler(this);

        // 初始化AAudio引擎
        this.aaudioEngineHandle = nativeCreateEngine();
        if (this.aaudioEngineHandle == 0) {
            Log.e(TAG, "Failed to create AAudio engine");
            throw new RuntimeException("Failed to create AAudio engine - nativeCreateEngine returned 0");
        } else {
            Log.d(TAG, "AAudio engine created successfully with handle: " + this.aaudioEngineHandle);
        }
    }

    /**
     * 位置回调类 - 将原生位置推送给Dart层
     */
    private class PositionCallback {
        public void onPositionUpdate(long positionMs) {
            mainHandler.post(() -> {
                if (positionEventSink != null) {
                    positionEventSink.success(positionMs);
                }
            });
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        positionEventSink = events;
        // 注册位置回调到原生端
        if (aaudioEngineHandle != 0) {
            nativeSetPositionCallback(aaudioEngineHandle, positionCallback);
        }
    }

    @Override
    public void onCancel(Object arguments) {
        // 清除原生端的位置回调
        if (aaudioEngineHandle != 0) {
            nativeClearPositionCallback(aaudioEngineHandle);
        }
        positionEventSink = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "load": {
                String uri = call.argument("uri");
                loadMedia(uri, result);
                break;
            }
            case "play": {
                play(result);
                break;
            }
            case "pause": {
                pause(result);
                break;
            }
            case "stop": {
                stop(result);
                break;
            }
            case "seekTo": {
                // 修复：使用Number处理整数类型转换问题
                Number positionNumber = call.argument("position");
                long position = positionNumber != null ? positionNumber.longValue() : 0;
                seekTo(position, result);
                break;
            }
            case "getPosition": {
                getPosition(result);
                break;
            }
            case "getDuration": {
                getDuration(result);
                break;
            }
            case "setSpeed": {
                Double speed = call.argument("speed");
                setSpeed(speed, result);
                break;
            }
            case "setVolume": {
                Double volume = call.argument("volume");
                setVolume(volume, result);
                break;
            }
            case "dispose": {
                dispose(result);
                break;
            }
            case "convertAudioFormat": {
                String inputPath = call.argument("inputPath");
                String outputPath = call.argument("outputPath");
                Integer sampleRate = call.argument("sampleRate");
                Integer channels = call.argument("channels");
                Integer bitrate = call.argument("bitrate");
                
                if (inputPath == null || outputPath == null) {
                    result.error("InvalidArguments", "Input or output path is null", null);
                    return;
                }
                
                // 使用默认值如果参数未提供
                int sr = sampleRate != null ? sampleRate : 44100;
                int ch = channels != null ? channels : 2;
                int br = bitrate != null ? bitrate : 128000;
                
                boolean success = AudioConverter.convertToWav(inputPath, outputPath);
                if (success) {
                    Log.d(TAG, "Successfully converted audio format from " + inputPath + " to " + outputPath);
                    result.success(null);
                } else {
                    Log.e(TAG, "Failed to convert audio format from " + inputPath + " to " + outputPath);
                    result.error("ConvertError", "Failed to convert audio format", null);
                }
                break;
            }
            default:
                result.notImplemented();
                break;
        }
    }

    private void loadMedia(String uri, @NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        // 检查是否需要转换音频格式
        String processedUri = uri;
        if (uri != null && uri.startsWith("file://")) {
            String filePath = uri.substring(7); // 移除"file://"前缀
            String extension = getFileExtension(filePath).toLowerCase();
            
            // 检查是否是需要转换的格式
            if (isCompressedFormat(extension)) {
                // 尝试转换为WAV格式
                String wavPath = convertToWavIfNeeded(filePath);
                if (wavPath != null) {
                    processedUri = "file://" + wavPath;
                } else {
                    // 如果转换失败，尝试直接加载原始文件
                    Log.w(TAG, "Failed to convert audio file, attempting to load original file: " + filePath);
                }
            }
        }
        
        boolean success = nativeLoad(aaudioEngineHandle, processedUri);
        if (success) {
            Log.d(TAG, "Successfully loaded media: " + processedUri);
            result.success(null);
        } else {
            Log.e(TAG, "Failed to load media with AAudio: " + processedUri);
            // 提供更具体的错误信息
            String errorMessage = "Failed to load media with AAudio. " +
                "This may be due to an unsupported audio format or file access issues. " +
                "Currently WAV, AIFF, and other formats supported by libsndfile are supported directly. " +
                "For other formats, conversion should be done before calling this method.";
            result.error("LoadError", errorMessage, null);
        }
    }
    
    /**
     * 获取文件扩展名
     */
    private String getFileExtension(String filePath) {
        if (filePath == null || filePath.isEmpty()) {
            return "";
        }
        int lastDot = filePath.lastIndexOf('.');
        if (lastDot >= 0) {
            return filePath.substring(lastDot + 1);
        }
        return "";
    }
    
    /**
     * 判断是否是需要转换的压缩格式
     */
    private boolean isCompressedFormat(String extension) {
        return "mp3".equals(extension) || "mp4".equals(extension) || 
               "m4a".equals(extension) || "aac".equals(extension) || 
               "ogg".equals(extension) || "flv".equals(extension) || 
               "webm".equals(extension) || "bin".equals(extension);
    }
    
    /**
     * 如果需要，将音频文件转换为WAV格式
     */
    private String convertToWavIfNeeded(String inputPath) {
        try {
            File inputFile = new File(inputPath);
            if (!inputFile.exists()) {
                Log.e(TAG, "Input file does not exist: " + inputPath);
                return null;
            }
            
            String outputPath = inputPath + ".wav";
            File outputFile = new File(outputPath);
            
            // 如果已经存在转换后的文件，直接使用
            if (outputFile.exists()) {
                Log.d(TAG, "Using existing WAV file: " + outputPath);
                currentWavCachePath = outputPath;
                return outputPath;
            }

            // 执行转换
            boolean success = AudioConverter.convertToWav(inputPath, outputPath);
            if (success && outputFile.exists()) {
                Log.d(TAG, "Successfully converted to WAV: " + outputPath);
                currentWavCachePath = outputPath;
                return outputPath;
            } else {
                Log.e(TAG, "Failed to convert to WAV: " + inputPath);
                return null;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error converting audio file", e);
            return null;
        }
    }

    private void play(@NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        boolean success = nativePlay(aaudioEngineHandle);
        if (success) {
            Log.d(TAG, "Successfully started playback");
            result.success(null);
        } else {
            Log.e(TAG, "Failed to play with AAudio");
            result.error("PlayError", "Failed to play with AAudio", null);
        }
    }

    private void pause(@NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        boolean success = nativePause(aaudioEngineHandle);
        if (success) {
            Log.d(TAG, "Successfully paused playback");
            result.success(null);
        } else {
            Log.e(TAG, "Failed to pause with AAudio");
            result.error("PauseError", "Failed to pause with AAudio", null);
        }
    }

    private void stop(@NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        boolean success = nativeStop(aaudioEngineHandle);
        if (success) {
            Log.d(TAG, "Successfully stopped playback");
            result.success(null);
        } else {
            Log.e(TAG, "Failed to stop with AAudio");
            result.error("StopError", "Failed to stop with AAudio", null);
        }
    }

    private void seekTo(long position, @NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        boolean success = nativeSeekTo(aaudioEngineHandle, position);
        if (success) {
            Log.d(TAG, "Successfully seeked to position: " + position);
            result.success(null);
        } else {
            Log.e(TAG, "Failed to seek with AAudio to position: " + position);
            result.error("SeekError", "Failed to seek with AAudio", null);
        }
    }

    private void getPosition(@NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        long position = nativeGetPosition(aaudioEngineHandle);
        result.success(position);
    }

    private void getDuration(@NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        
        long duration = nativeGetDuration(aaudioEngineHandle);
        result.success(duration);
    }

    private void setSpeed(Double speed, @NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        float speedValue = speed != null ? speed.floatValue() : 1.0f;
        Log.d(TAG, "Setting speed: " + speedValue);
        nativeSetSpeed(aaudioEngineHandle, speedValue);
        result.success(null);
    }

    private void setVolume(Double volume, @NonNull MethodChannel.Result result) {
        if (aaudioEngineHandle == 0) {
            result.error("NoEngine", "AAudio engine not initialized", null);
            return;
        }
        float volumeValue = volume != null ? volume.floatValue() : 1.0f;
        Log.d(TAG, "Setting volume: " + volumeValue);
        nativeSetVolume(aaudioEngineHandle, volumeValue);
        result.success(null);
    }

    private void dispose(@NonNull MethodChannel.Result result) {
        disposeWithoutResult();
        result.success(null);
    }

    public void disposeWithoutResult() {
        // 清理WAV缓存文件
        if (currentWavCachePath != null) {
            File cacheFile = new File(currentWavCachePath);
            if (cacheFile.exists()) {
                boolean deleted = cacheFile.delete();
                Log.d(TAG, "WAV cache file deleted: " + currentWavCachePath + ", result: " + deleted);
            }
            currentWavCachePath = null;
        }

        if (aaudioEngineHandle != 0) {
            nativeClearPositionCallback(aaudioEngineHandle);
            nativeDisposeEngine(aaudioEngineHandle);
            aaudioEngineHandle = 0;
            Log.d(TAG, "AAudio engine disposed");
        }
        positionEventSink = null;
    }

    // Native方法声明
    private native long nativeCreateEngine();
    private native void nativeDisposeEngine(long engineHandle);
    private native boolean nativeLoad(long engineHandle, String uri);
    private native boolean nativePlay(long engineHandle);
    private native boolean nativePause(long engineHandle);
    private native boolean nativeStop(long engineHandle);
    private native boolean nativeSeekTo(long engineHandle, long position);
    private native long nativeGetPosition(long engineHandle);
    private native long nativeGetDuration(long engineHandle);
    private native boolean nativeIsPlaying(long engineHandle);
    private native void nativeSetPositionCallback(long engineHandle, Object callback);
    private native void nativeClearPositionCallback(long engineHandle);
    private native void nativeSetSpeed(long engineHandle, float speed);
    private native void nativeSetVolume(long engineHandle, float volume);

    static {
        try {
            System.loadLibrary("just_aaudio");
            Log.d(TAG, "Native library loaded successfully");
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "Failed to load native library", e);
        }
    }
}