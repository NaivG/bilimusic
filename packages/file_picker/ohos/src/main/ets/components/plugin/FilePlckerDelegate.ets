/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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
import { util } from '@kit.ArkTS';
import FilePickerPlugin from "./FilePickerPlugin"
import { StreamHandler, EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  Ability,
  abilityAccessCtrl,
  bundleManager,
  common,
  PermissionRequestResult,
  Permissions,
  StartOptions,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import decodeURIComponent from '@ohos.util';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EventChannel, Log, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { FileInfo } from './FileInfo'
import { FileInfoBuilder } from './FileInfo'
import { FileUtils } from './FileUtils'
import List from '@ohos.util.List'
import { picker, WriteOptions } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const timestamp = Date.now();
const TAG: string = "FilePickerDelegate";

export class FilePickerDelegate {
  private permissionManager: PermissionManager | null = null;
  private eventSink: EventSink | null = null;
  private pendingResult: MethodResult | null = null;
  private isMultipleSelection: boolean = false;
  private loadDataToMemory: boolean = false;
  private type: string = "";
  private allowedExtensions: string[] = new Array;
  private ability: UIAbility | null = null;
  private context: common.UIAbilityContext | null = null;
  private audioSelectedUris: Array<string> = new Array
  private savaFilePath: Array<string> = new Array();
  private bytesList: Uint8Array[] = [];
  private sourceFd: number = -1;

  constructor(uiAbility: UIAbility) {
    this.ability = uiAbility;
  }

  async startFileExplorer(type: string, isMultipleSelection: boolean, withData: boolean,
    allowedExtensions: string[] | null | undefined,
    result: MethodResult) {
    if (!this.setPendingMethodCallAndResult(result)) {
      await this.cancelOperation();
    }
    this.type = type;
    this.isMultipleSelection = isMultipleSelection;
    this.loadDataToMemory = withData;
    if (allowedExtensions) {
      this.allowedExtensions = allowedExtensions;
    }
    this.startFileExplorerA();
  }

  async startFileExplorerA() {
    let want: Want | null = null;
    switch (this.type) {
      case "image": {
        let commonContext = this.ability?.context as common.UIAbilityContext;
        let photoPicker = new picker.PhotoViewPicker(commonContext);
        let photoSelectOptions = new picker.PhotoSelectOptions();
        photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        await photoPicker.select(photoSelectOptions).then(async (photoSelectResult) => {
          this.savaFilePath = photoSelectResult.photoUris
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
          }
          //this.bytes = await this.readFileData(photoSelectResult.photoUris[0]);
           // 逐个读取文件数据
           this.bytesList = [];
            for (const uri of photoSelectResult.photoUris) {
              const bytes = await this.readFileData(uri);
              this.bytesList.push(bytes);
            }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(photoSelectResult.photoUris)
          } else {
            this.handleSingleResult(photoSelectResult.photoUris[0]);
          }
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
          }
        }).catch((error: BusinessError) => {
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
        })
        break;
      }
      case "video": {
        let photoPicker = new picker.PhotoViewPicker();
        let photoSelectOptions = new picker.PhotoSelectOptions();
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.VIDEO_TYPE;
        photoPicker.select(photoSelectOptions).then(async (photoSelectResult) => {
          this.savaFilePath = photoSelectResult.photoUris
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
          }
          let selectedUris: Array<string> = photoSelectResult.photoUris;
          //this.bytes = await this.readFileData(selectedUris[0]);
          this.bytesList = [];
          for (const uri of selectedUris) {
             const bytes = await this.readFileData(uri);
             this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(selectedUris)
          } else {
            this.handleSingleResult(selectedUris[0]);
          }
          if (photoSelectResult == null || photoSelectResult.photoUris.length == 0) {
            await this.cancelOperation();
          }
        }).catch((error: BusinessError) => {
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
        })
        break;
      }
      case "audio": {
        let context = getContext(this) as common.UIAbilityContext;
        let audioPicker: picker.AudioViewPicker = new picker.AudioViewPicker(context);
        let audioSelectOptions = new picker.AudioSelectOptions();
        audioSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        audioPicker.select(audioSelectOptions).then(async (audioSelectResult) => {
          this.savaFilePath = audioSelectResult;
          if (audioSelectResult == null || audioSelectResult.length == 0) {
            await this.cancelOperation();
          }
          //this.bytes = await this.readFileData(audioSelectResult[0]);
          this.bytesList = [];
          for (const uri of audioSelectResult) {
            const bytes = await this.readFileData(uri);
            this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(audioSelectResult);
          } else {
            this.handleSingleResult(audioSelectResult[0]);
          }
          if (audioSelectResult == null || audioSelectResult.length == 0) {
            await this.cancelOperation();
          }
        }).catch((error: BusinessError) => {
          console.error('AudioViewPicker.select failed with err: ' + JSON.stringify(error));
        })
        break
      }
      case "media": {
        let photoPicker = new photoAccessHelper.PhotoViewPicker();
        let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
        photoSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        photoSelectOptions.MIMEType = this.resolveType(this.type) as photoAccessHelper.PhotoViewMIMETypes;
        photoPicker.select(photoSelectOptions).then(async (photoSelectResult) => {
          this.savaFilePath = photoSelectResult.photoUris;
          let selectedUris: Array<string> = photoSelectResult.photoUris;
          if (selectedUris == null || selectedUris.length == 0) {
            await this.cancelOperation();
          }
          //this.bytes = await this.readFileData(selectedUris[0]);
          this.bytesList = [];
          for (const uri of selectedUris) {
            const bytes = await this.readFileData(uri);
            this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(selectedUris)
          } else {
            this.handleSingleResult(selectedUris[0]);
          }
          if (selectedUris == null || selectedUris.length == 0) {
            await this.cancelOperation();
          }
        }).catch((error: BusinessError) => {
          console.error('PhotoViewPicker.select failed with err: ' + JSON.stringify(error));
        })
        break;
      }
      case "any": {
        let commonContext = this.ability?.context as common.UIAbilityContext;
        let documentPicker = new picker.DocumentViewPicker(commonContext);
        let documentSelectOptions = new picker.DocumentSelectOptions();
        documentSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        documentPicker.select(documentSelectOptions).then(async (documentSelectResult: Array<string>) => {
          this.savaFilePath = documentSelectResult
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
          let anySelectUris: Array<string> = documentSelectResult;
          //this.bytes = await this.readFileData(anySelectUris[0]);
          this.bytesList = [];
          for (const uri of anySelectUris) {
            const bytes = await this.readFileData(uri);
            this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(anySelectUris)
          } else {
            this.handleSingleResult(anySelectUris[0]);
          }
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
        }).catch((err: BusinessError) => {
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(err));
        });
        break
      }
      case "custom": {
        let commonContext = this.ability?.context as common.UIAbilityContext;
        let documentSelectOptions = new picker.DocumentSelectOptions();
        let documentPicker = new picker.DocumentViewPicker(commonContext);
        documentSelectOptions.maxSelectNumber = this.isMultipleSelection ? 9 : 1;
        documentSelectOptions.fileSuffixFilters = this.allowedExtensions;
        documentPicker.select(documentSelectOptions).then(async (documentSelectResult: Array<string>) => {
          this.savaFilePath = documentSelectResult;
          let anySelectUris: Array<string> = documentSelectResult;
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
          //this.bytes = await this.readFileData(anySelectUris[0]);
          this.bytesList = [];
          for (const uri of anySelectUris) {
            const bytes = await this.readFileData(uri);
            this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(anySelectUris)
          } else {
            this.handleSingleResult(anySelectUris[0]);
          }
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
        }).catch((err: BusinessError) => {
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(err));
        });
        break
      }
      case "dir": {
        let context = getContext(this) as common.UIAbilityContext;
        let documentPicker = new picker.DocumentViewPicker(context);
        let documentSelectOptions: picker.DocumentSelectOptions = {
          selectMode: 1
        }
        documentPicker.select(documentSelectOptions).then(async (documentSelectResult: Array<string>) => {
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
          let anySelectUris: Array<string> = documentSelectResult;
          //this.bytes = await this.readFileData(anySelectUris[0]);
          this.bytesList = [];
          for (const uri of anySelectUris) {
            const bytes = await this.readFileData(uri);
            this.bytesList.push(bytes);
          }
          if (this.isMultipleSelection) {
            this.handlingMultipleResults(anySelectUris)
          } else {
            this.handleSingleResult(anySelectUris[0]);
          }
          if (documentSelectResult == null || documentSelectResult.length == 0) {
            await this.cancelOperation();
          }
        }).catch((err: BusinessError) => {
          console.error('DocumentViewPicker.select failed with err: ' + JSON.stringify(err));
        });
        break
      }
    }
  }

  async handlingMultipleResults(uris: string[]) {
    let files: List<FileInfo> = new List();
    let count: number = uris.length;
    let currentItem = 0;
    while (currentItem < count) {
      let currentUri: string = uris[currentItem];
      if (this.ability?.context) {
        let file: FileInfo =
          await FileUtils.openFileStream(this.ability?.context, currentUri, this.loadDataToMemory) as FileInfo;
        if (file != null) {
          files.add(file);
          Log.d(TAG, "[MultiFilePick] File #" + currentItem + " - URI: " + currentUri);
        }
        currentItem++;
      }
    }
    this.finishWithSuccess(files);
  }

  async handleSingleResult(uris: string): Promise<void> {
    let files: List<FileInfo> = new List();
    if (this.ability?.context) {
      let file: FileInfo =
        await FileUtils.openFileStream(this.ability?.context, uris, this.loadDataToMemory) as FileInfo;
      if (file != null) {
        files.add(file);
      }
      if (!files.isEmpty()) {
        Log.d(TAG, "File path:" + files.toString())
        this.finishWithSuccess(files);
      } else {
        this.finishWithError("unknown_path", "Failed to retrieve path.");
      }
    }
  }

  saveFinishWithSuccess(data: string) {
    this.dispatchEventStatus(false);
    this.pendingResult?.success(data);
    this.clearPendingResult();
  }

  finishWithSuccess(data: List<FileInfo>) {
    this.dispatchEventStatus(false);
    let result: List<Map<string, Object>> | null = null;
    if (this.pendingResult != null) {
      if (data != null && !(data instanceof String)) {
        let files: List<Map<string, Object>> = new List();
        data.forEach((file) => {
          files.add(file.toMap());
        })
        result = files
      }
    }
    this.pendingResult?.success(result);
    this.clearPendingResult();
  }

  saveFile(fileNameArray: Array<string>, type: string, initialDirectory: string, allowedExtensions: Array<string>,
    result: MethodResult) {
    if (!this.setPendingMethodCallAndResult(result)) {
      this.finishWithAlreadyActiveError(result);
      return;
    }
    if (!this.bytesList || this.bytesList.length == 0) {
      this.finishWithError("", "Bytes are required on HarmonyOS & Android & IOS when saving a file");
    }

    if (this.bytesList && this.bytesList?.length > 0) {
      let documentSaveOptions: picker.DocumentSaveOptions | null = null
      documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.defaultFilePathUri = initialDirectory;
      if (allowedExtensions) {
        documentSaveOptions.fileSuffixChoices = allowedExtensions;
      }
      let commonContext = this.ability?.context as common.UIAbilityContext;
      let documentPicker = new picker.DocumentViewPicker(commonContext);
      let sourceFileNameList: Array<string> = [];
      // 通过选择文件的路径，获取文件名
      for (const item of this.savaFilePath) {
        const lastSlashIndex = item.lastIndexOf('/');
        const sourceFileName = item.substring(lastSlashIndex + 1);
        sourceFileNameList.push(sourceFileName);
      }
      if (this.savaFilePath && this.savaFilePath.length == 1) {
        // fileNameArray是 Default File Name 输入框的内容，如果为空，拉起文件选择器之后输入框有后缀（通过源文件获得）
        // documentSaveOptions.newFileNames是预设的文件名，拉起文件选择器自动显示在输入框中的
        let filePath: string = '';
        let hasExtension: boolean = hasFileExtension(filePath);
        const lastSlashIndex = this.savaFilePath[0].lastIndexOf('/');
        const sourceFileName = this.savaFilePath[0].substring(lastSlashIndex + 1);
        const sourceExt = getExtension(sourceFileName);
        if (!hasExtension) {
          filePath = fileNameArray[0] + sourceExt;
        } else {
          filePath = fileNameArray[0]
        }
        documentSaveOptions.newFileNames = [filePath];
      } else {
        documentSaveOptions.newFileNames = sourceFileNameList;
      }
      documentPicker.save(documentSaveOptions).then(async (documentSaveResult: Array<string>) => {
        if (documentSaveResult == null || documentSaveResult.length == 0) {
          //this.finishWithError("invalid_format_type","Can1t handle the provided file_type");//用例保持一致
          await this.cancelOperation();
        } else if (documentSaveResult && documentSaveResult.length == 1) {
          // 如果在这个位置添加后缀，错误码: 13900002 错误信息: No such file or directory
          this.singSave(documentSaveResult[0]);
        } else {
          //  选择多个文件后保存，只需要选择路径，不用添加文件名,重名自动加1
          this.multipleSave(documentSaveResult);
        }
        let originFileName = FileUtils.getFileName(documentSaveResult[0])
        let newFileName = FileUtils.urlDecodeManual(originFileName);
        let newSavePath = FileUtils.replaceFileName(documentSaveResult[0], originFileName, newFileName)
        this.saveFinishWithSuccess(newSavePath);
      }).catch((err: BusinessError) => {
        if (err.code == 13900001) {
          this.finishWithError(err.code.toString(), err.message + ", 此文件路径无权访问，只接受应用沙箱路径");
        } else {
          this.finishWithError(err.code.toString(), err.message);
        }
      });
    }
  }
  // 辅助函数：读取文件数据
  private async readFileData(uri: string): Promise<Uint8Array> {
    let fd: number | undefined;
    try {
      const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      this.sourceFd = file.fd;
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(this.sourceFd, buffer);
      return new Uint8Array(buffer);
    } finally {
      if (fd !== undefined) {
        fs.closeSync(fd);
      }
    }
  }

  multipleSave(photoSaveResultUri: Array<string>) {
    let targetFd: number | undefined;
    if (photoSaveResultUri.length > 1) {
      for (let i = 0; i < photoSaveResultUri.length; i++) {
        const targetFile: fs.File =
          fs.openSync(photoSaveResultUri[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        targetFd = targetFile.fd;
        fs.writeSync(targetFd, this.bytesList[i]?.buffer);
        fs.fsyncSync(targetFd); // 确保数据落盘
      }
    }
  }

  singSave(photoSaveResultUri: string) {
    let targetFd: number | undefined;

    try {
      const targetFile: fs.File =
        fs.openSync(photoSaveResultUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      targetFd = targetFile.fd;
      fs.writeSync(targetFd, this.bytesList[0]?.buffer);
      fs.fsyncSync(targetFd); // 确保数据落盘
    } catch (error) {
      const e = error as BusinessError;
      throw new Error(`savefile 文件复制失败: ${e.message}`);
    } finally {
      fs.closeSync(targetFd);
    }
  }

  private async cancelOperation(){
    this.pendingResult?.success(null);
    this.clearPendingResult();
    return;
  }

  finishWithError(errorCode: string, errorMessage: string) {
    if (this.pendingResult == null) {
      return;
    }
    this.dispatchEventStatus(false);
    this.pendingResult.error(errorCode, errorMessage, null);
    this.clearPendingResult();
  }

  dispatchEventStatus(status: boolean) {
    if (this.eventSink == null || this.type === ("dir")) {
      return;
    }
    this.eventSink.success(status)
  }

  setEventHandler(eventSink: EventSink) {
    this.eventSink = eventSink;
  }

  setPendingMethodCallAndResult(result: MethodResult): boolean {
    if (this.pendingResult != null) {
      return false;
    }
    this.pendingResult = result;
    return true;
  }

  finishWithAlreadyActiveError(result: MethodResult) {
    result.error("already_active", "File picker is already active", null)
  }

  clearPendingResult() {
    this.pendingResult = null;
  }

  resolveType(type: string) {
    switch (type) {
      case "image":
        return photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      case "video":
        return photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      case "media":
        return photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      case "any":
      default:
        return null;
    }
  }

  async isPermissionGranted(permission: Permissions): Promise<boolean> {
    let tokenId: number = 0;
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let bundleInfo: bundleManager.BundleInfo =
      await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
    tokenId = appInfo.accessTokenId;
    grantStatus = await atManager.checkAccessToken(tokenId, permission);
    return grantStatus == -1;
  }

  askForPermission(permissionName: Permissions) {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let context: Context = this.ability?.context as Context
    atManager.requestPermissionsFromUser(context, [permissionName]).then((data: PermissionRequestResult) => {
    }).catch((err: BusinessError) => {
      console.error('data:' + JSON.stringify(err));
    });
  }

  //
  clearBytesList():void {
   this.bytesList = [];
  }

  // save 通道由 Dart 直接带 bytes 过来，先放到 bytesList，saveFile() 再落盘。
  setPendingBytes(bytes: Uint8Array | null | undefined):void {
    this.bytesList = bytes ? [bytes] : [];
  }
}

export interface PermissionManager {
  ability: UIAbility | null

  isPermissionGranted(permission: Permissions): Promise<boolean>;

  askForPermission(permissionName: Permissions, requestCode: number): void;
}

class PermissionManagerClass implements PermissionManager {
  public ability: UIAbility | null = null;

  constructor(ability: UIAbility) {
    this.ability = ability
  }

  async isPermissionGranted(permission: Permissions): Promise<boolean> {
    let tokenId: number = 0;
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let bundleInfo: bundleManager.BundleInfo =
      await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
    tokenId = appInfo.accessTokenId;
    grantStatus = await atManager.checkAccessToken(tokenId, permission);
    return grantStatus == -1;
  }

  askForPermission(permissionName: Permissions, requestCode: number) {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let context: Context = this.ability?.context as Context
    atManager.requestPermissionsFromUser(context, [permissionName]).then((data: PermissionRequestResult) => {
    }).catch((err: BusinessError) => {
      console.error('data:' + JSON.stringify(err));
    });
  }
}
/**
 * 获取文件扩展名
 */
function getExtension(fileName: string): string {
  const name = fileName.trim();
  const lastDotIndex = name.lastIndexOf('.');
  // 排除特殊情况
  if (lastDotIndex <= 0 ||
    lastDotIndex === name.length - 1 ||
  name.startsWith('.')) {
    return '';
  }
  // 返回包含点的扩展名（如 .txt、.jpg）
  return name.substring(lastDotIndex).toLowerCase();
}

/**
 * 判断路径是否包含扩展名
 * @param filePath 文件路径
 * @returns 是否包含扩展名
 */
function hasFileExtension(filePath: string): boolean {
  if (!filePath || filePath.trim() === '') {
    return false;
  }
  // 获取文件名（不包含路径）
  const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
  // 排除没有文件名的情况
  if (!fileName || fileName.trim() === '') {
    return false;
  }
  // 查找最后一个点号的位置
  const lastDotIndex = fileName.lastIndexOf('.');
  return lastDotIndex > 0 && lastDotIndex < fileName.length - 1;
}