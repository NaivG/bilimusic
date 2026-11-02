/**
 * Copyright (c) 2025 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import { BinaryMessenger, Log, MethodCall } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Context } from '@kit.AbilityKit';
import audio from '@ohos.multimedia.audio';
import { ArrayList, JSON, List } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'OhosAudioManager';
const ERR_INVALID_ARGS = 'InvalidArgs';
const ERR_AUDIO_SESSION = 'AudioSessionError';

export default class OhosAudioManager implements MethodCallHandler {
  private static sharedInstance: Singleton | null = null;
  private messenger : BinaryMessenger | null;
  public channel : MethodChannel | null;
  private singleton : Singleton | null = null;

  constructor(applicationContext: Context, messenger: BinaryMessenger) {
    if(OhosAudioManager.sharedInstance == null) {
      OhosAudioManager.sharedInstance = new Singleton(applicationContext);
    }
    this.singleton = OhosAudioManager.sharedInstance;
    this.messenger = messenger;
    this.channel = new MethodChannel(messenger, 'com.ryanheise.ohos_audio_manager');
    this.singleton.add(this);
    this.channel.setMethodCallHandler(this);
  }

  /** 将 Flutter MethodChannel 单值或数组参数统一为 Array。 */
  private static normalizeArgs(raw: ESObject): Array<ESObject> {
    if (raw == null || raw == undefined) {
      return [];
    }
    if (Array.isArray(raw)) {
      return raw as Array<ESObject>;
    }
    let out: ESObject[] = [];
    out.push(raw);
    return out;
  }

  private static requireArgs(args: Array<ESObject>, minLen: number, method: string,
    result: MethodResult): boolean {
    if (args.length < minLen) {
      result.error(ERR_INVALID_ARGS, method + ' requires at least ' + minLen + ' argument(s)', null);
      return false;
    }
    return true;
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      const args: Array<ESObject> = OhosAudioManager.normalizeArgs(call.args);
      Log.i(TAG, 'onMethodCall: ' + call.method + ' args: ' + JSON.stringify(args));
      switch (call.method) {
        case 'setActive': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setActive', result)) {
            break;
          }
          if (this.singleton == null) {
            result.error(ERR_AUDIO_SESSION, 'singleton is null', null);
            break;
          }
          this.singleton.setActive(args, result);
          break;
        }
        case 'dispatchMediaKeyEvent': {
          this.singleton?.dispatchMediaKeyEvent(call.args, result);
          break;
        }
        case 'isVolumeUnadjustable': {
          result.success(this.singleton?.isVolumeUnadjustable());
          break;
        }
        case 'adjustStreamVolume': {
          if (!OhosAudioManager.requireArgs(args, 3, 'adjustStreamVolume', result)) {
            break;
          }
          this.singleton?.adjustStreamVolume(args[0] as number, args[1] as number, args[2] as number, result);
          break;
        }
        case 'adjustVolume': {
          if (!OhosAudioManager.requireArgs(args, 2, 'adjustVolume', result)) {
            break;
          }
          this.singleton?.adjustVolume(args[0] as number, args[1] as number, result);
          break;
        }
        case 'adjustSuggestedStreamVolume': {
          if (!OhosAudioManager.requireArgs(args, 3, 'adjustSuggestedStreamVolume', result)) {
            break;
          }
          this.singleton?.adjustSuggestedStreamVolume(args[0] as number, args[1] as number,
            args[2] as number, result);
          break;
        }
        case 'getRingerMode': {
          result.success(this.singleton?.getRingerMode());
          break;
        }
        case 'getMaxVolume': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getMaxVolume', result)) {
            break;
          }
          result.success(this.singleton?.getMaxVolume(args[0] as number));
          break;
        }
        case 'getMinVolume': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getMinVolume', result)) {
            break;
          }
          result.success(this.singleton?.getMinVolume(args[0] as number));
          break;
        }
        case 'getVolume': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getVolume', result)) {
            break;
          }
          result.success(this.singleton?.getVolume(args[0] as number));
          break;
        }
        case 'getSystemVolumeInDb': {
          // Dart 仅发送 streamType；内部用当前音量等级 + SPEAKER 补齐 OHOS 三参 API
          if (!OhosAudioManager.requireArgs(args, 1, 'getSystemVolumeInDb', result)) {
            break;
          }
          result.success(this.singleton?.getSystemVolumeInDb(args[0] as number));
          break;
        }
        case 'setRingerMode': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setRingerMode', result)) {
            break;
          }
          this.singleton?.setRingerMode(args[0] as number, result);
          break;
        }
        case 'setStreamVolume': {
          if (!OhosAudioManager.requireArgs(args, 3, 'setStreamVolume', result)) {
            break;
          }
          this.singleton?.setStreamVolume(args[0] as number, args[1] as number, args[2] as number, result);
          break;
        }
        case 'isMute': {
          if (!OhosAudioManager.requireArgs(args, 1, 'isMute', result)) {
            break;
          }
          result.success(this.singleton?.isMute(args[0] as number));
          break;
        }
        case 'getAvailableCommunicationDevices': {
          result.success(this.singleton?.getAvailableCommunicationDevices());
          break;
        }
        case 'setCommunicationDevice': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setCommunicationDevice', result)) {
            break;
          }
          this.singleton?.setCommunicationDevice(args[0] as number, result);
          break;
        }
        case 'getCommunicationDevice': {
          result.success(this.singleton?.getCommunicationDevice());
          break;
        }
        case 'clearCommunicationDevice': {
          this.singleton?.clearCommunicationDevice(result);
          break;
        }
        case 'setSpeakerphoneOn': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setSpeakerphoneOn', result)) {
            break;
          }
          this.singleton?.setSpeakerphoneOn(args[0] as boolean, result);
          break;
        }
        case 'isSpeakerphoneOn': {
          result.success(this.singleton?.isSpeakerphoneOn());
          break;
        }
        case 'setAllowedCapturePolicy': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setAllowedCapturePolicy', result)) {
            break;
          }
          this.singleton?.setAllowedCapturePolicy(args[0] as number, result);
          break;
        }
        case 'getAllowedCapturePolicy': {
          this.singleton?.getAllowedCapturePolicy(result);
          break;
        }
        case 'isBluetoothScoAvailableOffCall': {
          this.singleton?.isBluetoothScoAvailableOffCall(result);
          break;
        }
        case 'startBluetoothSco': {
          this.singleton?.startBluetoothSco(result);
          break;
        }
        case 'stopBluetoothSco': {
          this.singleton?.stopBluetoothSco(result);
          break;
        }
        case 'setBluetoothScoOn': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setBluetoothScoOn', result)) {
            break;
          }
          this.singleton?.setBluetoothScoOn(args[0] as boolean, result);
          break;
        }
        case 'isBluetoothScoOn': {
          this.singleton?.isBluetoothScoOn(result);
          break;
        }
        case 'setMicrophoneMute': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setMicrophoneMute', result)) {
            break;
          }
          this.singleton?.setMicrophoneMute(args[0] as boolean, result);
          break;
        }
        case 'isMicrophoneMute': {
          result.success(this.singleton?.isMicrophoneMute());
          break;
        }
        case 'setMode': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setMode', result)) {
            break;
          }
          this.singleton?.setMode(args[0] as number, result);
          break;
        }
        case 'getAudioScene': {
          result.success(this.singleton?.getAudioScene());
          break;
        }
        case 'isMusicActive': {
          result.success(this.singleton?.isMusicActive());
          break;
        }
        case 'generateAudioSessionId': {
          this.singleton?.generateAudioSessionId(result);
          break;
        }
        case 'setAudioParameter': {
          if (!OhosAudioManager.requireArgs(args, 2, 'setAudioParameter', result)) {
            break;
          }
          this.singleton?.setAudioParameter(args[0] as string, args[1] as string, result);
          break;
        }
        case 'getAudioParameter': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getAudioParameter', result)) {
            break;
          }
          this.singleton?.getAudioParameter(args[0] as string, result);
          break;
        }
        case 'getProperty': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getProperty', result)) {
            break;
          }
          this.singleton?.getProperty(args[0] as string, result);
          break;
        }
        case 'getDevices': {
          if (!OhosAudioManager.requireArgs(args, 1, 'getDevices', result)) {
            break;
          }
          result.success(this.singleton?.getDevices(args[0] as number));
          break;
        }
        case 'getMicrophones': {
          result.success(this.singleton?.getMicrophones());
          break;
        }
        case 'isHapticPlaybackSupported': {
          result.success(this.singleton?.isHapticPlaybackSupported());
          break;
        }
        case 'setInterruptionEventListener': {
          if (!OhosAudioManager.requireArgs(args, 1, 'setInterruptionEventListener', result)) {
            break;
          }
          if (this.singleton == null) {
            result.error(ERR_AUDIO_SESSION, 'singleton is null', null);
            break;
          }
          this.singleton.setInterruptionEventListener(args[0] as Map<string, ESObject>, result);
          break;
        }
        default: {
          result.notImplemented();
          break;
        }
      }
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'onMethodCall failed: code=' + error.code + ' message=' + error.message);
      result.error(ERR_AUDIO_SESSION, 'onMethodCall failed: ' + error.message, null);
    }
  }

  public dispose(): void {
    this.channel?.setMethodCallHandler(null);
    this.singleton?.remove(this);
    if(this.singleton?.isEmpty()) {
      this.singleton?.dispose();
      this.singleton = null;
      OhosAudioManager.sharedInstance = null;
    } else {
      this.singleton = null;
    }
    this.channel = null;
    this.messenger = null;
  }

  /**
   * 仅释放系统级事件监听（deviceChange / audioSessionDeactivated），保留 MethodChannel 与实例注册。
   * 用于 Ability 生命周期分离场景（engine 仍存活），避免循环引用导致 Singleton 无法回收。
   */
  public releaseSystemListeners(): void {
    this.singleton?.releaseListeners();
  }

  /** Ability 重新绑定时恢复 deviceChange 等系统级监听。 */
  public ensureSystemListeners(): void {
    this.singleton?.ensureListeners();
  }

}

