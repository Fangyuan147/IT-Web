# Ubuntu Web 运维项目评审报告

## 一、总体结论

这是一个方向正确、结构较完整的 Ubuntu Web 运维实践项目，已经覆盖：

```text
客户端 -> UFW -> Nginx:80 -> Gunicorn -> Flask -> systemd
```

项目还包含日志轮转、健康检查、项目文件备份、故障演练和运维文档，具备较好的学习和作品集基础。

当前第一阶段的主要脚本问题已经基本修复：配置源已统一，三个后端使用同一个 `opsdemo` 用户和共享虚拟环境，部署脚本能够复制应用、安装 Python 依赖、生成 systemd/Nginx 配置并执行检查。

当前项目更准确的评价是：

> 已达到“可以进入 Ubuntu 实机验收”的第二优先级，但还不能仅凭静态文件证明部署、故障恢复和备份恢复已经成功完成。

本报告基于当前工作区静态文件审查，未替代真实 Ubuntu 主机上的部署验证。

## 二、当前已完成的改进

### 1. 配置源已经统一

部署、健康检查和验收脚本统一加载：

```text
config/nginx/sites.conf
```

站点列表当前为：

| 服务 | 应用路径 | 端口 | Nginx 权重 |
|---|---|---:|---:|
| `ops-demo` | `/opt/ops-demo/apps/ops-demo` | 8000 | 3 |
| `ops-demo1` | `/opt/ops-demo/apps/ops-demo1` | 8001 | 2 |
| `ops-demo2` | `/opt/ops-demo/apps/ops-demo2` | 8002 | 1 |

三个服务共用配置中的 `RUN_USER=opsdemo` 和 `VENV_PATH=/opt/ops-demo/venv`。

### 2. 部署流程已经补齐主要环节

当前 `scripts/deploy.sh` 已包含：

- root 权限、项目目录和 `requirements.txt` 检查
- 创建或复用 `opsdemo` 系统用户和用户组
- 复制应用、配置、脚本和依赖清单
- 创建共享 Python 虚拟环境并安装依赖
- 动态生成三个 systemd 服务文件
- 动态生成 Nginx upstream 和站点配置
- 安装 logrotate 配置并创建 Nginx 站点软链接
- 执行 `nginx -t` 和 `systemctl daemon-reload`
- 启用并重启三个后端服务以及 Nginx
- 最后调用 `scripts/check.sh` 进行验收

系统依赖安装由独立的 `scripts/install.sh` 负责。当前 `deploy.sh` 不会自动调用它，首次部署时需要先单独执行安装脚本。

### 3. 检查和健康检查逻辑已经改善

`health-check.sh` 已加载统一配置，并为后端和 Nginx 请求设置连接超时和总超时。`check.sh` 对 systemd 状态、开机自启、端口监听、Nginx 配置和健康接口使用明确的失败返回。

### 4. Python 依赖版本已固定

当前 `requirements.txt` 固定为：

```text
Flask==3.0.3
gunicorn==22.0.0
```

## 三、当前仍需确认或改进的问题

### 1. 尚未完成真实 Ubuntu 验收

Windows 或 Git Bash 上的静态检查不能证明 systemd、Nginx、APT、权限和网络行为正确。下一步应在 Ubuntu 上执行并保留输出：

```bash
bash -n scripts/install.sh scripts/deploy.sh scripts/health-check.sh scripts/check.sh scripts/backup.sh
sudo ./scripts/install.sh
sudo ./scripts/deploy.sh
sudo ./scripts/check.sh
```

还应单独验证三个后端、Nginx 统一入口、服务自启和端口监听。

### 2. `install.sh` 仍是独立的未跟踪文件

当前 Git 状态显示 `scripts/install.sh` 尚未纳入版本控制。只要项目仍依赖它，发布前就应将它加入 Git，并在 README 中保留“先安装系统依赖、再执行部署”的顺序。

如果以后希望实现单命令部署，可以让 `deploy.sh` 调用 `install.sh`，但当前不能提前宣称已经实现。

