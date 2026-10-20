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
//   - 把常见 AI 域名单独指向「AI 专用」组（可在组里手动选节点）

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
};

// 常见 AI 服务（按域名后缀匹配）
const AI_DOMAINS = [
  // OpenAI
  'chatgpt.com', 'openai.com', 'chat.com', 'sora.com', 'oaistatic.com', 'oaiusercontent.com',
  'openai.azure.com',
  // Anthropic / Claude
  'anthropic.com', 'claude.ai', 'claude.com', 'claudeusercontent.com',
  // Google Gemini / DeepMind
  'gemini.google.com', 'bard.google.com', 'aistudio.google.com', 'makersuite.google.com',
  'notebooklm.google.com', 'generativelanguage.googleapis.com', 'aiplatform.googleapis.com',
  'ai.google.dev', 'deepmind.google', 'deepmind.com', 'labs.google',
  // Microsoft / GitHub Copilot
  'copilot.microsoft.com', 'copilot.cloud.microsoft', 'sydney.bing.com', 'edgeservices.bing.com',
  'githubcopilot.com',
  // Search / chat
  'perplexity.ai', 'x.ai', 'grok.com', 'poe.com', 'character.ai',
  // Model providers
  'mistral.ai', 'cohere.com', 'groq.com', 'together.ai', 'together.xyz', 'openrouter.ai',
  'replicate.com', 'huggingface.co', 'hf.co', 'stability.ai',
  // Image / video / audio
  'midjourney.com', 'elevenlabs.io', 'suno.com', 'suno.ai', 'udio.com', 'runwayml.com',
  'pika.art', 'lumalabs.ai', 'ideogram.ai', 'leonardo.ai', 'blackforestlabs.ai',
  'klingai.com', 'hailuoai.com', 'minimax.io', 'minimaxi.com', 'heygen.com', 'synthesia.io',
  // Coding assistants
  'cursor.com', 'cursor.sh', 'windsurf.com', 'codeium.com', 'tabnine.com',
  'v0.dev', 'v0.app', 'bolt.new', 'lovable.dev',
];

// 精确域名（避免把整个 githubusercontent 都路由走）
const AI_EXACT_DOMAINS = [
  'copilot-proxy.githubusercontent.com',
];

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
    ? AI_DOMAINS.map(d => `DOMAIN-SUFFIX,${d},${CONFIG.aiGroup}`)
      .concat(AI_EXACT_DOMAINS.map(d => `DOMAIN,${d},${CONFIG.aiGroup}`))
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
