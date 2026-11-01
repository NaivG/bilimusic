/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
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

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { MethodCall } from '@ohos/flutter_ohos';
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Share from './Share';

const TAG = 'MethodCallHandlerImpl';

export default class MethodCallHandlerImpl implements MethodCallHandler {
  private share: Share | null = null;

  constructor(share: Share) {
    this.share = share;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, "onMethodCall step in");
    let method: string = call.method;
    Log.i(TAG, "Received '" + method + "' message.");
    const isWithResult: boolean = call.method.endsWith('WithResult');
    try {
      switch (method) {
        case 'shareUri':
          this.share?.share(call.argument('uri') as string, null, call.argument('title') as string, false, result);
          if (!isWithResult) {
            result.success(null);
          }
          break;
        case 'share':
        case 'shareWithResult':
          // 官方 share_plus_platform_interface 只会发 `share`，文件与 URI 放在
          // 同一个参数表里（paths / mimeTypes / uri）；鸿蒙适配分支的 SPI 则改发
          // shareFiles / shareUri。两种形态都认，本包才能配官方 SPI 使用。
          if (call.hasArgument('paths')) {
            this.share?.shareFiles(
              call.argument('paths'),
              call.argument('mimeTypes'),
              call.argument('text'),
              call.argument('subject'),
              call.argument('title'),
              isWithResult,
              result);
          } else if (call.hasArgument('uri')) {
            this.share?.share(
              call.argument('uri') as string,
              null,
              call.argument('title') as string,
              isWithResult,
              result);
          } else {
            this.share?.share(
              call.argument('text') as string,
              call.argument('subject') as string,
              call.argument('title') as string,
              isWithResult,
              result);
          }
          if (!isWithResult) {
            result.success("dev.fluttercommunity.plus/share/unavailable");
          }
          break;
        case 'shareFiles':
        case 'shareFilesWithResult':
          this.share?.shareFiles(
            call.argument('paths'),
            call.argument('mimeTypes'),
            call.argument('text'),
            call.argument('title'),
            call.argument('subject'),
            isWithResult,
            result);
          if (!isWithResult) {
            result.success("dev.fluttercommunity.plus/share/unavailable");
          }
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (err) {
      Log.e(TAG, 'err:' + JSON.stringify(err));
    }
  }
}
