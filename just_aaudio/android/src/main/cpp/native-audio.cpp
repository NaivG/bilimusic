#include <jni.h>
#include <android/log.h>
#include <oboe/Oboe.h>
#include <string>
#include <memory>
#include <thread>
#include <atomic>
#include <vector>
#include <mutex>
#include <chrono>
#include <sndfile.h>

#define LOG_TAG "NativeAudio"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// 音频引擎类
class AudioEngine : public oboe::AudioStreamCallback {
public:
    AudioEngine();
    ~AudioEngine();

    bool init();
    bool load(const char* uri);
    bool play();
    bool pause();
    bool stop();
    void seekTo(int64_t position);
    int64_t getPosition();
    int64_t getDuration();
    bool isPlaying();
    void dispose();
    void setVolume(float volume);
    void setSpeed(float speed);
    void setPositionCallback(JNIEnv* env, jobject callback);
    void clearPositionCallback();

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream *oboeStream, 
                                          void *audioData, 
                                          int32_t numFrames) override;

private:
    oboe::ManagedStream mPlaybackStream;
    std::atomic<bool> mIsPlaying{false};
    std::atomic<int64_t> mPosition{0};
    std::atomic<int64_t> mDuration{0};
    std::string mUri;
    std::atomic<int32_t> mSampleRate{0};
    std::atomic<int32_t> mChannels{0};
    std::vector<float> mAudioData;
    mutable std::mutex mAudioDataMutex;
    std::atomic<size_t> mDataPosition{0};
    std::atomic<bool> mIsLoaded{false};
    std::atomic<float> mVolume{1.0f};
    std::atomic<float> mSpeed{1.0f};

    // 位置回调相关
    JavaVM* mJvm = nullptr;
    jobject mPositionCallback = nullptr;
    int64_t mLastPositionUpdateTime = 0;

    // 新增：重新配置音频流
    bool reconfigureStream(int32_t sampleRate, int32_t channelCount);
    
    bool loadWithSndfile(const std::string& filePath);
};

AudioEngine::AudioEngine() {
    LOGD("AudioEngine constructor");
}

AudioEngine::~AudioEngine() {
    LOGD("AudioEngine destructor");
    dispose();
}

bool AudioEngine::init() {
    LOGD("Initializing audio engine");
    
    oboe::AudioStreamBuilder builder;
    oboe::Result result = builder.setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(oboe::ChannelCount::Stereo)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Exclusive)
        ->setCallback(this)
        ->openManagedStream(mPlaybackStream);
        
    if (result != oboe::Result::OK) {
        LOGE("Failed to create audio stream: %s", oboe::convertToText(result));
        return false;
    }
    
    mSampleRate.store(mPlaybackStream->getSampleRate());
    mChannels.store(mPlaybackStream->getChannelCount());
    LOGD("Audio engine initialized with sample rate: %d, channels: %d", mSampleRate.load(), mChannels.load());
    return true;
}

bool AudioEngine::load(const char* uri) {
    LOGD("Loading audio: %s", uri);
    mUri = uri;
    
    // 解析URI，目前只支持file://协议
    if (std::string(uri).find("file://") == 0) {
        std::string filePath = std::string(uri).substr(7); // 移除"file://"前缀
        return loadWithSndfile(filePath);
    }
    
    LOGE("Unsupported URI scheme: %s", uri);
    return false;
}

// 新增：重新配置音频流
bool AudioEngine::reconfigureStream(int32_t sampleRate, int32_t channelCount) {
    // 关闭现有流（如果存在）
    if (mPlaybackStream) {
        mPlaybackStream->stop();
        mPlaybackStream.reset();
    }
    
    // 创建新流
    oboe::AudioStreamBuilder builder;
    oboe::Result result = builder.setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(channelCount)
        ->setSampleRate(sampleRate)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Exclusive)
        ->setCallback(this)
        ->openManagedStream(mPlaybackStream);
        
    if (result != oboe::Result::OK) {
        LOGE("Failed to reconfigure audio stream: %s", oboe::convertToText(result));
        return false;
    }
    
    mSampleRate.store(mPlaybackStream->getSampleRate());
    mChannels.store(mPlaybackStream->getChannelCount());
    LOGD("Audio stream reconfigured with sample rate: %d, channels: %d", mSampleRate.load(), mChannels.load());
    return true;
}

