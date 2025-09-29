# macOS 自动化脚本概述

`scripts/` 和 `launchd/` 目录提供了在 macOS 上运行双入口 OpenVPN 时常见的自动化示例。所有脚本都假设存在 `.env` 文件，并通过其中的变量与真实环境解耦。

## `.env` 中常用变量

| 变量 | 说明 |
|------|------|
| `OVPN_CLOUD_HOST` | 云端主机地址或 SSH 别名 |
| `OVPN_CLOUD_USER` | 连接云端的用户名 |
| `OVPN_SSH_KEY_PATH` | SSH 私钥路径（仅用于自动化脚本） |
| `OVPN_CLOUD_STATUS_PATH` | 云端 `openvpn-status.log` 的绝对路径 |
| `OVPN_CLOUD_STATUS_BACKHAUL_PATH` | 后端隧道状态文件路径 |
| `OVPN_BACKHAUL_GATEWAY` | 回程隧道对端网关，例如 `10.255.0.1` |
| `OVPN_SELF_TUN_IP` | 本机分配的固定 `10.8.0.x` 地址 |
| `OVPN_ROUTE_APPLY` | 本地用于增删 `/32` 路由的脚本路径 |

根据需要还可以声明：

- `OVPN_SSH_STRICT_HOSTKEY`：控制 SSH 的 StrictHostKeyChecking（默认为 `accept-new`）。
- `OVPN_SUDO_PASS`：如需无交互调用 `sudo`，可在临时环境中设置该变量；建议投入生产前改用 `sudoers` 规则或单独账号，避免明文密码。

## Launchd 样例

- `com.example.openvpn-backhaul.plist`：确保 macOS 侧的后端 OpenVPN 客户端常驻运行。
- `com.example.openvpn-route-sync.plist`：周期开启 `connect-route-sync.sh`，根据云端状态文件切换路由优先级。
- `com.example.openvpn-flush-local32.plist`：定期清理 10.8.0.x 的过期主机路由。

使用方法：

```bash
sudo cp launchd/com.example.openvpn-backhaul.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.example.openvpn-backhaul.plist
```

复制前请根据实际路径修改 `ProgramArguments`、`EnvironmentVariables` 等条目。

## 调试建议

1. 执行 `scripts/backhaul-up-sync.sh --dry-run` 查看脚本会增添哪些路由。
2. 使用 `scripts/connect-route-sync.sh status` 检查当前识别到的云端客户端和本地路由。
3. 结合 `ovpn-admin.sh health` 查看 launchd、接口与云端状态。

所有脚本均为示例，请在受控环境中测试，并根据自身安全策略进行加固（日志、凭据管理、错误处理等）。