class Singleton {
  private instances: OhosAudioManager[];
  private applicationContext: Context | null;
  private audioManager: audio.AudioManager | null;
  private audioDeviceDescriptors: audio.AudioDeviceDescriptors | undefined;
  private audioActive: boolean = false;
  private audioSessionManager: audio.AudioSessionManager | null = null;
  // 保存回调引用，便于精确 off() 并打破循环引用；标志位追踪订阅状态，避免重复注册
  private deviceChangeCallback: ((device: audio.DeviceChangeAction) => void) | null = null;
  private interruptionCallback: ((event: audio.AudioSessionDeactivatedEvent) => void) | null = null;
  private isInterruptionListenerActive: boolean = false;
  // Dart setInterruptionEventListener 传入的 audioAttributes，供会话激活时使用
  private pendingAudioAttributes: Map<string, ESObject> | null = null;
  private pendingRendererOptions: audio.AudioRendererOptions | null = null;

  constructor(applicationContext: Context) {
    this.instances = [];
    this.applicationContext = applicationContext;
    this.audioDeviceDescriptors = undefined;
    try {
      this.audioManager = audio.getAudioManager();
      this.initAudioDeviceCallback();
    } catch (err) {
      Log.e(TAG, 'Singleton init failed: ' + err);
      this.audioManager = null;
    }
  }