bool AudioEngine::loadWithSndfile(const std::string& filePath) {
    LOGD("Loading audio file with libsndfile: %s", filePath.c_str());

    SF_INFO sfInfo;
    memset(&sfInfo, 0, sizeof(SF_INFO));

    // 验证文件路径
    if (filePath.empty()) {
        LOGE("Invalid file path: empty string");
        return false;
    }

    SNDFILE* sndfile = sf_open(filePath.c_str(), SFM_READ, &sfInfo);
    if (!sndfile) {
        LOGE("Failed to open audio file with libsndfile: %s", filePath.c_str());
        // 检查常见的系统错误
        int err = sf_error(NULL);
        switch (err) {
            case SF_ERR_SYSTEM:
                LOGE("System error: File not found or permission denied.");
                break;
            case SF_ERR_UNSUPPORTED_ENCODING:
                LOGE("File encoding is not supported by libsndfile.");
                break;
            default: {
                const char* errorStr = sf_strerror(NULL);
                if (errorStr) {
                    LOGE("libsndfile error: %s", errorStr);
                } else {
                    LOGE("Unknown libsndfile error code: %d", err);
                }
            }
        }
        return false;
    }

    LOGD("Audio file info - Sample rate: %d, Channels: %d, Frames: %ld, Format: 0x%X",
         sfInfo.samplerate, sfInfo.channels, sfInfo.frames, sfInfo.format);

    // 检查是否是支持的格式
    if (sfInfo.frames <= 0) {
        LOGE("Audio file has no frames or invalid format: %ld frames", static_cast<long>(sfInfo.frames));
        sf_close(sndfile);
        return false;
    }

    if (sfInfo.samplerate <= 0) {
        LOGE("Invalid sample rate: %d", sfInfo.samplerate);
        sf_close(sndfile);
        return false;
    }

    if (sfInfo.channels <= 0) {
        LOGE("Invalid channel count: %d", sfInfo.channels);
        sf_close(sndfile);
        return false;
    }
    if (sfInfo.channels > 8) {
        LOGW("High channel count detected: %d. This might cause performance issues.", sfInfo.channels);
        // 继续加载，但记录警告
    }

    // 读取所有音频数据
    sf_count_t totalFrames = sfInfo.frames;
    size_t totalSamples = static_cast<size_t>(totalFrames) * static_cast<size_t>(sfInfo.channels);

    // 检查内存分配是否会溢出
    if (totalSamples == 0 || totalSamples > SIZE_MAX / sizeof(float)) {
        LOGE("Memory allocation would overflow for audio data");
        sf_close(sndfile);
        return false;
    }

    std::vector<float> rawData;
    try {
        rawData.resize(totalSamples);
    } catch (const std::bad_alloc& e) {
        LOGE("Failed to allocate memory for audio data. Requested samples: %zu, Error: %s", totalSamples, e.what());
        sf_close(sndfile);
        return false;
    }

    sf_count_t framesRead = sf_readf_float(sndfile, rawData.data(), totalFrames);
    if (framesRead < 0) {
        LOGE("Error reading audio data: %s", sf_strerror(sndfile));
        sf_close(sndfile);
        return false;
    }

    if (framesRead != totalFrames) {
        LOGW("Partial audio data read. Expected: %ld, Read: %ld",
             static_cast<long>(totalFrames), static_cast<long>(framesRead));
        // 继续处理已读取的数据而不是完全失败
        totalFrames = framesRead;
    }

    sf_close(sndfile);

    // Reconfigure stream to match source file format
    if (!reconfigureStream(sfInfo.samplerate, sfInfo.channels)) {
        LOGE("Failed to reconfigure stream for source file");
        return false;
    }

    // 获取音频流的实际采样率和通道数
    int32_t actualSampleRate = mSampleRate.load();
    int32_t actualChannelCount = mChannels.load();

    // 重采样处理：当文件采样率与流实际采样率不匹配时
    if (actualSampleRate > 0 && sfInfo.samplerate != actualSampleRate) {
        double resampleFactor = static_cast<double>(actualSampleRate) / sfInfo.samplerate;
        LOGD("Resampling audio from %d to %d (factor: %.2f)",
             sfInfo.samplerate, actualSampleRate, resampleFactor);

        // 整数倍上采样 - 保持时长不变
        if (resampleFactor > 1.0 && std::floor(resampleFactor) == resampleFactor) {
            int factor = static_cast<int>(resampleFactor);
            std::vector<float> resampledData;

            // 计算新的总帧数（保持时长不变）
            size_t newTotalFrames = static_cast<size_t>(totalFrames * factor);
            size_t newTotalSamples = newTotalFrames * sfInfo.channels;
            resampledData.reserve(newTotalSamples);

            // 对每个原始帧进行处理
            for (size_t frame = 0; frame < totalFrames - 1; frame++) {
                size_t currentIndex = frame * sfInfo.channels;
                size_t nextIndex = (frame + 1) * sfInfo.channels;

                // 对于每对相邻帧，插入factor-1个插值帧
                for (int j = 0; j < factor; j++) {
                    float alpha = static_cast<float>(j) / factor;

                    for (int ch = 0; ch < sfInfo.channels; ch++) {
                        float current = rawData[currentIndex + ch];
                        float next = rawData[nextIndex + ch];
                        float interpolated = current + alpha * (next - current);
                        resampledData.push_back(interpolated);
                    }
                }
            }

            // 处理最后一帧（没有下一帧可插值）
            for (int ch = 0; ch < sfInfo.channels; ch++) {
                resampledData.push_back(rawData[(totalFrames - 1) * sfInfo.channels + ch]);
            }

            mAudioData = std::move(resampledData);
            // 时长保持不变，因为采样率提高了
            mDuration = (static_cast<int64_t>(totalFrames) * 1000) / sfInfo.samplerate;
            LOGD("Resampled audio duration: %ld ms (unchanged)", static_cast<long>(mDuration.load()));
        } else if (resampleFactor < 1.0 && std::floor(1.0/resampleFactor) == (1.0/resampleFactor)) {
            // 处理下采样（原始采样率是目标采样率的整数倍）
            int factor = static_cast<int>(1.0 / resampleFactor);
            std::vector<float> resampledData;
            size_t newSize = rawData.size() / factor;
            resampledData.reserve(newSize);

            for (size_t i = 0; i < rawData.size(); i += factor * sfInfo.channels) {
                for (int ch = 0; ch < sfInfo.channels; ch++) {
                    size_t index = i + ch;
                    if (index < rawData.size()) {
                        resampledData.push_back(rawData[index]);
                    }
                }
            }

            mAudioData = std::move(resampledData);
            mDuration = (static_cast<int64_t>(mAudioData.size() / sfInfo.channels) * 1000) / actualSampleRate;
            LOGD("Resampled audio duration: %ld ms", static_cast<long>(mDuration.load()));
        } else {
            // 非整数倍，使用线性插值重采样
            LOGD("Non-integer resampling factor: %.2f, performing linear interpolation", resampleFactor);
            size_t newTotalFrames = static_cast<size_t>(totalFrames * resampleFactor);
            size_t newTotalSamples = newTotalFrames * sfInfo.channels;
            std::vector<float> resampledData;
            resampledData.reserve(newTotalSamples);

            for (size_t targetFrame = 0; targetFrame < newTotalFrames; targetFrame++) {
                double sourceFrame = static_cast<double>(targetFrame) / resampleFactor;
                size_t srcIdx0 = static_cast<size_t>(sourceFrame) * sfInfo.channels;
                size_t srcIdx1 = srcIdx0 + sfInfo.channels;

                if (srcIdx1 >= rawData.size()) srcIdx1 = srcIdx0; // clamp at end

                double frac = sourceFrame - std::floor(sourceFrame);

                for (int ch = 0; ch < sfInfo.channels; ch++) {
                    float s0 = rawData[srcIdx0 + ch];
                    float s1 = rawData[srcIdx1 + ch];
                    resampledData.push_back(static_cast<float>(s0 + frac * (s1 - s0)));
                }
            }

            mAudioData = std::move(resampledData);
            mDuration = (static_cast<int64_t>(mAudioData.size() / sfInfo.channels) * 1000) / actualSampleRate;
            LOGD("Resampled audio duration: %ld ms", static_cast<long>(mDuration.load()));
        }
    } else {
        // 采样率相同，直接使用
        mAudioData = std::move(rawData);
        mDuration = (static_cast<int64_t>(mAudioData.size() / sfInfo.channels) * 1000) / actualSampleRate;
    }

    // 更新采样率和通道数为实际值
    mSampleRate.store(actualSampleRate);
    mChannels.store(actualChannelCount);

    mIsLoaded = true;
    mDataPosition.store(0);

    LOGD("Successfully loaded audio file, duration: %ld ms, sample rate: %d, channels: %d",
         static_cast<long>(mDuration.load()), mSampleRate.load(), mChannels.load());
    return true;
}

