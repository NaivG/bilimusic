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

import { common, Context, UIAbility, WantAgent, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError, Callback } from '@kit.BasicServicesKit';
import { Any, Log } from '@ohos/flutter_ohos';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { SessionParameter, AudioProcessingState } from './AudioProcessingState';
import { JSON } from '@kit.ArkTS';
import { audio } from '@kit.AudioKit';

const TAG: string = "AudioService";

export default class AudioService {

  private context: Context
  private ability: UIAbility
  private session: avSession.AVSession | null = null
  private sessionCallback: Callback<SessionParameter> | null = null
  private avMetadata: avSession.AVMetadata = {
    assetId: '0'
  }
  private isStartContinuousTask = false
  private queueItems: avSession.AVQueueItem[] = []
  private fastForwardInterval: avSession.SkipIntervals = avSession.SkipIntervals.SECONDS_10
  private mediaType: avSession.AVSessionType = 'audio'

  // 在类属性声明部分添加
  private shuffleMode: number = 0; // 0: 正常模式, 1: 随机模式
  private originalQueue: avSession.AVQueueItem[] = [];
  private shuffledQueue: avSession.AVQueueItem[] = [];
  private currentQueueIndex: number = 0;

  constructor(context: Context, ability: UIAbility) {
    this.context = context
    this.ability = ability
    this.createSession()
  }

  setFastForwardInterval(data: number) {
    let interval: number = data / 1000
    if (Object.values(avSession.SkipIntervals).includes(interval)) {
      this.fastForwardInterval = interval
    }
  }


  setQueueItems(queue: Map<Any, Any>) {
    try {
      const tempItems: avSession.AVQueueItem[] = []
      queue.forEach((data: Map<string, Any>, key: number) => {
        let id: string = data.get('id')
        let title: string = data.get('title')
        let album: string = data.get('album')
        let artist: string = data.get('artist')
        let genre: number = data.get('genre')
        let duration: number = data.get('duration')
        let artUri: string = data.get('artUri')
        let playable: string = data.get('playable')
        let displayTitle: string = data.get('displayTitle')
        let displaySubtitle: string = data.get('displaySubtitle')
        let displayDescription: string = data.get('displayDescription')
        let rating: string = data.get('rating')
        let extras: Any = data.get('extras')
        const description: avSession.AVMediaDescription = {
          assetId: id
        }
        if(title){
          description.title = title
        }
        if(album){
          description.albumTitle = album
        }
        if(artist){
          description.artist = artist
        }
        if(genre){
          description.displayTags = genre
        }
        if(duration){
          description.duration = duration
        }
        if(artUri){
          description.mediaUri = artUri
        }
        if (extras){
          description.extras = extras
        }
        tempItems.push({
          itemId: key,
          description: description
        })
      })
      this.session?.setAVQueueItems(tempItems);
      this.queueItems = tempItems;
    } catch (e) {
      Log.e(TAG, "AudioService setQueueItems catch " + JSON.stringify(e));
    }
  }

  setSessionCallback(sessionCallback: Callback<SessionParameter>) {
    this.sessionCallback = sessionCallback
  }

  async setMediaItem(mediaItem: Map<string, Any>) {
    try {
      let extrasMap: Map<string, string> = mediaItem.get('extras');
      if (extrasMap != null) {
        if (extrasMap.has('mediaType')) {
          this.mediaType = extrasMap.get('mediaType') as avSession.AVSessionType
        }
      }
      let id: string = mediaItem.get('id');
      let index = this.queueItems.findIndex(item => item.description?.assetId === id);
      if (index != -1 && this.queueItems.length > 1) {
        //列表首
        if (index == 0) {
          this.avMetadata.nextAssetId = this.queueItems[index+1].description?.assetId

        }
        //列表尾
        else if (index == this.queueItems.length - 1) {
          this.avMetadata.previousAssetId = this.queueItems[index-1].description?.assetId
        }
        //中间
        else {
          this.avMetadata.nextAssetId = this.queueItems[index+1].description?.assetId
          this.avMetadata.previousAssetId = this.queueItems[index-1].description?.assetId
        }
      }
      this.avMetadata.assetId = mediaItem.get('id')
      this.avMetadata.title = mediaItem.get('title')
      this.avMetadata.mediaImage = mediaItem.get('artUri')
      this.avMetadata.artist = mediaItem.get('artist')
      this.avMetadata.duration = mediaItem.get('duration')
      this.avMetadata.skipIntervals = this.fastForwardInterval
      Log.e(TAG, "AudioService setMediaItem " + JSON.stringify(this.avMetadata));
      if (this.session != null) {
        await this.session.setAVMetadata(this.avMetadata)
        await this.session.activate()
      }
    } catch (e) {
      Log.e(TAG, "AudioService setMediaItem catch " + JSON.stringify(e));
    }
  }

