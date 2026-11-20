#pragma once

#include "bonsoir_windows_plugin.h"

#include <flutter/standard_method_codec.h>

using namespace flutter;

namespace bonsoir_windows {
  void BonsoirWindowsPlugin::RegisterWithRegistrar(PluginRegistrarWindows *registrar) {
    auto messenger = registrar->messenger();
    auto channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, "fr.skyost.bonsoir", &StandardMethodCodec::GetInstance()
    );
    auto plugin = std::make_unique<BonsoirWindowsPlugin>(messenger);
    channel->SetMethodCallHandler(
      [pluginPtr = plugin.get()](const auto &call, auto result) {
        pluginPtr->HandleMethodCall(call, std::move(result));
      }
    );
    registrar->AddPlugin(std::move(plugin));
  }

  BonsoirWindowsPlugin::BonsoirWindowsPlugin(BinaryMessenger *messenger)
    : messenger(messenger) {}

  BonsoirWindowsPlugin::~BonsoirWindowsPlugin() {
    // The engine is shutting down: no channel may be touched from here on.
    for (auto &[id, broadcast] : broadcasts) {
      broadcast->detachFromEngine();
    }
    for (auto &[id, discovery] : discoveries) {
      discovery->detachFromEngine();
    }
    // 兜底：retired 里的对象在 retire 时已经 dispose() 过（eventChannel 为 null），
    // 这里再标一次 engineGone，防止将来改动后它们又在引擎走后去碰通道。
    for (auto &broadcast : retiredBroadcasts) {
      broadcast->detachFromEngine();
    }
    for (auto &discovery : retiredDiscoveries) {
      discovery->detachFromEngine();
    }
    broadcasts.clear();
    discoveries.clear();
    // 本仓库改动：retired 里的对象同样可能还有一次回调在路上，但引擎/进程已经在
    // 退出，这里只能直接释放（与上游原有行为一致）。
    retiredBroadcasts.clear();
    retiredDiscoveries.clear();
  }

  void BonsoirWindowsPlugin::retireBroadcast(int id) {
    auto iterator = broadcasts.find(id);
    if (iterator == broadcasts.end()) {
      return;
    }
    // 先 dispose()：销毁消息窗口、摘掉事件通道，之后哪怕还有注册/取消回调过来，
    // 也只会落进 isRunning()==false 的分支，不会再往 Dart 推事件。
    iterator->second->dispose();
    retiredBroadcasts.push_back(std::move(iterator->second));
    broadcasts.erase(iterator);
  }

  void BonsoirWindowsPlugin::retireDiscovery(int id) {
    auto iterator = discoveries.find(id);
    if (iterator == discoveries.end()) {
      return;
    }
    // 同上。注意 stop() 里的 DnsServiceBrowseCancel 是异步的，回调仍会带着
    // pQueryContext = 这个对象指针回来；只要对象还活着就不会 use-after-free。
    iterator->second->dispose();
    retiredDiscoveries.push_back(std::move(iterator->second));
    discoveries.erase(iterator);
  }

  void BonsoirWindowsPlugin::HandleMethodCall(const MethodCall<EncodableValue> &methodCall, std::unique_ptr<MethodResult<EncodableValue>> result) {
    const auto &method = methodCall.method_name();
    const auto *arguments = std::get_if<EncodableMap>(methodCall.arguments());
    const auto id = std::get<int>(arguments->find(EncodableValue("id"))->second);
    if (method.compare("broadcast.initialize") == 0) {
      std::map<std::string, std::string> attributes = std::map<std::string, std::string>();
      EncodableMap encodedAttributes = std::get<EncodableMap>(arguments->find(EncodableValue("service.attributes"))->second);
      for (auto const &[key, value] : encodedAttributes) {
        attributes.insert({std::get<std::string>(key), std::get<std::string>(value)});
      }
      std::vector<std::string> hostAddresses = std::vector<std::string>();
      auto hostAddressesValue = arguments->find(EncodableValue("service.hostAddresses"));
      if (hostAddressesValue != arguments->end() && !hostAddressesValue->second.IsNull()) {
        EncodableList encodedHostAddresses = std::get<EncodableList>(hostAddressesValue->second);
        for (auto const &address : encodedHostAddresses) {
          hostAddresses.push_back(std::get<std::string>(address));
        }
      }
      auto hostnameValue = arguments->find(EncodableValue("service.hostname"));
      std::optional<std::string> hostname;
      if (hostnameValue == arguments->end() || hostnameValue->second.IsNull()) {
        hostname = std::optional<std::string>();
      } else {
        hostname = std::get<std::string>(hostnameValue->second);
      }
      std::unique_ptr<BonsoirService> servicePtr = std::make_unique<BonsoirService>(
        std::get<std::string>(arguments->find(EncodableValue("service.name"))->second),
        std::get<std::string>(arguments->find(EncodableValue("service.type"))->second),
        std::get<int>(arguments->find(EncodableValue("service.port"))->second),
        hostAddresses,
        hostname,
        attributes
      );
      broadcasts[id] = std::make_unique<BonsoirBroadcast>(
        id,
        std::get<bool>(arguments->find(EncodableValue("printLogs"))->second),
        messenger,
        std::move(servicePtr)
      );
      result->Success(EncodableValue(true));
    } else if (method.compare("broadcast.start") == 0) {
      auto iterator = broadcasts.find(id);
      if (iterator == broadcasts.end()) {
        result->Success(EncodableValue(false));
        return;
      }
      iterator->second->start();
      result->Success(EncodableValue(true));
    } else if (method.compare("broadcast.stop") == 0) {
      auto iterator = broadcasts.find(id);
      if (iterator == broadcasts.end()) {
        result->Success(EncodableValue(false));
        return;
      }
      iterator->second->stop();
      iterator->second->disposeAfterStreamCancel([this](int stoppedId) {
        retireBroadcast(stoppedId);
      });
      result->Success(EncodableValue(true));
    } else if (method.compare("discovery.initialize") == 0) {
      discoveries[id] = std::make_unique<BonsoirDiscovery>(
        id,
        std::get<bool>(arguments->find(EncodableValue("printLogs"))->second),
        messenger,
        std::get<std::string>(arguments->find(EncodableValue("type"))->second)
      );
      result->Success(EncodableValue(true));
    } else if (method.compare("discovery.start") == 0) {
      auto iterator = discoveries.find(id);
      if (iterator == discoveries.end()) {
        result->Success(EncodableValue(false));
        return;
      }
      iterator->second->start();
      result->Success(EncodableValue(true));
    } else if (method.compare("discovery.resolveService") == 0) {
      auto iterator = discoveries.find(id);
      if (iterator == discoveries.end()) {
        result->Success(EncodableValue(false));
        return;
      }
      iterator->second->resolveService(
        std::get<std::string>(arguments->find(EncodableValue("name"))->second),
        std::get<std::string>(arguments->find(EncodableValue("type"))->second)
      );
      result->Success(EncodableValue(true));
    } else if (method.compare("discovery.supportsMdnsHostname") == 0) {
      result->Success(EncodableValue(true));
    } else if (method.compare("discovery.stop") == 0) {
      auto iterator = discoveries.find(id);
      if (iterator == discoveries.end()) {
        result->Success(EncodableValue(false));
        return;
      }
      iterator->second->stop();
      iterator->second->disposeAfterStreamCancel([this](int stoppedId) {
        retireDiscovery(stoppedId);
      });
      result->Success(EncodableValue(true));
    } else {
      result->NotImplemented();
    }
  }
}  // namespace bonsoir_windows
