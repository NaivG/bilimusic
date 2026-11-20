#include "utilities.h"

#include <windows.h>

#include <regex>

namespace bonsoir_windows {
  std::wstring toUtf16(const std::string string) {
    // see https://stackoverflow.com/a/69410299/8707976

    if (string.empty()) {
      return L"";
    }

    auto sizeNeeded = MultiByteToWideChar(CP_UTF8, 0, &string.at(0), (int)string.size(), nullptr, 0);
    if (sizeNeeded <= 0) {
      // 本仓库改动：这里原来 throw std::runtime_error。转换失败只可能来自对端 mDNS
      // 里的脏字节（见 VENDORED.md），而抛出的异常会穿过 C 回调 / 平台通道 →
      // std::terminate → abort()。
      // 返回空串让上层按"名字为空"降级，绝不把异常带出边界。
      // 错误码见 https://docs.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-multibytetowidechar
      return L"";
    }

    std::wstring result(sizeNeeded, 0);
    MultiByteToWideChar(CP_UTF8, 0, &string.at(0), (int)string.size(), &result.at(0), sizeNeeded);
    return result;
  }

  std::string toUtf8(const std::wstring wide_string) {
    // see https://stackoverflow.com/a/69410299/8707976

    if (wide_string.empty()) {
      return "";
    }

    auto sizeNeeded = WideCharToMultiByte(CP_UTF8, 0, &wide_string.at(0), (int)wide_string.size(), nullptr, 0, nullptr, nullptr);
    if (sizeNeeded <= 0) {
      // 本仓库改动：同 toUtf16()，对端数据里的孤立代理项会让转换失败。
      // 异常穿出 C 回调等于进程 abort，这里直接返回空串。
      return "";
    }

    std::string result(sizeNeeded, 0);
    WideCharToMultiByte(CP_UTF8, 0, &wide_string.at(0), (int)wide_string.size(), &result.at(0), sizeNeeded, nullptr, nullptr);
    return result;
  }

  std::tuple<std::string, std::string> parseBonjourFqdn(const std::string fqdn) {
    std::regex regexPattern("^(.*?)\\._(.*?)\\.?(?:local)?\\.?$");
    std::smatch match;

    if (std::regex_search(fqdn, match, regexPattern)) {
      std::string serviceName = match[1].str();
      size_t pos = serviceName.find_last_not_of(" \t\r\n");
      if (pos != std::string::npos) {
        serviceName.erase(pos + 1);
      }

      std::string serviceType = "_" + match[2].str();

      return {serviceName, serviceType};
    }

    return {"", ""};
  }

  std::wstring getComputerName() {
    DWORD size = 0;
    GetComputerNameEx(ComputerNameDnsHostname, nullptr, &size);
    if (size == 0) {
      // 本仓库改动：不要 throw（见 VENDORED.md），广播侧按"拿不到主机名"降级。
      return L"";
    }
    std::vector<wchar_t> computerName(size);
    if (!GetComputerNameEx(ComputerNameDnsHostname, &computerName[0], &size)) {
      return L"";
    }
    return &computerName[0];
  }
}  // namespace bonsoir_windows