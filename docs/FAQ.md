# 常见问题

## 安装时报“无法下载 usque / mihomo”

GitHub 在部分网络下不可达。可以：

1. 使用镜像：

   ```powershell
   .\install.ps1 -Mirror https://ghproxy.net/
   ```

2. 手动下载后离线安装：

   - usque：<https://github.com/Diniboy1123/usque/releases>
   - mihomo：<https://github.com/MetaCubeX/mihomo/releases>（选 `mihomo-windows-amd64-v*.zip`）

   ```powershell
   .\install.ps1 -UsquePath C:\path\usque.exe -MihomoPath C:\path\mihomo.exe
   ```

## 安装时注册 WARP 失败

`usque register` 需要访问 Cloudflare 的 API。如果当前网络完全无法访问，先临时挂一个能用的代理再安装；或者把已注册好的 `usque/config.json` 放进安装目录后重跑安装。

## 代理连不上 / 全部超时

按顺序检查：

```powershell
.\warpctl.bat status
```

- 前端 `DOWN`：`.\warpctl.bat start`
- usque `DOWN`：看 `logs\watchdog.log`，或手动 `.\warpctl.bat restart`
- 两个都 `UP` 但 health `FAILED`：说明 WARP 隧道暂时不可用（常见于晚高峰），等一会儿或换网络。
- 想看真实请求：把浏览器代理设为 `127.0.0.1:17894`，访问 <https://www.cloudflare.com/cdn-cgi/trace>，应看到 `warp=on`。

## 速度很慢

WARP 免费档是 best-effort：

- 晚高峰/被 QoS 时可能只有 1~5 Mbps；
- MASQUE/QUIC 在某些网络下会被限速；
- 可以尝试换网络（手机热点/其他 Wi-Fi），或重启服务换一个 Cloudflare 边缘。

## 某些网站打不开 / 提示 VPN

WARP 的出口是 Cloudflare 机房 IP，Google、OpenAI、流媒体等会主动拦截。解决办法是让这些域名走你自己的干净节点（住宅 IP 或支持解锁的机场），不要走 WARP。

## 手机怎么用

```powershell
.\warpctl.bat lan on
```

按提示放行防火墙端口，然后手机连同一个 Wi-Fi，设置 HTTP 代理为电脑 IP:17894，用户名/密码见 `status`。

注意：只有遵守系统代理的 App 会走；要让所有 App 走，可以在手机上装 Clash（FlClash / Clash Meta），把 `电脑IP:17894` 添加为 HTTP 节点并开 VPN 模式。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

保留配置：`-KeepConfig`。

## 会不会收集我的数据

不会。项目没有遥测、没有服务器、不上报任何东西。唯一的网络请求是 Cloudflare WARP 本身，以及安装时从 GitHub 下载二进制。