  private initAudioDeviceCallback(): void {
    if (this.audioManager == null) {
      return;
    }
    // 已注册则跳过，避免重复 on()
    if (this.deviceChangeCallback != null) {
      return;
    }
    // 用 self 引用，配合 dispose 时 off+null 打破循环引用
    let self = this;
    let callback = (device: audio.DeviceChangeAction) => {
      try {
        if (device.type == audio.DeviceChangeType.CONNECT) {
          self.invokeMethod('onAudioDevicesAdded', self.encodeAudioDevices(device.deviceDescriptors));
        } else if (device.type == audio.DeviceChangeType.DISCONNECT) {
          self.invokeMethod('onAudioDevicesRemoved', self.encodeAudioDevices(device.deviceDescriptors));
        }
      } catch (err) {
        Log.e(TAG, 'deviceChange callback failed: ' + err);
      }
    };
    this.deviceChangeCallback = callback;
    try {
      this.audioManager.getRoutingManager().on('deviceChange', audio.DeviceFlag.ALL_DEVICES_FLAG,
        callback);
    } catch (err) {
      Log.e(TAG, 'initAudioDeviceCallback on failed: ' + err);
      this.deviceChangeCallback = null;
    }
  }

  private encodeAudioDevices(devices: audio.AudioDeviceDescriptors): Map<string, ESObject>[] {
    let result: Map<string, ESObject>[] = [];
    for(let i = 0; i < devices.length; i++) {
      result.push(this.encodeAudioDevice(devices[i]));
    }
    return result;
  }

  private encodeAudioDevice(device: audio.AudioDeviceDescriptor): Map<string, ESObject> {
    let deviceMap: Map<string, ESObject> = new Map();
    deviceMap.set('deviceRole', device.deviceRole);
    deviceMap.set('deviceType', device.deviceType);
    deviceMap.set('id', device.id);
    deviceMap.set('name', device.name);
    deviceMap.set('address', device.address);
    deviceMap.set('sampleRates', device.sampleRates);
    deviceMap.set('channelMasks', device.channelMasks);
    deviceMap.set('displayName', device.displayName);
    // OHOS AudioDeviceDescriptor 无 channelIndexMasks；勿误用 channelMasks
    let emptyIndexMasks: number[] = [];
    deviceMap.set('channelIndexMasks', emptyIndexMasks);
    deviceMap.set('channelCounts', device.channelCounts);
    if (device.encodingTypes != null && device.encodingTypes != undefined) {
      deviceMap.set('encodingTypes', device.encodingTypes);
    }
    return deviceMap;
  }

