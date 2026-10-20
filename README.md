# warp-lite

> 一个面向 Windows 的 **Cloudflare WARP 一键客户端**：自动注册免费 WARP 账号，通过 **MASQUE / HTTP-3（QUIC 443）** 建立隧道，对外提供本地 HTTP/SOCKS5 代理，可选接入 Clash Verge、局域网共享给手机。
>
> 不用买机场、不用找免费节点、不用账号密码 —— 装完就能用。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey.svg)]()

---

## 它是什么

`warp-lite` 不是一个"机场"，也不是自建服务器。它把 **Cloudflare 官方的免费 WARP 网络** 封装成了一个开箱即用的本地代理：

```
应用 / 浏览器 / Clash
        │
        ▼
127.0.0.1:17894  (mihomo 前端，HTTP/SOCKS5，带认证)
        │
        ▼
127.0.0.1:17896  (usque: MASQUE over QUIC/UDP 443)
        │
        ▼
Cloudflare WARP  →  互联网
```

- **usque** 是第三方开源的 WARP 客户端，使用 MASQUE 协议（HTTP/3），比传统 WireGuard 的 UDP 2408 更容易穿过网络限制；
- **mihomo** 只做本地代理前端：提供 HTTP/SOCKS5 入口、DNS、健康检查、局域网共享；
- WARP 账号由 `usque register` 现场注册，**不需要任何账号、邮箱或付费**。

## 特性

- ✅ 一键安装：自动下载依赖、注册 WARP、写配置、设开机自启
- ✅ 免费无限量（Cloudflare WARP 免费档）
- ✅ MASQUE / QUIC 443，抗封锁能力优于原生 WireGuard
- ✅ 本地 HTTP + SOCKS5 混合代理，带用户名/密码
- ✅ 可选局域网共享（手机/平板同一 Wi-Fi 直接用）
- ✅ 可选接入 Clash Verge，作为普通节点使用
- ✅ 守护进程：隧道假死自动重启
- ✅ 无 Python / Node 依赖，只用 Windows 自带 PowerShell
- ✅ 卸载干净：账号、配置、服务、自启项一并移除

## 快速开始（Windows 10/11）

```powershell
git clone https://github.com/LainVs/warp-lite.git
cd warp-lite
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装完成后：

```powershell
# 查看状态 / 代理地址 / 账号密码
.\warpctl.bat status

# 测试出口
.\warpctl.bat test

# 启动 / 停止 / 重启
.\warpctl.bat start
.\warpctl.bat stop
.\warpctl.bat restart
```

默认代理：

- 地址：`127.0.0.1:17894`
- 协议：HTTP / SOCKS5 均可
- 用户名 / 密码：安装时随机生成，`warpctl.bat status` 可查看

## 常用参数

```powershell
# 自定义端口
.\install.ps1 -Port 17894 -SocksPort 17896 -CtrlPort 17895

# 开启局域网共享（手机会用）
.\install.ps1 -Lan

# 安装到自定义目录
.\install.ps1 -Prefix D:\Tools\warp-lite

# 使用 GitHub 镜像下载依赖（国内网络）
.\install.ps1 -Mirror https://ghproxy.net/

# 已有二进制时离线安装
.\install.ps1 -UsquePath C:\path\usque.exe -MihomoPath C:\path\mihomo.exe

# 不设置开机自启
.\install.ps1 -NoAutostart
```

## 接入 Clash Verge

安装后，在 Clash Verge 里新增一个 **HTTP 代理节点**：

```yaml
proxies:
  - name: WARP Lite
    type: http
    server: 127.0.0.1
    port: 17894
    username: warp
    password: "<安装时生成的密码>"
```

然后在代理组里选择它即可。也可以参考 [`clash/`](clash/) 里的示例，把它插进现有订阅的合并配置。

> 更完整的做法：用 Clash Verge 的「配置增强脚本」在每次生成配置时自动注入节点，见 [`clash/clash-verge-enhance.js`](clash/clash-verge-enhance.js)。

## 手机共享（可选）

```powershell
.\warpctl.bat lan on
```

它会：

1. 把 `allow-lan` 打开；
2. 提示你以管理员身份放行防火墙端口；
3. 打印电脑的局域网 IP、端口、用户名和密码。

手机连同一个 Wi-Fi，在 Wi-Fi 设置里配置 HTTP 代理即可。

## 工作原理

| 组件 | 作用 |
|---|---|
| `usque.exe` | 注册 WARP 账号，建立 MASQUE（HTTP/3 over QUIC 443）隧道，暴露本地 SOCKS5 |
| `mihomo.exe` | 本地 HTTP/SOCKS 前端、DNS、认证、局域网共享、健康检查 |
| `warpctl.ps1` | 启停、状态、测试、局域网开关 |
| `watchdog.ps1` | 每 60 秒检查隧道；假死自动重启 usque |
| `config.json` | 端口、认证、路径等运行配置 |
| `warp.yaml` | mihomo 前端配置 |

详细说明见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 已知限制

- **出口是 Cloudflare 机房 IP**，不是住宅 IP。Google、OpenAI、流媒体等可能拒绝或触发验证——这类站点请走你自己的干净节点。
- **速度不保证**。WARP 免费档是 best-effort；晚高峰/被 QoS 时可能只有 1~5 Mbps，甚至间歇超时。
- **抗封锁是动态的**。MASQUE/QUIC 通常比 WireGuard 稳，但并非永远可用；网络环境变化时可能需要重启服务。
- **不适合敏感用途**。不要用它登录银行、公司内网等；出口不是你自己的。
- 仅支持 **Windows 10/11**（PowerShell 5.1+）。macOS/Linux 可参考 usque + mihomo 自行组装。

## 安全说明

- 本地代理默认只监听 `127.0.0.1`，并带随机用户名/密码；
- 开启 `-Lan` 后会监听局域网，请只在可信 Wi-Fi 使用；
- 项目不收集任何数据、不含遥测、不内置任何人的 WARP 凭据；
- WARP 账号在安装时现场注册，保存在本机 `usque/config.json`，请勿分享。

## 合规声明

- 本项目仅封装 Cloudflare 官方免费 WARP 服务，依赖 [usque](https://github.com/Diniboy1123/usque)（MIT）与 [mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0）；
- 使用前请确认符合你所在地区的法律法规以及 Cloudflare 的服务条款；
- 作者不对因使用本项目产生的任何后果负责。

## License

本项目代码采用 [MIT](LICENSE)。第三方依赖遵循其各自许可证：

- usque：MIT
- mihomo：GPL-3.0

仓库不包含第三方二进制，安装时从官方 Release 下载。
