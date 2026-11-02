/*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
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

import {
  AbilityAware,
  AbilityPluginBinding,
  Any,
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import AudioService, { ServiceListener } from './AudioService';
import { SessionParameter } from './AudioProcessingState';
import { JSON } from '@kit.ArkTS';

const TAG: string = "AudioServicePlugin";

const CHANNEL_CLIENT = "com.ryanheise.audio_service.client.methods";
const CHANNEL_HANDLER = "com.ryanheise.audio_service.handler.methods";

let audioService: AudioService | null = null

export default class AudioServicePlugin implements FlutterPlugin, AbilityAware {
  private flutterPluginBinding: FlutterPluginBinding | null = null;
  private abilityPluginBinding: AbilityPluginBinding | null = null;
  private audioServiceHandle: AudioServiceHandle | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.flutterPluginBinding = binding;
    if (this.audioServiceHandle == null && this.abilityPluginBinding != null) {
      this.audioServiceHandle =
        new AudioServiceHandle(this.flutterPluginBinding.getBinaryMessenger(),
          this.flutterPluginBinding.getApplicationContext(), this.abilityPluginBinding)
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.flutterPluginBinding = null;
    audioService?.release()
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    Log.i(TAG, "onAttachedToAbility");
    this.abilityPluginBinding = binding
    if (this.audioServiceHandle == null && this.flutterPluginBinding != null) {
      this.audioServiceHandle =
        new AudioServiceHandle(this.flutterPluginBinding.getBinaryMessenger(),
          this.flutterPluginBinding.getApplicationContext(), this.abilityPluginBinding)
    }
  }

  onDetachedFromAbility(): void {
    throw new Error('Method not implemented.');
  }
}

class AudioServiceHandle implements MethodCallHandler, ServiceListener {
  private context: Context;
  private messenger: BinaryMessenger;
  private clientMethodChannel: MethodChannel;
  private handleMethodChannel: MethodChannel;
  private abilityPluginBinding: AbilityPluginBinding;

  constructor(messenger: BinaryMessenger, context: Context, abilityPluginBinding: AbilityPluginBinding) {
    this.context = context
    this.messenger = messenger
    this.abilityPluginBinding = abilityPluginBinding
    this.clientMethodChannel = new MethodChannel(this.messenger, CHANNEL_CLIENT)
    this.clientMethodChannel.setMethodCallHandler(this)
    this.handleMethodChannel = new MethodChannel(this.messenger, CHANNEL_HANDLER)
    this.handleMethodChannel.setMethodCallHandler(this)
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, "onMethodCall : " + call.method);
    switch (call.method) {
      case 'configure':
        try {
          let config: Map<Any, Any> = call.argument('config');
          let fastForwardInterval: number = config.get('fastForwardInterval')
          let rewindInterval: number = config.get('rewindInterval')
          if (audioService == null) {
            audioService = new AudioService(this.context, this.abilityPluginBinding.getAbility())
            audioService.setSessionCallback(this.sessionCallback.bind(this))
          }
          audioService.setFastForwardInterval(fastForwardInterval)
        } catch (e) {
          Log.e(TAG, "onMethodCall configure catch : " + JSON.stringify(e));
        }
        result.success(new Map<string, object>())
        break
      case 'setState':
        try {
          let state: Map<string, Any> = call.argument("state")
          audioService?.setAVPlaybackState(state)
        } catch (e) {
          Log.e(TAG, "onMethodCall setState catch : " + JSON.stringify(e));
        }
        result.success(null)
        break
      case 'setQueue':
        let queue: Map<Any, Any> = call.argument("queue")
        audioService?.setQueueItems(queue)
        result.success(null)
        break
      case 'setMediaItem':
        let mediaItem: Map<Any, Any> = call.argument("mediaItem")
        audioService?.setMediaItem(mediaItem)
        result.success(null)
        break
      case 'setPlaybackInfo':
        result.success(null)
        break
      case 'notifyChildrenChanged':
        result.success(null)
        break
      case 'setAndroidPlaybackInfo':
        result.success(null)
        break
      case 'androidForceEnableMediaButtons':
        result.success(null)
        break
      case 'stopService':
        audioService?.release()
        result.success(null)
        break
      case 'setShuffleMode':
        try {
          Log.i(TAG, "收到setShuffleMode调用");
          // 直接从参数中获取shuffleMode值
          let shuffleMode: number = call.argument("shuffleMode") as number || 0;
          Log.i(TAG, `设置随机播放模式: ${shuffleMode}`);
          audioService?.setShuffleMode(shuffleMode);
          Log.i(TAG, "setShuffleMode调用完成");
        } catch (e) {
          Log.e(TAG, "onMethodCall setShuffleMode catch : " + JSON.stringify(e));
        }
        result.success(null);
        break;
    }
  }

  invokeMethod(method: string, arg: Any): void {
    this.handleMethodChannel.invokeMethod(method, arg)
  }

  sessionCallback(sessionParameter: SessionParameter) {
    Log.i(TAG, "AudioHandlerInterface sessionCallback : " + JSON.stringify(sessionParameter));
    switch (sessionParameter.type) {
      case 'play':
        this.onPlay()
        break
      case 'pause':
        this.onPause()
        break
      case 'stop':
        this.onStop()
        break
      case 'seek':
        this.onSeekTo(sessionParameter.params as number * 1000)
        break
      case 'playNext':
        this.onSkipToNext()
        break
      case 'playPrevious':
        this.onSkipToPrevious()
        break
      case 'rewind':
        this.onRewind()
        break
      case 'fastForward':
        this.onFastForward()
        break
      case 'setSpeed':
        this.onSeekTo(sessionParameter.params as number)
        break
      case 'setLoopMode':
        this.onSetRepeatMode(sessionParameter.params as number)
        break
    }
  }

  onPlay() {
    this.invokeMethod('play', null)
  }

  onPause() {
    this.invokeMethod('pause', null)
  }

  onSkipToNext() {
    this.invokeMethod('skipToNext', null);
  }

  onSkipToPrevious() { 
    this.invokeMethod('skipToPrevious', null);
  }

  onFastForward() {
    this.invokeMethod('fastForward', null);
  }

  onRewind() {
    this.invokeMethod('rewind', null);
  }

  onStop() {
    this.invokeMethod('stop', null)
  }

  onSeekTo(pos: number) {
    let map: Map<String, Any> = new Map();
    map.set('position', pos)
    this.invokeMethod('seek', map)
  }

  onSetRepeatMode(repeatMode: number) {
    let map: Map<String, Any> = new Map();
    if (repeatMode == 3) {
      map.set('shuffleMode', 0)
      this.invokeMethod('setShuffleMode', map)
    } else {
      map.set('repeatMode', repeatMode)
      this.invokeMethod('setRepeatMode', map)
    }
  }

  onSetPlaybackSpeed(speed: number) {
    let map: Map<String, Any> = new Map();
    map.set('speed', speed)
    this.invokeMethod('setSpeed', map)
  }
}