bool AudioEngine::play() {
    LOGD("Playing audio");
    if (!mPlaybackStream) {
        LOGE("Playback stream is null");
        return false;
    }
    
    if (!mIsLoaded) {
        LOGE("No audio loaded");
        return false;
    }

    oboe::StreamState state = mPlaybackStream->getState();
    if (state == oboe::StreamState::Started || state == oboe::StreamState::Starting) {
        LOGW("Stream is already started or starting. No need to start again.");
        mIsPlaying = true;  // 同步内部状态
        return true;
    }
    
    if (!mIsPlaying) {
        oboe::Result result = mPlaybackStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("Failed to start audio stream: %s", oboe::convertToText(result));
            return false;
        }
        mIsPlaying = true;
    }
    return true;
}

bool AudioEngine::pause() {
    LOGD("Pausing audio");
    if (mIsPlaying && mPlaybackStream) {
        oboe::Result result = mPlaybackStream->requestPause();
        if (result != oboe::Result::OK) {
            LOGE("Failed to pause audio stream: %s", oboe::convertToText(result));
            return false;
        }
        mIsPlaying = false;
    }
    return true;
}

bool AudioEngine::stop() {
    LOGD("Stopping audio");
    if (mPlaybackStream) {
        mPlaybackStream->stop();
        mIsPlaying = false;
        mPosition = 0;
        mDataPosition.store(0);
    }
    return true;
}

