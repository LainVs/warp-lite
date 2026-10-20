# 接入 Clash Verge / mihomo

warp-lite 对外就是一个普通的 **HTTP 代理**（带用户名/密码），所以任何支持 HTTP 代理的客户端都能接。

## 方式一：手动加一个节点（最简单）

1. 先确认 warp-lite 在运行：

   ```powershell
   C:\Users\<you>\AppData\Local\warp-lite\warpctl.bat status
   ```

   记下 `proxy`、`username`、`password`。

2. 在 Clash Verge 的订阅合并配置里加入：

   ```yaml
   prepend-proxies:
     - name: WARP Lite
       type: http
       server: 127.0.0.1
       port: 17894
       username: warp
       password: "你的密码"
   ```

   或者直接把 [`warp-node.yaml`](warp-node.yaml) 的内容合并进你的配置。

3. 在代理组里选择 `WARP Lite` 即可。

> 注意：如果 Clash 里同时有 `WARP Lite` 和别的代理，建议把它放进一个 **fallback** 组（WARP 优先），这样 WARP 挂了会自动切回机场节点。

## 方式二：配置增强脚本（推荐，订阅更新不丢）

Clash Verge 支持在每次生成配置时执行一个 JS 脚本。把 [`clash-verge-enhance.js`](clash-verge-enhance.js) 的内容粘到：

> Clash Verge → 订阅 → 当前订阅 → 编辑脚本

然后修改脚本顶部的 `CONFIG`：

```js
const CONFIG = {
  warp: {
    name: 'WARP Lite',
    server: '127.0.0.1',
    port: 17894,
    username: 'warp',
    password: '你的密码',
  },
  primaryGroup: 'XFLTD',   // 你订阅里的主选择组
  aiGroup: 'AI 专用',
  aiNodeGroup: '自动选择',
  // ...
};
```

保存并重新应用订阅。脚本会自动：

- 注入 `WARP Lite` 节点；
- 把它放进你的主选择组；
- 新建一个 `总出口` fallback 组（WARP 优先，失败自动用机场）；
- 新建 `AI 专用` 组并把常见 AI 域名路由过去；
- 把最后的 `MATCH` 指向 `总出口`。

AI 域名清单在脚本顶部的 `AI_DOMAINS` / `AI_EXACT_DOMAINS`，可自行增删。默认覆盖 60+ 服务：OpenAI / Anthropic Claude / Google Gemini / Microsoft Copilot / GitHub Copilot / Perplexity / xAI Grok / Mistral / Cohere / Groq / OpenRouter / HuggingFace / Midjourney / Suno / Runway / Cursor / Windsurf 等。

## 方式三：系统代理

不装 Clash 也可以。把 Windows 系统代理设为：

- 地址：`127.0.0.1`
- 端口：`17894`
- 用户名/密码：`warpctl.bat status` 里显示的

或者用浏览器插件（SwitchyOmega 等）单独配置。
