# 架构与实现细节

## 总览

```
┌──────────────────────────────┐
│ 应用 / 浏览器 / Clash / 手机  │
└──────────────┬───────────────┘
               │ HTTP / SOCKS5（带认证）
               ▼
┌──────────────────────────────┐
│ mihomo（本地前端）            │
│  - mixed-port 17894          │
│  - DNS / 健康检查 / 局域网    │
└──────────────┬───────────────┘
               │ SOCKS5
               ▼
┌──────────────────────────────┐
│ usque（MASQUE 客户端）        │
│  - 本地 SOCKS5 17896          │
│  - HTTP/3 over QUIC/UDP 443  │
└──────────────┬───────────────┘
               │ MASQUE
               ▼
        Cloudflare WARP
               │
               ▼
            互联网
```

## 为什么用 usque + mihomo

### usque

- 使用 **MASQUE（HTTP/3 CONNECT-IP）**，跑在 UDP 443 上；
- 相比原生 WireGuard 的 UDP 2408，443/QUIC 更像普通网页流量，被针对性封锁的概率更低；
- 自带 WARP 账号注册（`usque register`），不需要邮箱或付费；
- 提供 SOCKS5 / HTTP 代理 / TUN 等多种出口，本项目只使用 SOCKS5。

### mihomo

- 成熟的代理前端，负责 HTTP/SOCKS5 入口、认证、DNS、健康检查；
- 支持热重载和外部控制器 API，方便脚本管理；
- 可以把同一个本地代理共享到局域网，或作为 Clash 的一个上游节点。

## 运行时文件

| 文件 | 说明 |
|---|---|
| `bin\usque.exe` | MASQUE 客户端（安装时下载） |
| `bin\mihomo.exe` | 代理前端（安装时下载） |
| `usque\config.json` | **WARP 账号身份**（私钥、token、地址），勿分享 |
| `warp.yaml` | mihomo 配置（端口、认证、DNS、上游） |
| `config.json` | warp-lite 自己的运行配置（端口/密码/路径） |
| `logs\` | 看门狗与运行日志 |

## 启动流程

1. `usque socks -b 127.0.0.1 -p 17896 -m 1280 -k 25s --always-reconnect`
   - 在 `usque/` 目录下运行，读取 `config.json` 里的 WARP 身份；
   - 建立 MASQUE 隧道，暴露本地 SOCKS5。
2. `mihomo -d <prefix> -f warp.yaml`
   - 监听 `127.0.0.1:17894`；
   - 上游指向 `127.0.0.1:17896`；
   - 所有流量 `MATCH,PROXY` → WARP。

## 看门狗

`watchdog.ps1` 每 60 秒调用一次 `warpctl.ps1 ensure`：

1. 前端端口没了 → 重启 mihomo；
2. usque 端口没了 → 重启 usque；
3. 端口在但健康检查连续失败 2 次 → 杀掉 usque 并重启；
4. 健康检查恢复 → 清零失败计数。

健康检查走 mihomo 控制器：

```
GET http://127.0.0.1:17895/proxies/WARP/delay?url=http://cp.cloudflare.com/generate_204&timeout=5000
Authorization: Bearer <secret>
```

## 安全设计

- 本地端口默认只绑定 `127.0.0.1`；
- HTTP/SOCKS 入口强制用户名/密码（安装时随机生成 18 位）；
- 控制器只监听 `127.0.0.1`，并带随机 secret；
- 项目不收集数据、不含遥测；
- WARP 身份只保存在本机，`.gitignore` 已排除。

## 已知边界

- MASQUE 的可用性依赖 Cloudflare 边缘与本地网络，无法保证 100% 在线；
- WARP 出口是共享的 Cloudflare 机房 IP，部分站点会拦截；
- 本项目不做多跳、不做流量伪装、不做抗审查增强——它只是 WARP 的一个好用封装。