void AudioEngine::seekTo(int64_t position) {
    LOGD("Seeking to position: %ld", static_cast<long>(position));

    if (!mIsLoaded) {
        LOGW("Cannot seek: no audio loaded");
        return;
    }

    // 确保位置不为负数
    int64_t clampedPosition = position < 0 ? 0 : position;

    // 如果位置超过持续时间，则限制在结尾
    if (clampedPosition > mDuration) {
        LOGD("Seek position %ld exceeds duration %ld, clamping to end",
             static_cast<long>(position), static_cast<long>(mDuration.load()));
        clampedPosition = mDuration;
    }

    mPosition = clampedPosition;

    // 根据position计算dataPosition，考虑重采样比例
    int32_t sampleRate = mSampleRate.load();
    int32_t channels = mChannels.load();
    if (sampleRate > 0 && channels > 0) {
        // 获取当前流的采样率（可能是重采样后的）
        int32_t actualSampleRate = mPlaybackStream ? mPlaybackStream->getSampleRate() : sampleRate;

        // 计算重采样比例
        double resampleRatio = 1.0;
        if (sampleRate > 0 && actualSampleRate > 0) {
            resampleRatio = static_cast<double>(actualSampleRate) / sampleRate;
        }

        // 应用重采样比例计算数据位置
        size_t newPos = static_cast<size_t>((clampedPosition * sampleRate * channels * resampleRatio) / 1000);

        // 确保dataPosition不超过缓冲区大小
        {
            std::lock_guard<std::mutex> lock(mAudioDataMutex);
            if (newPos > mAudioData.size()) {
                LOGW("Calculated data position %zu exceeds buffer size %zu, clamping",
                     newPos, mAudioData.size());
                newPos = mAudioData.size();
            }
        }
        mDataPosition.store(newPos);
    } else {
        LOGE("Invalid audio parameters for seeking: sample rate=%d, channels=%d",
             sampleRate, channels);
        mDataPosition.store(0);
    }
}