  async setAVPlaybackState(mediaItem: Map<string, Any>) {
    Log.i(TAG, `aVPlaybackState mediaItem JSON  : ${JSON.stringify(Array.from(mediaItem))}`);
    let aVPlaybackState: avSession.AVPlaybackState = {}
    try {
      let playing: boolean = mediaItem.get('playing')
      if (playing) {
        aVPlaybackState.state = avSession.PlaybackState.PLAYBACK_STATE_PLAY
        this.startContinuousTask()
        //播放完成初始化进度条
      } else {
        aVPlaybackState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
        this.stopContinuousTask()
      }

      let updatePosition = mediaItem.get('updatePosition') as number;
      let processingState = mediaItem.get('processingState') as number;
      // 不仅在播放状态下要更新卡片状态条，只要updatePosition有效都需要进行更新
      if (updatePosition != undefined) {
        aVPlaybackState.position = {
          elapsedTime: updatePosition,
          updateTime: new Date().getTime()
        }
        //播放完成初始化进度条
      } else if (processingState == AudioProcessingState.completed) {
        aVPlaybackState.position = {
          elapsedTime: 0,
          updateTime: new Date().getTime()
        }
      }

      aVPlaybackState.loopMode = mediaItem.get('repeatMode')
      if (mediaItem.has('speed')) {
        let speed: number = mediaItem.get('speed')
        aVPlaybackState.speed = speed
      }
      if (this.session == null && playing) {
        await this.createSession();
      }
      Log.w(TAG, `aVPlaybackState  : ${JSON.stringify(aVPlaybackState)}`);
      this.session?.setAVPlaybackState(aVPlaybackState)
      await this.session?.activate()
    } catch (e) {
      Log.e(TAG, "AudioService setAVPlaybackState catch " + JSON.stringify(e));
    }

  }

  async startContinuousTask() {
    Log.d(TAG, `startContinuousTask`);
    if (this.isStartContinuousTask) {
      return;
    }
    this.isStartContinuousTask = true;
    let context = this.ability.context;
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context?.abilityInfo.bundleName,
          abilityName: context?.abilityInfo.name
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        wantAgentObj).then(() => {
        Log.d(TAG, `Succeeded in operationing startBackgroundRunning.`);
      }).catch((err: BusinessError) => {
        Log.e(TAG, `Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
      });
    });
  }

  async stopContinuousTask() {
    Log.d(TAG, `stopContinuousTask`);
    if (!this.isStartContinuousTask) {
      return;
    }
    this.isStartContinuousTask = false;
    backgroundTaskManager.stopBackgroundRunning(this.ability.context).then(() => {
      Log.d(TAG, `Succeeded in operationing stopBackgroundRunning.`);
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Failed to operation stopBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
    });
  }

  // 创建session
  async createSession() {
    try {
      this.session = await avSession.createAVSession(this.ability.context, 'SESSION_NAME', this.mediaType);
      await this.session.setAVMetadata(this.avMetadata)
      await this.session.activate()
      //监听事件
      this.setListenerForMesFromController(this.session)
      Log.i(TAG, `session create done : sessionId : ${this.session.sessionId}`);
    } catch (e) {
      Log.i(TAG, "createSession err " + JSON.stringify(e));
    }
  }

  release() {
    try {
      this.session?.deactivate()
      this.session?.destroy()
      this.session = null
      this.stopContinuousTask()
    } catch (e) {
      Log.e(TAG, "sessionCallback play catch " + JSON.stringify(e));
    }
  }

  setListenerForMesFromController(session: avSession.AVSession) {
    session.on('play', () => {
      Log.i(TAG, `on play , do play task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'play'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback play catch " + JSON.stringify(e));
      }

    });
    session.on('pause', () => {
      Log.i(TAG, `on pause , do pause task`);
      try {
        Log.i(TAG, `on pause , do pause task`);
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'pause'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback pause catch " + JSON.stringify(e));
      }
    });
    session.on('stop', () => {
      Log.i(TAG, `on stop , do stop task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'stop'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback stop catch " + JSON.stringify(e));
      }
    });
    session.on('playNext', () => {
      Log.i(TAG, `on playNext , do playNext task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'playNext'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback playNext catch " + JSON.stringify(e));
      }
    });
    session.on('playPrevious', () => {
      Log.i(TAG, `on playPrevious , do playPrevious task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'playPrevious'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback playPrevious catch " + JSON.stringify(e));
      }
    });
    session.on('fastForward', () => {
      Log.i(TAG, `on fastForward , do fastForward task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'fastForward'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback fastForward catch " + JSON.stringify(e));
      }
    });
    session.on('rewind', () => {
      Log.i(TAG, `on rewind , do rewind task`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'rewind'
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback rewind catch " + JSON.stringify(e));
      }
    });
    session.on('seek', (time) => {
      Log.i(TAG, `on seek , the seek time is ${time}`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'seek', params: time
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback seek catch " + JSON.stringify(e));
      }
    });
    session.on('setSpeed', (speed) => {
      Log.i(TAG, `on setSpeed , the speed is ${speed}`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'setSpeed', params: speed
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback setSpeed catch " + JSON.stringify(e));
      }
    });
    session.on('setLoopMode', (mode) => {
      Log.i(TAG, `on setLoopMode , the loop mode is ${mode}`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'setLoopMode', params: mode == 2 ? 0 : mode + 1
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback setLoopMode catch " + JSON.stringify(e));
      }
    });
    session.on('toggleFavorite', (assetId) => {
      Log.i(TAG, `on toggleFavorite , the target asset Id is ${assetId}`);
      try {
        if (this.sessionCallback) {
          this.sessionCallback({
            type: 'toggleFavorite', params: assetId
          })
        }
      } catch (e) {
        Log.e(TAG, "sessionCallback toggleFavorite catch " + JSON.stringify(e));
      }
    });
  }


  // 在类方法部分添加（在 release() 方法之前）

  // 获取随机播放模式 - 必须返回 number 类型
  getShuffleMode(): number {
    return this.shuffleMode;
  }

  // 设置随机播放模式
  // 设置随机播放模式
  setShuffleMode(enabled: number): void {
    Log.i(TAG, `AudioService setShuffleMode: ${enabled}`);
    this.shuffleMode = enabled;
    if (enabled === 1) {
      Log.i(TAG, "启用随机播放，打乱播放列表");
      this.shufflePlaylist();
    } else {
      Log.i(TAG, "禁用随机播放，恢复原始播放列表");
      this.restoreOriginalPlaylist();
    }
    Log.i(TAG, `随机播放模式设置完成，当前模式: ${this.shuffleMode}`);
  }

  // 获取下一首歌曲索引
  getNextTrackIndex(): number {
    const currentQueue = this.getCurrentQueue();
    if (currentQueue.length === 0) return 0;

    if (this.shuffleMode === 1) {
      // 随机模式：返回随机索引
      return Math.floor(Math.random() * currentQueue.length);
    } else {
      // 正常模式：返回下一首
      return (this.currentQueueIndex + 1) % currentQueue.length;
    }
  }

  // 获取上一首歌曲索引
  getPreviousTrackIndex(): number {
    const currentQueue = this.getCurrentQueue();
    if (currentQueue.length === 0) return 0;

    if (this.shuffleMode === 1) {
      // 随机模式：返回随机索引
      return Math.floor(Math.random() * currentQueue.length);
    } else {
      // 正常模式：返回上一首
      return this.currentQueueIndex === 0 ? currentQueue.length - 1 : this.currentQueueIndex - 1;
    }
  }

  // 打乱播放列表
  private shufflePlaylist(): void {
    if (this.originalQueue.length === 0) {
      this.originalQueue = [...this.queueItems];
    }

    this.shuffledQueue = [...this.originalQueue];
    // Fisher-Yates 洗牌算法
    for (let i = this.shuffledQueue.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const temp = this.shuffledQueue[i];
      this.shuffledQueue[i] = this.shuffledQueue[j];
      this.shuffledQueue[j] = temp;
    }

    this.queueItems = this.shuffledQueue;
    this.currentQueueIndex = 0;
  }

  // 恢复原始播放列表
  private restoreOriginalPlaylist(): void {
    if (this.originalQueue.length > 0) {
      this.queueItems = [...this.originalQueue];
      this.currentQueueIndex = 0;
    }
  }

  // 获取当前播放列表
  getCurrentQueue(): avSession.AVQueueItem[] {
    return this.shuffleMode === 1 ? this.shuffledQueue : this.originalQueue;
  }

}


