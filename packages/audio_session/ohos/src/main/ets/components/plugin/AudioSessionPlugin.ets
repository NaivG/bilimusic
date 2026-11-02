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
 
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import OhosAudioManager from './OhosAudioManager';
import { Log } from '@ohos/flutter_ohos';

/** AudioSessionPlugin **/
export default class AudioSessionPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private ohosAudioManager: OhosAudioManager | null = null;
  private static instances: AudioSessionPlugin[] = [];
  private static configuration: Map<ESObject, ESObject> | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'AudioSessionPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'com.ryanheise.audio_session');
    this.channel.setMethodCallHandler(this);
    this.ohosAudioManager = new OhosAudioManager(binding.getApplicationContext(), binding.getBinaryMessenger());
    AudioSessionPlugin.instances.push(this);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    // Ability 重建后恢复系统级监听（onDetachedFromAbility 会释放）
    this.ohosAudioManager?.ensureSystemListeners();
  }

  onDetachedFromAbility(): void {
    // Ability 分离时（如配置变更导致 Ability 重建）兜底释放系统级监听（deviceChange /
    // audioSessionDeactivated），避免循环引用导致 Singleton 无法 GC。
    // 注意：此处仅清理系统级监听，保留 MethodChannel/实例注册（engine 仍存活），全量释放交由 onDetachedFromEngine。
    this.ohosAudioManager?.releaseSystemListeners();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.ohosAudioManager?.dispose();
    this.ohosAudioManager = null;
    let index = AudioSessionPlugin.instances.indexOf(this);
    if (index !== -1) {
      AudioSessionPlugin.instances.splice(index, 1);
    }
    this.channel = null;
    // 当无存活的 Plugin 实例时，清理跨实例共享的静态配置，避免数据残留
    AudioSessionPlugin.clearConfigurationIfIdle();
  }

  private static clearConfigurationIfIdle(): void {
    if (AudioSessionPlugin.instances.length == 0 && AudioSessionPlugin.configuration != null) {
      AudioSessionPlugin.configuration.clear();
      AudioSessionPlugin.configuration = null;
    }
  }

  /** Coerce known numeric configuration fields to int for Dart `as int` decoding. */
  private static toIntOrNull(value: ESObject | undefined): number | null {
    if (value == null || value == undefined) {
      return null;
    }
    if (typeof value === 'number') {
      let num: number = value as number;
      return num | 0;
    }
    return null;
  }

  private static putIntIfPresent(out: Map<ESObject, ESObject>, key: string,
    raw: ESObject | undefined): void {
    let asInt: number | null = AudioSessionPlugin.toIntOrNull(raw);
    if (asInt != null) {
      out.set(key, asInt);
    }
  }

  private static copyMap(src: Map<ESObject, ESObject>): Map<ESObject, ESObject> {
    let out: Map<ESObject, ESObject> = new Map();
    src.forEach((v: ESObject, k: ESObject) => {
      out.set(k, v);
    });
    return out;
  }

  private static normalizeNestedAttrs(raw: ESObject | undefined): Map<ESObject, ESObject> | null {
    if (raw == null || raw == undefined) {
      return null;
    }
    let src: Map<ESObject, ESObject> = raw as Map<ESObject, ESObject>;
    let out: Map<ESObject, ESObject> = AudioSessionPlugin.copyMap(src);
    AudioSessionPlugin.putIntIfPresent(out, 'contentType', src.get('contentType'));
    AudioSessionPlugin.putIntIfPresent(out, 'flags', src.get('flags'));
    AudioSessionPlugin.putIntIfPresent(out, 'usage', src.get('usage'));
    AudioSessionPlugin.putIntIfPresent(out, 'streamUsage', src.get('streamUsage'));
    AudioSessionPlugin.putIntIfPresent(out, 'samplingRate', src.get('samplingRate'));
    AudioSessionPlugin.putIntIfPresent(out, 'channels', src.get('channels'));
    AudioSessionPlugin.putIntIfPresent(out, 'sampleFormat', src.get('sampleFormat'));
    AudioSessionPlugin.putIntIfPresent(out, 'encodingType', src.get('encodingType'));
    return out;
  }

  private static normalizeConfiguration(raw: ESObject): Map<ESObject, ESObject> {
    let src: Map<ESObject, ESObject> = raw as Map<ESObject, ESObject>;
    let out: Map<ESObject, ESObject> = AudioSessionPlugin.copyMap(src);
    AudioSessionPlugin.putIntIfPresent(out, 'avAudioSessionCategoryOptions',
      src.get('avAudioSessionCategoryOptions'));
    AudioSessionPlugin.putIntIfPresent(out, 'avAudioSessionMode', src.get('avAudioSessionMode'));
    AudioSessionPlugin.putIntIfPresent(out, 'avAudioSessionRouteSharingPolicy',
      src.get('avAudioSessionRouteSharingPolicy'));
    AudioSessionPlugin.putIntIfPresent(out, 'avAudioSessionSetActiveOptions',
      src.get('avAudioSessionSetActiveOptions'));
    AudioSessionPlugin.putIntIfPresent(out, 'androidAudioFocusGainType',
      src.get('androidAudioFocusGainType'));

    let androidRaw: ESObject | undefined = src.get('androidAudioAttributes');
    let androidAttrs: Map<ESObject, ESObject> | null =
      AudioSessionPlugin.normalizeNestedAttrs(androidRaw);
    if (androidAttrs != null) {
      out.set('androidAudioAttributes', androidAttrs);
    }
    let ohosRaw: ESObject | undefined = src.get('ohosAudioAttributes');
    let ohosAttrs: Map<ESObject, ESObject> | null =
      AudioSessionPlugin.normalizeNestedAttrs(ohosRaw);
    if (ohosAttrs != null) {
      out.set('ohosAudioAttributes', ohosAttrs);
    }
    return out;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      Log.i('AudioSessionPlugin', 'onMethodCall: ' + call.method);
      switch (call.method) {
        case 'setConfiguration': {
          const args: Array<ESObject> = call.args as Array<ESObject>;
          if (args == null || args.length < 1 || args[0] == null) {
            result.error('InvalidArgs', 'setConfiguration requires at least 1 argument', null);
            break;
          }
          Log.i('AudioSessionPlugin', 'setConfiguration: ' + args[0]);
          // Normalize numeric fields to integers before echoing to Dart.
          // OHOS MethodChannel may widen ints to doubles; Dart fromJson uses `as int`.
          AudioSessionPlugin.configuration =
            AudioSessionPlugin.normalizeConfiguration(args[0]);
          result.success(null);
          this.invokeMethod('onConfigurationChanged', AudioSessionPlugin.configuration);
          break;
        }
        case 'getConfiguration': {
          result.success(AudioSessionPlugin.configuration);
          break;
        }
        default:
          result.notImplemented();
          break;
      }
    } catch (err) {
      Log.e('AudioSessionPlugin', 'onMethodCall failed: ' + err);
      result.error('AudioSessionPluginError', 'Method call failed: ' + err, null);
    }
  }

  private invokeMethod(method: string, ...args: Array<ESObject>): void {
    for(let i = 0; i < AudioSessionPlugin.instances.length; i++) {
      const instance = AudioSessionPlugin.instances[i];
      if (instance.channel != null) {
        const list: ESObject[] = [...args]
        instance.channel!.invokeMethod(method, list);
      }
    }
  }
}