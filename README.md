# openvpn-cross

开源示例：展示如何用 OpenVPN 打造“云端入口 + 内网回程 + 动态路由同步”的双站部署。仓库只包含通用脚本与模板，不含任何生产密钥、备份或个性化拓扑数据。所有敏感配置都放在 `.env` 或本地未入库的目录中。

## 特色

- **双入口架构**：支持公网与局域网两个 VPN Server，同一个地址池，客户端可按优先级择路。
- **后端回程隧道**：脚本演示如何在两台服务器之间同步 /32 主机路由，让跨入口的 10.8.0.x 客户端互通。
- **macOS 自动化**：提供 launchd plist 样例和若干 Bash 工具，方便在 macOS 上启动、同步路线、调试。

## 快速开始

1. 克隆仓库：
   ```bash
   git clone https://github.com/<your-account>/openvpn-cross.git
   cd openvpn-cross
   ```
2. 复制变量样例并填写真实信息：
   ```bash
   cp .env.example .env
   # 按需修改云端主机、SSH key、后端网段等
   ```
3. 根据 `docs/ARCHITECTURE.md` 调整 OpenVPN 服务器配置（所有 `.ovpn`、`ccd/`、`keys/` 等敏感文件都保持在版本库外）。
4. 如需运行 macOS 辅助脚本，请将 `launchd/*.plist` 安装到 `/Library/LaunchDaemons/` 并指向实际路径，然后加载：
   ```bash
   sudo launchctl load -w /Library/LaunchDaemons/com.example.openvpn-backhaul.plist
   ```

## 目录结构

```
.
├── docs/                 # 公共文档（不含机密）
├── launchd/              # launchd 样例配置
├── scripts/              # Bash 脚本，依赖 .env 中的变量
├── server.conf.example   # Cloud 端 OpenVPN 配置模板
├── ovpn-admin.sh         # macOS 管理脚本（调用前请检查脚本逻辑）
└── .env.example          # 环境变量样例，实际值存放在 .env
```

## 安全注意

- 仓库默认忽略 `client/`、`keys/`、`backup/`、`.ovpn` 等敏感目录和文件，确保生产资产不会进入 Git。
- 推送到公共仓库前务必再次确认：`git status` 只列出模板和脚本，且 `.env` 中的值不会被提交。
- 所有脚本都假设通过变量传入真实主机名、IP 地址和凭据，请根据自身安全策略继续加固。

## 许可

MIT License。欢迎提交 PR 改进脚本或文档。
