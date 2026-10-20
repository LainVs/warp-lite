// warp-lite · Clash Verge 配置增强脚本
//
// 用法：
//   1. 打开 Clash Verge → 订阅 → 当前订阅 → 右键「编辑脚本」（或 profiles 目录里的 script 文件）
//   2. 把本文件内容粘进去，按需修改下面的 CONFIG
//   3. 保存并重新应用订阅
//
// 它会：
//   - 注入一个指向本机 warp-lite 的 HTTP 代理节点
//   - 新建「总出口」fallback 组：WARP 优先，WARP 不可用时自动用机场节点
//   - 把最后一条 MATCH 规则指向「总出口」
//   - 可选：把 AI 域名单独指向一个手动选择的组

const CONFIG = {
  warp: {
    name: 'WARP Lite',
    server: '127.0.0.1',
    port: 17894,
    username: 'warp',
    password: 'REPLACE_WITH_YOUR_PASSWORD', // warpctl.bat status
  },
  exitGroup: '总出口',
  aiGroup: 'AI 专用',            // 设为 null 可关闭 AI 分组
  aiNodeGroup: '自动选择',        // AI 组默认选哪个（通常是你的机场 url-test 组）
  primaryGroup: 'XFLTD',         // 你订阅里用来兜底的主选择组
  aiDomains: [
    'chatgpt.com', 'openai.com', 'chat.com', 'sora.com',
    'oaistatic.com', 'oaiusercontent.com',
    'anthropic.com', 'claude.ai', 'claudeusercontent.com',
    'gemini.google.com', 'bard.google.com', 'aistudio.google.com',
    'makersuite.google.com', 'notebooklm.google.com',
    'generativelanguage.googleapis.com',
    'perplexity.ai', 'x.ai', 'grok.com',
    'copilot.microsoft.com', 'poe.com', 'midjourney.com', 'character.ai',
  ],
};

function main(config) {
  const w = CONFIG.warp;
  config.proxies = Array.isArray(config.proxies) ? config.proxies : [];

  const existing = config.proxies.find(p => p && p.name === w.name);
  const def = {
    name: w.name,
    type: 'http',
    server: w.server,
    port: w.port,
    username: w.username,
    password: w.password,
  };
  if (existing) Object.assign(existing, def);
  else config.proxies.push(def);

  const groups = Array.isArray(config['proxy-groups'])
    ? config['proxy-groups']
    : (config['proxy-groups'] = []);

  // 把 WARP 放进主选择组
  for (const g of groups) {
    if (g && g.name === CONFIG.primaryGroup && Array.isArray(g.proxies) && !g.proxies.includes(w.name)) {
      g.proxies.unshift(w.name);
    }
  }

  // AI 专用组
  if (CONFIG.aiGroup && !groups.some(g => g && g.name === CONFIG.aiGroup)) {
    const nodeNames = config.proxies
      .map(p => p && p.name)
      .filter(n => n && n !== w.name && n !== 'DIRECT' && n !== 'REJECT');
    groups.push({
      name: CONFIG.aiGroup,
      type: 'select',
      proxies: [CONFIG.aiNodeGroup, '故障转移'].concat(nodeNames),
    });
  }

  // 总出口：WARP 优先，挂了自动用机场
  if (!groups.some(g => g && g.name === CONFIG.exitGroup)) {
    groups.push({
      name: CONFIG.exitGroup,
      type: 'fallback',
      url: 'http://cp.cloudflare.com/generate_204',
      interval: 60,
      proxies: [w.name, CONFIG.aiNodeGroup, 'DIRECT'],
    });
  }

  // AI 规则
  const rules = Array.isArray(config.rules) ? config.rules : (config.rules = []);
  const aiRules = CONFIG.aiGroup
    ? CONFIG.aiDomains.map(d => `DOMAIN-SUFFIX,${d},${CONFIG.aiGroup}`)
    : [];
  config.rules = aiRules.concat(rules);

  // MATCH -> 总出口
  for (let i = 0; i < config.rules.length; i++) {
    if (typeof config.rules[i] === 'string' && config.rules[i].toUpperCase().startsWith('MATCH,')) {
      config.rules[i] = 'MATCH,' + CONFIG.exitGroup;
    }
  }

  return config;
}