  private decodeAudioRendererOptions(attributes: Map<string, ESObject>): audio.AudioRendererOptions | null {
    if(!attributes.has('sampleRate') || !attributes.has('channels') || !attributes.has('sampleFormat')
      || !attributes.has('encodingType') || !attributes.has('streamUsage')) {
      return null;
    }
    let audioStreamInfo: audio.AudioStreamInfo = {
      samplingRate: attributes.get('sampleRate') as audio.AudioSamplingRate,
      channels: attributes.get('channels') as audio.AudioChannel,
      sampleFormat: attributes.get('sampleFormat') as audio.AudioSampleFormat,
      encodingType: attributes.get('encodingType') as audio.AudioEncodingType,
    };
    let audioRendererInfo: audio.AudioRendererInfo = {
      usage: attributes.get('streamUsage') as audio.StreamUsage,
      rendererFlags: 0,
    };
    let audioRendererOptions: audio.AudioRendererOptions = {
      streamInfo: audioStreamInfo,
      rendererInfo: audioRendererInfo,
    };
    return audioRendererOptions;
  }

  private decodeAudioConcurrencyMode(mode: ESObject): audio.AudioConcurrencyMode {
    if(mode) {
      return mode as audio.AudioConcurrencyMode;
    }
    return audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT;
  }

  public add(manager: OhosAudioManager): void {
    this.instances.push(manager);
  }
  public remove(manager: OhosAudioManager): void {
    const index = this.instances.indexOf(manager);
    if(index != -1) {
      this.instances.splice(index, 1);
    }
  }

  public isEmpty() {
    return this.instances.length == 0;
  }

  public dispose(): void {
    // 1. 取消所有事件监听（按 on/off 对称原则，传入具体回调引用）
    this.releaseListeners();
    // 2. 清空实例列表
    this.instances = [];
    // 3. 释放系统资源
    this.audioDeviceDescriptors = undefined;
    this.pendingAudioAttributes = null;
    this.pendingRendererOptions = null;
    // 4. 释放上下文
    this.applicationContext = null;
    this.audioManager = null;
  }

  /**
   * 释放系统级事件监听并清除回调引用，打破循环引用。
   * 与 dispose() 不同，保留 instances / audioManager / applicationContext，供 engine 仍存活场景继续使用。
   */
  public releaseListeners(): void {
    this.disposeAudioDeviceCallback();
    this.disposeAudioSessionCallback();
  }

  /** Ability 重建后恢复 deviceChange 监听（interruption 由 Dart 按需重新注册）。 */
  public ensureListeners(): void {
    this.initAudioDeviceCallback();
  }

  private disposeAudioSessionCallback(): void {
    let manager = this.audioSessionManager;
    if (manager != null) {
      try {
        if (this.isInterruptionListenerActive) {
          let callback = this.interruptionCallback;
          // 传入具体回调引用，确保取消正确的监听器并打破循环引用
          if (callback != null) {
            manager.off('audioSessionDeactivated', callback);
          }
        }
      } catch (err) {
        Log.w(TAG, 'disposeAudioSessionCallback off failed: ' + err);
      }
      this.audioSessionManager = null;
      this.interruptionCallback = null;
      this.isInterruptionListenerActive = false;
    }
  }