int64_t AudioEngine::getPosition() {
    return mPosition;
}

int64_t AudioEngine::getDuration() {
    return mDuration;
}

bool AudioEngine::isPlaying() {
    return mIsPlaying;
}

void AudioEngine::setVolume(float volume) {
    mVolume.store(volume);
}

void AudioEngine::setSpeed(float speed) {
    mSpeed.store(speed);
}

void AudioEngine::setPositionCallback(JNIEnv* env, jobject callback) {
    // 清除之前的全局引用
    if (mPositionCallback) {
        env->DeleteGlobalRef(mPositionCallback);
        mPositionCallback = nullptr;
    }
    if (callback) {
        // 获取 JavaVM 并创建全局引用
        env->GetJavaVM(&mJvm);
        mPositionCallback = env->NewGlobalRef(callback);
    }
}

void AudioEngine::clearPositionCallback() {
    if (mJvm && mPositionCallback) {
        JNIEnv* env;
        if (mJvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            env->DeleteGlobalRef(mPositionCallback);
        }
        mPositionCallback = nullptr;
        mJvm = nullptr;
    }
}

void AudioEngine::dispose() {
    LOGD("Disposing audio engine");
    if (mPlaybackStream) {
        mPlaybackStream->stop();
        mPlaybackStream.reset();
    }
    mIsPlaying = false;
    mPosition = 0;
    mDuration = 0;
    mAudioData.clear();
    mDataPosition.store(0);
    mIsLoaded = false;
}