export interface ServiceListener {

  // onLoadChildren(): void
  //
  // onLoadItem(): void
  //
  // onSearch(): void
  //
  // onClick(): void
  //
  // onPrepare(): void
  //
  // onPrepareFromMediaId(): void
  //
  // onPrepareFromSearch(): void
  //
  // onPrepareFromUri(): void
  //
  onPlay(): void

  //
  // onPlayFromMediaId(): void
  //
  // onPlayFromSearch(): void
  //
  // onPlayFromUri(): void
  //
  // onSkipToQueueItem(): void
  //
  onPause(): void

  //
  onSkipToNext(): void

  //
  onSkipToPrevious(): void

  //
  onFastForward(): void

  //
  onRewind(): void

  //
  onStop(): void

  //
  onSeekTo(pos: number): void

  //
  // onSetRating(): void

  //循环模式
  onSetRepeatMode(repeatMode: number): void

  //
  // onSetShuffleMode(): void
  //
  // onCustomAction(): void
  //
  // onAddQueueItem(): void
  //
  // onAddQueueItemAt(): void
  //
  // onRemoveQueueItem(): void
  //
  // onRemoveQueueItemAt(): void

  //调整播放速度
  onSetPlaybackSpeed(speed: number): void

  //
  // onSetCaptioningEnabled(): void
  //
  // onSetVolumeTo(): void
  //
  // onAdjustVolume(): void
  //
  // onPlayMediaItem(): void
  //
  // onTaskRemoved(): void
  //
  // onClose(): void
  //
  // onDestroy(): void
}




function getNextTrackIndex() {
  throw new Error('Function not implemented.');
}