  public async setInterruptionEventListener(args: Map<string, ESObject>, result: MethodResult): Promise<boolean> {
    try {
      // Dart 侧 isOnListener 为 bool；先校验键存在
      let isOnListenerRaw: ESObject | undefined = args.get('isOnListener');
      if (isOnListenerRaw == null || isOnListenerRaw == undefined) {
        result.error(ERR_INVALID_ARGS, 'isOnListener is required', null);
        return false;
      }
      let isOnListener: boolean = isOnListenerRaw as boolean;
      // 使用 Dart 传入的 audioAttributes
      let attrsRaw: ESObject | undefined = args.get('audioAttributes');
      if (attrsRaw != null && attrsRaw != undefined) {
        let attrs: Map<string, ESObject> = attrsRaw as Map<string, ESObject>;
        this.pendingAudioAttributes = attrs;
        if (attrs.has('samplingRate') && !attrs.has('sampleRate')) {
          attrs.set('sampleRate', attrs.get('samplingRate') as ESObject);
        }
        this.pendingRendererOptions = this.decodeAudioRendererOptions(attrs);
        Log.i(TAG, 'setInterruptionEventListener stored audioAttributes, options=' +
          (this.pendingRendererOptions != null));
      } else {
        this.pendingAudioAttributes = null;
        this.pendingRendererOptions = null;
      }
      if (this.audioSessionManager == null) {
        this.audioSessionManager = audio.getAudioManager().getSessionManager();
      }
      let manager = this.audioSessionManager;
      if (manager == null) {
        result.success(false);
        return false;
      }
      if (isOnListener) {
        // 先取消旧监听器，避免重复注册导致同一事件多次回调
        if (this.isInterruptionListenerActive) {
          let oldCallback = this.interruptionCallback;
          if (oldCallback != null) {
            try {
              manager.off('audioSessionDeactivated', oldCallback);
            } catch (err) {
              Log.w(TAG, 'setInterruptionEventListener off old failed: ' + err);
            }
          }
        }
        // 保存回调引用，避免反复创建匿名函数累积；回调内 try-catch 防止系统回调崩溃
        let self = this;
        let callback = (event: audio.AudioSessionDeactivatedEvent) => {
          try {
            self.invokeMethod('onAudioInterrupt', event.reason);
          } catch (err) {
            Log.e(TAG, 'audioSessionDeactivated callback failed: ' + err);
          }
        };
        this.interruptionCallback = callback;
        manager.on('audioSessionDeactivated', callback);
        this.isInterruptionListenerActive = true;
      } else {
        let oldCallback = this.interruptionCallback;
        if (oldCallback != null) {
          try {
            manager.off('audioSessionDeactivated', oldCallback);
          } catch (err) {
            Log.w(TAG, 'setInterruptionEventListener off failed: ' + err);
          }
        }
        this.interruptionCallback = null;
        this.isInterruptionListenerActive = false;
      }
      result.success(true);
      return true;
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setInterruptionEventListener failed: code=' + error.code + ' message=' + error.message);
      result.error(ERR_AUDIO_SESSION, 'setInterruptionEventListener failed: ' + error.message, null);
      return false;
    }
  }

  private disposeAudioDeviceCallback(): void {
    let manager = this.audioManager;
    let callback = this.deviceChangeCallback;
    if (manager != null && callback != null) {
      try {
        // 传入具体回调引用，确保取消正确的监听器并打破循环引用
        manager.getRoutingManager().off('deviceChange', callback);
      } catch (err) {
        Log.w(TAG, 'disposeAudioDeviceCallback off failed: ' + err);
      }
      this.deviceChangeCallback = null;
    }
  }

  private invokeMethod(method: string, ...args: Array<ESObject>): void {
    for(let i = 0; i < this.instances.length; i++) {
      const instance = this.instances[i];
      if (instance.channel != null) {
        const list: ESObject[] = [...args]
        instance.channel!.invokeMethod(method, list);
      }
    }
  }

  public async setActive(args: Array<ESObject>, result: MethodResult): Promise<boolean> {
    try {
      this.audioActive = args[0] as boolean;
      if (this.audioSessionManager == null) {
        this.audioSessionManager = audio.getAudioManager().getSessionManager();
      }
      if (this.audioActive) {
        // concurrencyMode 可选，Dart 可能传 null
        let concurrencyArg: ESObject | null = args.length > 1 ? args[1] : null;
        let sessionStrategy: audio.AudioSessionStrategy = {
          concurrencyMode: this.decodeAudioConcurrencyMode(concurrencyArg)
        };
        // 若已配置 audioAttributes，记录 streamUsage 便于排查（会话策略本身仅含 concurrencyMode）
        if (this.pendingAudioAttributes != null) {
          Log.i(TAG, 'setActive with pending audioAttributes streamUsage=' +
            this.pendingAudioAttributes.get('streamUsage'));
        }
        await this.audioSessionManager!.activateAudioSession(sessionStrategy);
      } else {
        // 已停用时再调 deactivateAudioSession 会抛 6800301
        //（system error. set app volume fail.）。先查状态，按幂等成功处理。
        let alreadyInactive: boolean = false;
        try {
          alreadyInactive = !this.audioSessionManager!.isAudioSessionActivated();
        } catch (checkErr) {
          Log.w(TAG, 'isAudioSessionActivated failed: ' + checkErr);
        }
        if (alreadyInactive) {
          Log.i(TAG, 'setActive(false): already inactive, skip deactivate');
          result.success(true);
          return true;
        }
        await this.audioSessionManager!.deactivateAudioSession();
      }
      result.success(true);
      return true;
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setActive failed: code=' + error.code + ' message=' + error.message);
      // 停用竞态：查询后、调用前被系统停用，同样视为成功
      if (!this.audioActive && error.code == 6800301) {
        Log.w(TAG, 'setActive(false) treat 6800301 as already inactive');
        result.success(true);
        return true;
      }
      // 失败时清理 pending，避免重复失败时引用残留
      this.pendingAudioAttributes = null;
      this.pendingRendererOptions = null;
      result.error(ERR_AUDIO_SESSION, 'setActive failed: ' + error.message, null);
      return false;
    }
  }