oboe::DataCallbackResult AudioEngine::onAudioReady(oboe::AudioStream *oboeStream,
                                                   void *audioData,
                                                   int32_t numFrames) {
    if (!mIsLoaded) {
        // 如果没有加载音频，则填充静音数据
        auto *outputBuffer = static_cast<float*>(audioData);
        size_t totalFrames = numFrames * oboeStream->getChannelCount();
        for (size_t i = 0; i < totalFrames; i++) {
            outputBuffer[i] = 0.0f;
        }
        return oboe::DataCallbackResult::Continue;
    }

    std::lock_guard<std::mutex> lock(mAudioDataMutex);
    if (mAudioData.empty()) {
        auto *outputBuffer = static_cast<float*>(audioData);
        size_t totalFrames = numFrames * oboeStream->getChannelCount();
        for (size_t i = 0; i < totalFrames; i++) {
            outputBuffer[i] = 0.0f;
        }
        return oboe::DataCallbackResult::Continue;
    }

    auto *outputBuffer = static_cast<float*>(audioData);
    int32_t outputChannels = oboeStream->getChannelCount();
    size_t totalOutputFrames = numFrames * outputChannels;

    // 清空输出缓冲区作为默认值
    for (size_t i = 0; i < totalOutputFrames; i++) {
        outputBuffer[i] = 0.0f;
    }

    // 安全计算可写入的帧数，防止整数溢出和越界
    int32_t channels = mChannels.load();
    if (channels == 0) {
        LOGE("Invalid mChannels value: %d", channels);
        return oboe::DataCallbackResult::Stop;
    }

    size_t dataPos = mDataPosition.load();
    size_t maxReadableFrames = mAudioData.size() / static_cast<size_t>(channels);
    size_t framesAvailable = maxReadableFrames > dataPos / static_cast<size_t>(channels) ?
                             maxReadableFrames - dataPos / static_cast<size_t>(channels) : 0;
    size_t framesToWrite = std::min(static_cast<size_t>(numFrames), framesAvailable);

    float volume = mVolume.load();
    float speed = mSpeed.load();

    // 数据填充循环
    for (size_t frame = 0; frame < framesToWrite; frame++) {
        for (int32_t channel = 0; channel < outputChannels; channel++) {
            // 确保源索引不越界
            size_t sourceIndex = dataPos + frame * static_cast<size_t>(channels);
            if (sourceIndex >= mAudioData.size()) {
                LOGE("Source index out of bounds: %zu >= %zu", sourceIndex, mAudioData.size());
                break;
            }

            // 处理通道映射：如果源通道少于目标通道，复制左声道；如果多于，则截断
            int sourceChannel = channel < channels ? channel : (channels - 1);
            if (sourceIndex + sourceChannel >= mAudioData.size()) {
                LOGW("Source channel index out of bounds, using first channel");
                sourceChannel = 0;
            }

            float sample = mAudioData[sourceIndex + sourceChannel];
            if (volume != 1.0f) {
                sample *= volume;
            }
            outputBuffer[frame * outputChannels + channel] = sample;
        }
    }

    // 更新位置（根据speed调整advance量）
    size_t samplesWritten = framesToWrite * static_cast<size_t>(channels);
    size_t advance = samplesWritten;
    if (speed != 1.0f && speed > 0.0f) {
        advance = static_cast<size_t>(samplesWritten * speed);
    }
    size_t newDataPos = dataPos + advance;
    if (newDataPos > mAudioData.size()) {
        newDataPos = mAudioData.size();
    }
    mDataPosition.store(newDataPos);

    if (mIsPlaying) {
        // 由于音频数据已经重采样到与流匹配的采样率，直接使用流的采样率计算位置
        int32_t actualSampleRate = oboeStream->getSampleRate();
        double millisecondsPerFrame = 1000.0 / actualSampleRate;
        mPosition += static_cast<int64_t>(framesToWrite * millisecondsPerFrame);

        // 位置推送：每隔约100ms通过JNI回调推送到Java
        if (mJvm && mPositionCallback) {
            int64_t currentTime = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            if (currentTime - mLastPositionUpdateTime >= 100) {
                JNIEnv* env = nullptr;
                int getEnvStat = mJvm->GetEnv((void**)&env, JNI_VERSION_1_6);
                if (getEnvStat == JNI_EDETACHED) {
                    if (mJvm->AttachCurrentThread(&env, nullptr) != 0) {
                        LOGE("Failed to attach current thread to JVM");
                    }
                }
                if (env) {
                    jclass callbackClass = env->GetObjectClass(mPositionCallback);
                    jmethodID methodId = env->GetMethodID(callbackClass, "onPositionUpdate", "(J)V");
                    if (methodId) {
                        env->CallVoidMethod(mPositionCallback, methodId, static_cast<jlong>(mPosition.load()));
                    }
                    if (getEnvStat == JNI_EDETACHED) {
                        mJvm->DetachCurrentThread();
                    }
                    mLastPositionUpdateTime = currentTime;
                }
            }
        }
    }

    // 检查是否播放完毕
    if (mDataPosition.load() >= mAudioData.size()) {
        mIsPlaying = false;
        mPosition.store(mDuration.load());
    }

    return oboe::DataCallbackResult::Continue;
}

