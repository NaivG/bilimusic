#pragma once

#ifndef FLUTTER_PLUGIN_BONSOIR_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_BONSOIR_WINDOWS_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <vector>

#include "bonsoir_broadcast.h"
#include "bonsoir_discovery.h"

using namespace flutter;

namespace bonsoir_windows {

  class BonsoirWindowsPlugin : public Plugin {
   public:
    static void RegisterWithRegistrar(PluginRegistrarWindows *registrar);

    BonsoirWindowsPlugin(BinaryMessenger *messenger);

    virtual ~BonsoirWindowsPlugin();

    // Disallow copy and assign.
    BonsoirWindowsPlugin(const BonsoirWindowsPlugin &) = delete;

    BonsoirWindowsPlugin &operator=(const BonsoirWindowsPlugin &) = delete;

    // Called when a method is called on this plugin's channel from Dart.
    void HandleMethodCall(const MethodCall<EncodableValue> &methodCall, std::unique_ptr<MethodResult<EncodableValue>> result);

   private:
    BinaryMessenger *messenger;
    std::map<int, std::unique_ptr<BonsoirBroadcast>> broadcasts;
    std::map<int, std::unique_ptr<BonsoirDiscovery>> discoveries;
    // 本仓库改动（见 VENDORED.md）：已停止、但可能还有一次 DNS-SD 回调在路上的对象。
    //
    // DnsServiceBrowseCancel / DnsServiceRegisterCancel 都是异步的，回调里直接把
    // pQueryContext 当 this 用；取消之后立刻 delete 就是 use-after-free
    // （0xc0000005，或者改写了已释放内存后过一阵子随机崩）。
    // 这里改成「停止后只 dispose()、不销毁」，挪进 retired 列表留到插件析构
    // （引擎退出）时统一释放。每次 start 才产生一个对象，数量有界，代价可忽略。
    std::vector<std::unique_ptr<BonsoirBroadcast>> retiredBroadcasts;
    std::vector<std::unique_ptr<BonsoirDiscovery>> retiredDiscoveries;

    void retireBroadcast(int id);

    void retireDiscovery(int id);
  };

}  // namespace bonsoir_windows

#endif