  public dispatchMediaKeyEvent(rawKeyEvent: ESObject, result: MethodResult): void {
    // 平台限制：公开 SDK 无 MediaKeyEvent 分发 API
    Log.w(TAG, 'dispatchMediaKeyEvent unsupported on public OHOS SDK');
    result.error('UnsupportedOperation', 'dispatchMediaKeyEvent is not available on OHOS public SDK', null);
  }

  public isVolumeUnadjustable(): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .isVolumeUnadjustable();
  }

  private getVolumeGroup(): audio.AudioVolumeGroupManager | null {
    if (this.audioManager == null) {
      return null;
    }
    return this.audioManager.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
  }

  /** 按步进调整指定音量类型；公开 API 无 adjustSystemVolumeByStep，改用 getVolume + setVolume。flags 在 OHOS 无 UI 标志位，仅记录日志。 */
  public async adjustStreamVolume(streamType: number, direction: number, flags: number,
    result: MethodResult): Promise<void> {
    try {
      // OHOS 无 Android FLAG_* 对等项；保留参数以满足签名并记录
      Log.i(TAG, 'adjustStreamVolume flags=' + flags + ' (ignored on OHOS)');
      let group = this.getVolumeGroup();
      if (group == null || this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'volume manager unavailable', null);
        return;
      }
      let current: number = group.getVolumeSync(streamType);
      let next: number = current;
      if (direction > 0) {
        next = current + 1;
      } else if (direction < 0) {
        next = current - 1;
      }
      let minV: number = group.getMinVolumeSync(streamType);
      let maxV: number = group.getMaxVolumeSync(streamType);
      if (next < minV) {
        next = minV;
      }
      if (next > maxV) {
        next = maxV;
      }
      await this.audioManager.setVolume(streamType, next);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'adjustStreamVolume failed: ' + error.message);
      result.error(ERR_AUDIO_SESSION, 'adjustStreamVolume failed: ' + error.message, null);
    }
  }

  /** 调整默认媒体音量；公开 API 无 adjustVolume，改用 MEDIA 流 setVolume。 */
  public async adjustVolume(direction: number, flags: number, result: MethodResult): Promise<void> {
    await this.adjustStreamVolume(audio.AudioVolumeType.MEDIA, direction, flags, result);
  }

  public adjustSuggestedStreamVolume(direction: number, suggestedStreamType: number, flags: number,
    result: MethodResult): void {
    Log.w(TAG, 'adjustSuggestedStreamVolume unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'adjustSuggestedStreamVolume is not available on OHOS public SDK', null);
  }

  public getRingerMode(): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .getRingerModeSync();
  }

  public getMaxVolume(streamType: number): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .getMaxVolumeSync(streamType);
  }

  public getMinVolume(streamType: number): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .getMinVolumeSync(streamType);
  }

  public getVolume(streamType: number): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .getVolumeSync(streamType);
  }

  /**
   * Dart 仅传 AudioVolumeType，期望返回 int；
   * OHOS API 返回 number（可能为浮点），四舍五入为整数以匹配 Dart Future<int>。
   */
  public getSystemVolumeInDb(streamType: number): ESObject {
    let volumeGroup = this.audioManager?.getVolumeManager()
      .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
    if (volumeGroup == null || volumeGroup == undefined) {
      return null;
    }
    let volumeLevel: number = volumeGroup.getVolumeSync(streamType);
    let dbValue: number = volumeGroup.getSystemVolumeInDbSync(streamType, volumeLevel, audio.DeviceType.SPEAKER);
    // 显式转为整数，满足 Dart Future<int>
    let asInt: number = Math.round(dbValue) | 0;
    return asInt;
  }

  public async setRingerMode(ringerMode: number, result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      await this.audioManager.setRingerMode(ringerMode);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setRingerMode failed: code=' + error.code + ' message=' + error.message);
      result.error('SetRingerModeError', 'setRingerMode failed: ' + error.message, null);
    }
  }

  public async setStreamVolume(streamType: number, index: number, flags: number,
    result: MethodResult): Promise<void> {
    try {
      // OHOS 无 Android FLAG_*；保留并记录以满足签名一致性
      Log.i(TAG, 'setStreamVolume flags=' + flags + ' (ignored on OHOS)');
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      await this.audioManager.setVolume(streamType, index);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setStreamVolume failed: ' + error.message);
      result.error(ERR_AUDIO_SESSION, 'setStreamVolume failed: ' + error.message, null);
    }
  }

  public isMute(streamType: number): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .isMuteSync(streamType);
  }

  public getAvailableCommunicationDevices(): Map<string, ESObject>[] {
    this.audioDeviceDescriptors = this.audioManager?.getRoutingManager()
      .getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
    let result: Map<string, ESObject>[] = [];
    if (this.audioDeviceDescriptors != undefined) {
      for (let i = 0; i < this.audioDeviceDescriptors.length; i++) {
        // 仅返回扬声器类通信设备，贴近 Android getAvailableCommunicationDevices 语义
        if (this.audioDeviceDescriptors[i].deviceType == audio.DeviceType.SPEAKER) {
          result.push(this.encodeAudioDevice(this.audioDeviceDescriptors[i]));
        }
      }
    }
    return result;
  }

  public async setCommunicationDevice(deviceId: number, result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      if (this.audioDeviceDescriptors == undefined) {
        this.audioDeviceDescriptors = this.audioManager.getRoutingManager()
          .getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
      }
      let found = false;
      if (this.audioDeviceDescriptors != undefined) {
        for (let i = 0; i < this.audioDeviceDescriptors.length; i++) {
          let device = this.audioDeviceDescriptors[i];
          if (device.id == deviceId) {
            // 公开 CommunicationDeviceType 仅 SPEAKER；扬声器设备走 setCommunicationDevice
            if (device.deviceType == audio.DeviceType.SPEAKER) {
              await this.audioManager.getRoutingManager()
                .setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, true);
              found = true;
            }
            break;
          }
        }
      }
      result.success(found);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setCommunicationDevice failed: ' + error.message);
      result.error(ERR_AUDIO_SESSION, 'setCommunicationDevice failed: ' + error.message, null);
    }
  }

  public getCommunicationDevice(): Map<string, ESObject> {
    let empty: Map<string, ESObject> = new Map();
    let routing = this.audioManager?.getRoutingManager();
    if (routing == null || routing == undefined) {
      return empty;
    }
    // 公开 API 无 getCommunicationDeviceSync；用 isCommunicationDeviceActiveSync 推断
    let active = routing.isCommunicationDeviceActiveSync(audio.CommunicationDeviceType.SPEAKER);
    if (!active) {
      return empty;
    }
    let devices = routing.getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].deviceType == audio.DeviceType.SPEAKER) {
        return this.encodeAudioDevice(devices[i]);
      }
    }
    return empty;
  }

  public async clearCommunicationDevice(result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      // 公开 API 无 clearCommunicationDevice；关闭扬声器通信路由
      await this.audioManager.getRoutingManager()
        .setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, false);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'clearCommunicationDevice failed: ' + error.message);
      result.error(ERR_AUDIO_SESSION, 'clearCommunicationDevice failed: ' + error.message, null);
    }
  }

  public async setSpeakerphoneOn(enabled: boolean, result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      await this.audioManager.getRoutingManager()
        .setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, enabled);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setSpeakerphoneOn failed: ' + error.message);
      result.error(ERR_AUDIO_SESSION, 'setSpeakerphoneOn failed: ' + error.message, null);
    }
  }

  public isSpeakerphoneOn(): ESObject {
    return this.audioManager?.getRoutingManager().isCommunicationDeviceActiveSync(audio.CommunicationDeviceType.SPEAKER);
  }

  public setAllowedCapturePolicy(capturePolicy: number, result: MethodResult): void {
    // 平台限制：公开 SDK 无 setAudioAllowedCapturePolicy
    Log.w(TAG, 'setAllowedCapturePolicy unsupported on public OHOS SDK, policy=' + capturePolicy);
    result.error('UnsupportedOperation',
      'setAllowedCapturePolicy is not available on OHOS public SDK', null);
  }

  public getAllowedCapturePolicy(result: MethodResult): void {
    // 平台限制：公开 SDK 无 getAudioAllowedCapturePolicy
    Log.w(TAG, 'getAllowedCapturePolicy unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'getAllowedCapturePolicy is not available on OHOS public SDK', null);
  }

  public isBluetoothScoAvailableOffCall(result: MethodResult): void {
    Log.w(TAG, 'isBluetoothScoAvailableOffCall unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'isBluetoothScoAvailableOffCall is not available on OHOS public SDK', null);
  }

  public startBluetoothSco(result: MethodResult): void {
    Log.w(TAG, 'startBluetoothSco unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'startBluetoothSco is not available on OHOS public SDK', null);
  }

  public stopBluetoothSco(result: MethodResult): void {
    Log.w(TAG, 'stopBluetoothSco unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'stopBluetoothSco is not available on OHOS public SDK', null);
  }

  public setBluetoothScoOn(enabled: boolean, result: MethodResult): void {
    Log.w(TAG, 'setBluetoothScoOn unsupported on public OHOS SDK, enabled=' + enabled);
    result.error('UnsupportedOperation',
      'setBluetoothScoOn is not available on OHOS public SDK', null);
  }

  public isBluetoothScoOn(result: MethodResult): void {
    Log.w(TAG, 'isBluetoothScoOn unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'isBluetoothScoOn is not available on OHOS public SDK', null);
  }

  public async setMicrophoneMute(enabled: boolean, result: MethodResult): Promise<void> {
    // 平台限制：AudioVolumeGroupManager.setMicrophoneMute 需 ohos.permission.MANAGE_AUDIO_CONFIG（仅系统应用可申请）；
    // AudioManager.setMicrophoneMute 自 API 9 起废弃，替代接口同样仅系统应用可用。三方应用无法设置系统麦克风静音。
    Log.w(TAG, 'setMicrophoneMute unsupported for third-party apps on OHOS, enabled=' + enabled);
    result.error('UnsupportedOperation',
      'setMicrophoneMute requires ohos.permission.MANAGE_AUDIO_CONFIG (system apps only); ' +
        'not available to third-party apps on OHOS public SDK', null);
  }

  public isMicrophoneMute(): ESObject {
    return this.audioManager?.getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID)
      .isMicrophoneMuteSync();
  }

  public setMode(mode: number, result: MethodResult): void {
    // 平台限制：公开 SDK 仅有 getAudioScene，无 setAudioScene
    Log.w(TAG, 'setMode/setAudioScene unsupported on public OHOS SDK, mode=' + mode);
    result.error('UnsupportedOperation',
      'setMode/setAudioScene is not available on OHOS public SDK', null);
  }

  public getAudioScene(): ESObject {
    return this.audioManager?.getAudioSceneSync();
  }

  public isMusicActive(): ESObject {
    return this.audioManager?.getStreamManager().isActiveSync(audio.AudioVolumeType.MEDIA);
  }

  public generateAudioSessionId(result: MethodResult): void {
    Log.w(TAG, 'generateAudioSessionId unsupported on public OHOS SDK');
    result.error('UnsupportedOperation',
      'generateAudioSessionId is not available on OHOS public SDK', null);
  }

  public async setAudioParameter(key: string, value: string, result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      await this.audioManager.setAudioParameter(key, value);
      result.success(null);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'setAudioParameter failed: code=' + error.code + ' message=' + error.message);
      result.error(ERR_AUDIO_SESSION, 'setAudioParameter failed: ' + error.message, null);
    }
  }

  public async getAudioParameter(key: string, result: MethodResult): Promise<void> {
    try {
      if (this.audioManager == null) {
        result.error(ERR_AUDIO_SESSION, 'audioManager is null', null);
        return;
      }
      let value: string = await this.audioManager.getAudioParameter(key);
      result.success(value);
    } catch (err) {
      let error = err as BusinessError;
      Log.e(TAG, 'getAudioParameter failed: code=' + error.code + ' message=' + error.message);
      result.error(ERR_AUDIO_SESSION, 'getAudioParameter failed: ' + error.message, null);
    }
  }


  public getProperty(arg: string, result: MethodResult): void {
    Log.w(TAG, 'getProperty unsupported on public OHOS SDK, key=' + arg);
    result.error('UnsupportedOperation',
      'getProperty is not available on OHOS public SDK', null);
  }

  public getDevices(flags: number): ESObject {
    let result: Array<Map<string, ESObject>> = [];
    this.audioDeviceDescriptors = this.audioManager?.getRoutingManager().getDevicesSync(flags);
    if(this.audioDeviceDescriptors != undefined) {
      for(let i = 0; i < this.audioDeviceDescriptors?.length; i++) {
        result.push(this.encodeAudioDevice(this.audioDeviceDescriptors[i]));
      }
    }
    return result;
  }

  public getMicrophones(): ESObject {
    let result: ArrayList<Map<string, ESObject>> = new ArrayList();
    this.audioManager?.getRoutingManager().getDevicesSync(audio.DeviceFlag.INPUT_DEVICES_FLAG).forEach(device => {
      if(device.deviceType == audio.DeviceType.MIC)
      result.add(this.encodeAudioDevice(device));
    })
    return result;
  }

  public isHapticPlaybackSupported(): ESObject {
    // 公开 SDK 无触觉播放能力查询 API；保守返回 false（与 Android 不可用时一致）
    return false;
  }
}