### 3. 仍有工程清理项

配置中保留了 `GUNICORN_VERSION` 的需求痕迹，但实际版本已经由 `requirements.txt` 固定；后续应决定删除该变量或让安装流程真正使用它。此外，提交前应清理脚本末尾多余空行，确保：

```bash
git diff --check
```

通过。这些属于提交质量问题，不是当前架构阻塞项。

### 4. 故障和恢复证据仍不完整

当前文档描述了演练方法，但还需要在 Ubuntu 实机记录实际结果：

- 停止一个后端，确认 Nginx 仍能访问其他后端
- 停止全部后端，确认统一入口出现 502 并完成恢复
- 制造 Nginx 配置错误，确认 `nginx -t` 阻止错误 reload
- 制造端口冲突，用 `ss` 和 `journalctl` 定位原因
- 重启 Ubuntu，确认服务自动恢复
- 解压备份到临时目录并完成恢复验证

## 四、不应再列为当前问题的旧结论

以下问题已经不应继续作为当前版本的确定性缺陷记录：

- `config/sites.conf` 与 `config/nginx/sites.conf` 路径不一致
- 站点字段缺少运行用户导致 `User=` 为空
- `/opt/ops-demo2` 路径错误
- `usradd` 拼写错误
- Nginx upstream 名称与 `proxy_pass` 不一致
- 健康检查没有加载配置或缺少超时
- `config/sites.conf` 自我递归加载
- Flask 和 Gunicorn 依赖只使用范围版本
- `install.sh` 中存在无意义的长时间等待

这些内容应归档为“已修复问题”，不要再写成当前阻塞部署的原因。

## 五、项目能力边界

当前项目可以体现：

- Ubuntu 基础服务部署
- Flask/Gunicorn 应用运行
- systemd 服务托管和开机自启
- Nginx 反向代理与权重转发
- UFW 端口边界控制
- 日志轮转、健康检查和项目文件备份
- 基础故障排查和运维文档编写

但仅凭仓库文件还不能证明：

- 部署脚本已经在 Ubuntu 成功执行
- 三个服务已经稳定运行
- Nginx 权重已经通过实测生效
- 故障演练已经真实完成
- 备份可以成功恢复完整运行环境
- 主机重启后服务可以自动恢复
- UFW 规则已经按预期生效

简历或作品集应区分“已编写自动化部署方案”和“已在 Ubuntu 完成可重复部署、故障恢复及备份恢复验证”。

## 六、下一步优先级

### 第二优先级：完成 Ubuntu 实机验收

1. 在 Ubuntu 中拉取当前仓库。
2. 执行 Bash 语法检查和 `install.sh`。
3. 执行 `deploy.sh`，确认三个 systemd 服务和 Nginx 正常启动。
4. 执行 `check.sh`、`health-check.sh` 和 curl 验收。
5. 记录输出，补充到 `docs/incident-review.md` 或单独的验收记录中。

### 第三优先级：补齐运维证据和工程质量

- 完成故障演练和备份恢复记录
- 加入 ShellCheck、Python 语法检查和 CI
- 明确安装脚本与部署脚本的调用关系
- 统一日志、备份和配置变量的实际使用
- 后续再考虑将三份重复的 `app.py` 重构为一份通用 Flask 应用
- 再学习 Ansible、Docker Compose 和 GitHub Actions

## 七、总结

项目选题和总体架构没有明显方向性错误，第一阶段的脚本问题也已经基本解决。当前差距主要不在“还缺一个 app.py”，而在于：

1. 在真实 Ubuntu 上完成一次可重复部署；
2. 用检查输出证明服务、端口和 Nginx 正常；
3. 用故障演练和恢复记录证明运维闭环确实工作；
4. 将仍依赖的 `install.sh` 纳入版本控制并明确其调用方式。

完成这些证据后，项目才适合更有把握地描述为可重复部署和可验证恢复的 Ubuntu Web 运维实践项目。