// JNI接口实现
extern "C" {

JNIEXPORT jlong JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeCreateEngine(JNIEnv *env, jobject thiz) {
    LOGD("Creating audio engine from JNI");
    AudioEngine* engine = new AudioEngine();
    if (engine->init()) {
        return reinterpret_cast<jlong>(engine);
    } else {
        delete engine;
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeDisposeEngine(JNIEnv *env, jobject thiz, jlong engineHandle) {
    LOGD("Disposing audio engine from JNI");
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (engine) {
        engine->dispose();
        delete engine;
    }
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeLoad(JNIEnv *env, jobject thiz, jlong engineHandle, jstring uri) {
    LOGD("Loading audio from JNI");
    
    if (!uri) {
        LOGE("Null URI passed to nativeLoad");
        return JNI_FALSE;
    }
    
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        LOGE("Invalid engine handle in nativeLoad");
        return JNI_FALSE;
    }
    
    const char* uriStr = env->GetStringUTFChars(uri, nullptr);
    if (!uriStr) {
        LOGE("Failed to get UTF chars from JNI string");
        return JNI_FALSE;
    }
    
    LOGD("Attempting to load URI: %s", uriStr);
    
    bool result = engine->load(uriStr);
    
    env->ReleaseStringUTFChars(uri, uriStr);
    
    LOGD("Load operation result: %s", result ? "success" : "failure");
    
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativePlay(JNIEnv *env, jobject thiz, jlong engineHandle) {
    LOGD("Playing audio from JNI");
    
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        LOGE("Invalid engine handle in nativePlay");
        return JNI_FALSE;
    }
    
    bool result = engine->play();
    LOGD("Play operation result: %s", result ? "success" : "failure");
    
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativePause(JNIEnv *env, jobject thiz, jlong engineHandle) {
    LOGD("Pausing audio from JNI");
    
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        LOGE("Invalid engine handle in nativePause");
        return JNI_FALSE;
    }
    
    bool result = engine->pause();
    LOGD("Pause operation result: %s", result ? "success" : "failure");
    
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeStop(JNIEnv *env, jobject thiz, jlong engineHandle) {
    LOGD("Stopping audio from JNI");
    
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        LOGE("Invalid engine handle in nativeStop");
        return JNI_FALSE;
    }
    
    bool result = engine->stop();
    LOGD("Stop operation result: %s", result ? "success" : "failure");
    
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeSeekTo(JNIEnv *env, jobject thiz, jlong engineHandle, jlong position) {
    LOGD("Seeking to position from JNI: %ld", static_cast<long>(position));
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        return JNI_FALSE;
    }
    
    engine->seekTo(position);
    return JNI_TRUE;
}

JNIEXPORT jlong JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeGetPosition(JNIEnv *env, jobject thiz, jlong engineHandle) {
//    LOGD("Getting position from JNI");  // 会刷屏的机霸日志，在DEBUG时酌情启用
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        return -1;
    }
    
    return engine->getPosition();
}

JNIEXPORT jlong JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeGetDuration(JNIEnv *env, jobject thiz, jlong engineHandle) {
//    LOGD("Getting duration from JNI");
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        return -1;
    }
    
    return engine->getDuration();
}

JNIEXPORT jboolean JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeIsPlaying(JNIEnv *env, jobject thiz, jlong engineHandle) {
    LOGD("Checking if playing from JNI");
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (!engine) {
        return JNI_FALSE;
    }
    
    return engine->isPlaying() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeSetVolume(JNIEnv *env, jobject thiz, jlong engineHandle, jfloat volume) {
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (engine) {
        engine->setVolume(static_cast<float>(volume));
    }
}

JNIEXPORT void JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeSetSpeed(JNIEnv *env, jobject thiz, jlong engineHandle, jfloat speed) {
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (engine) {
        engine->setSpeed(static_cast<float>(speed));
    }
}

JNIEXPORT void JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeSetPositionCallback(JNIEnv *env, jobject thiz, jlong engineHandle, jobject callback) {
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (engine) {
        engine->setPositionCallback(env, callback);
    }
}

JNIEXPORT void JNICALL
Java_github_naivg_just_1aaudio_AAudioPlayer_nativeClearPositionCallback(JNIEnv *env, jobject thiz, jlong engineHandle) {
    AudioEngine* engine = reinterpret_cast<AudioEngine*>(engineHandle);
    if (engine) {
        engine->clearPositionCallback();
    }
}

}