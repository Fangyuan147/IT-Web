# Ubuntu Web 运维项目评审报告

## 一、总体结论

这是一个方向正确、结构较完整的 Ubuntu Web 运维练习项目。项目已经覆盖：

```text
客户端 -> UFW -> Nginx:80 -> Gunicorn -> Flask -> systemd
```

同时包含日志轮转、健康检查、备份、故障演练和运维文档，具备较好的学习和作品集基础。

但当前工作区修改后的 `scripts/deploy.sh` 和 `scripts/health-check.sh` 存在多个会导致脚本直接失败的问题。因此当前项目应评价为：

> 架构设计和运维场景较好，但自动化部署版本尚未达到可重复执行和可验收状态。

本报告基于静态文件审查，尚未在真实 Ubuntu 主机上执行部署，所以不能据此证明服务已经成功运行。

## 二、项目优点

### 1. Web 运维链路比较完整

项目覆盖了 Web 服务生命周期中的多个环节：

- Flask：提供 Web 应用和 `/health` 健康接口
- Gunicorn：运行 Flask 应用
- systemd：负责启动、停止、开机自启和故障重启
- Nginx：提供统一入口和反向代理
- UFW：控制对外开放端口
- logrotate：管理日志文件
- 健康检查脚本：检查服务和后端端口
- 备份脚本：备份项目文件
- 故障演练文档：记录常见故障定位思路

这比只部署一个 Flask 页面更能体现基础运维能力。

### 2. Nginx 负载均衡设计清晰

原有 Nginx 配置将三个后端绑定到本机回环地址：

| 服务 | 地址 | 权重 | 理论长期比例 |
|---|---|---:|---:|
| `ops-demo` | `127.0.0.1:8000` | 3 | 50% |
| `ops-demo1` | `127.0.0.1:8001` | 2 | 33.3% |
| `ops-demo2` | `127.0.0.1:8002` | 1 | 16.7% |

三个后端不直接暴露给外部，只允许 Nginx 统一转发，端口边界设计合理。权重表示长期相对比例，不保证每六次请求严格按照 `3:2:1` 分配。

### 3. 有基础权限隔离意识

systemd 服务使用受限的 `opsdemo` 用户运行，并使用了：

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- Gunicorn 只监听 `127.0.0.1`
- 后端不直接监听公网地址

这些设置说明项目已经考虑到服务不应使用 root 运行，以及尽量缩小网络暴露面。

### 4. 文档意识较好

项目包含 README、架构说明和故障复盘模板：

- README：环境准备、部署流程和验收命令
- `docs/architecture.md`：请求链路、服务关系和权限边界
- `docs/incident-review.md`：故障现象、证据、原因、恢复和改进

故障复盘模板尤其适合后续补充真实演练证据。

### 5. 项目定位比较诚实

README 已明确说明这不是生产级高可用平台，并指出还缺少 HTTPS、监控告警、密钥管理、集中日志和灾备策略。这种定位适合作品集展示，也避免夸大项目能力。

### 6. 基础敏感信息保护较好

`.gitignore` 已忽略 `.env`、私钥证书、备份包、日志、虚拟环境和 Python 缓存，为后续公开到 GitHub 提供了基础保障。

## 三、当前确定存在的高风险问题

### 1. `deploy.sh` 没有完成 README 描述的部署流程

当前 `scripts/deploy.sh` 只做了部分目录创建和 systemd/Nginx 文件生成，没有完成以下关键步骤：

- 没有检查 root 权限
- 没有复制应用代码
- 没有复制 `requirements.txt`
- 没有创建 Python 虚拟环境
- 没有安装 Flask 和 Gunicorn
- 没有安装 systemd 配置
- 没有执行 `systemctl daemon-reload`
- 没有启用或启动服务
- 没有安装 logrotate 配置
- 没有创建 Nginx 配置软链接
- 没有执行 `nginx -t`
- 没有 reload 或启动 Nginx

因此 README 中的部署命令与当前脚本实际行为不一致。

### 2. 站点字段数量不匹配，运行用户会为空

脚本中的站点配置只有四个字段：

```bash
"ops-demo|/opt/ops-demo|8000|3"
```

但读取时使用了五个变量：

```bash
IFS='|' read -r SERVICE_NAME APP_PATH APP_PORT UPSTREAM_WEIGHT RUN_USER <<< "$site"
```

结果是 `RUN_USER` 为空，后续可能生成空的 `User=`、`Group=`，导致用户创建、权限设置或 systemd 启动失败。

### 3. 第二个应用路径写错

当前写成：

```bash
"ops-demo2|/opt/opt-demo2|8002|3"
```

应统一为类似：

```bash
"ops-demo2|/opt/ops-demo2|8002|1|opsdemo"
```

路径错误会导致目录、服务文件和实际应用位置不一致。

### 4. 用户创建命令拼写错误

当前脚本使用：

```bash
usradd
```

Linux 中正确的命令是：

```bash
useradd
```

这是会直接导致部署失败的确定性错误。

### 5. Nginx upstream 名称不一致

脚本生成：

```nginx
upstream bacckend{
```

但代理目标写成：

```nginx
proxy_pass http://backend;
```

`bacckend` 和 `backend` 不一致，Nginx 无法正确找到后端 upstream。生成配置后必须执行：

```bash
sudo nginx -t
```

### 6. `health-check.sh` 使用了未加载的变量

当前脚本直接使用：

```bash
for site in "${SITES[@]}"; do
```

但没有加载 `config/sites.conf`。由于脚本启用了 `set -u`，执行时会因 `SITES` 未定义而退出。

### 7. 健康检查 URL 多了空格

当前代码：

```bash
curl --fail --silent "http://127.0.0.1: $NGINX_PORT/health"
```

端口号后多了空格，正确写法应为：

```bash
curl --fail --silent "http://127.0.0.1:${NGINX_PORT}/health"
```

### 8. `config/sites.conf` 递归加载自身

当前配置文件最后又 source 了自己：

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/sites.conf"
```

配置文件应该只保存变量；加载逻辑应放在 `deploy.sh`、`health-check.sh` 等脚本中。

### 9. 存在多个配置源，容易产生配置漂移

站点信息同时存在于：

- `config/sites.conf`
- `scripts/deploy.sh`
- `config/nginx/ops-demo.conf`
- `config/systemd/*.service`

但当前脚本没有真正读取 `config/sites.conf`。修改站点时可能只修改一处，造成端口、路径、用户和权重不一致。

建议保留一个配置源，由脚本读取配置并生成 systemd、Nginx 和健康检查逻辑。

## 四、其他不足

### 1. 三个 Flask 应用重复较多

三个 `app.py` 基本相同，只是服务名和端口不同。作为负载均衡演示可以接受，但维护成本较高。

更好的方式是保留一份应用代码，通过环境变量传入服务名和端口，再使用三个 systemd 实例启动。

### 2. Python 依赖没有完全锁定

当前依赖使用范围版本：

```text
Flask>=2.3,<4
gunicorn>=21,<24
```

范围版本方便升级，但可能导致不同时间部署得到不同版本。建议增加锁定版本或依赖锁文件。

### 3. 健康检查缺少完整的可观测性

建议增加：

- `--max-time`
- `--connect-timeout`
- 失败时间和失败原因记录
- 连续失败阈值
- 明确的恢复动作
- 失败告警

当前脚本失败后主要是退出，缺少稳定的检查日志和告警机制。

### 4. 备份不等于完整环境备份

当前备份主要覆盖项目目录中的应用、配置和脚本。完整恢复还应考虑：

- `/etc/systemd/system/*.service`
- `/etc/nginx/sites-available/ops-demo.conf`
- `/etc/nginx/sites-enabled/` 中的软链接
- `/etc/logrotate.d/ops-demo`
- 定时任务
- 用户和权限信息
- 数据库或业务数据

因此当前备份更准确的名称是“项目文件备份”，不能直接称为“主机灾备”。

### 5. 缺少自动化验证

建议加入：

- `bash -n scripts/*.sh`
- ShellCheck
- Python 语法检查
- Nginx 配置语法检查
- GitHub Actions
- 部署后的 HTTP 验收测试

## 五、作品集价值评价

### 可以体现的能力

- Ubuntu 基础服务部署
- Nginx 反向代理和权重负载均衡
- Gunicorn 运行 Flask
- systemd 服务管理
- 端口和监听地址检查
- 日志和日志轮转
- 健康检查
- 备份意识
- 基础故障排查
- 运维文档编写

### 当前不能直接证明的能力

仅凭仓库静态文件，不能证明：

- 部署脚本已经在 Ubuntu 成功执行
- 三个服务已经稳定运行
- Nginx 权重实际生效
- 故障演练已经真实完成
- 备份可以成功恢复
- 重启后服务可以自动恢复
- UFW 规则已经按预期生效

简历中应区分“完成部署实践”和“完成可验证、可重复部署及故障恢复的项目”。后者需要补充真实命令输出、日志、截图或演练记录。

## 六、建议修复顺序

### 第一阶段：恢复可部署性

1. 修复 `config/sites.conf`，只保留配置变量。
2. 让 `deploy.sh` 和 `health-check.sh` 正确加载该配置。
3. 统一五个字段：服务名、应用路径、端口、权重、运行用户。
4. 修复 `useradd`、`/opt/ops-demo2` 和 Nginx upstream 名称。
5. 恢复复制应用、创建虚拟环境、安装依赖、安装配置和启动服务的流程。

### 第二阶段：建立验收机制

在 Ubuntu 上执行：

```bash
bash -n scripts/deploy.sh
bash -n scripts/health-check.sh
sudo ./scripts/deploy.sh
systemctl is-active ops-demo ops-demo1 ops-demo2 nginx
sudo nginx -t
sudo ss -lntup
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8001/health
curl --fail http://127.0.0.1:8002/health
curl --fail http://localhost/health
```

### 第三阶段：补充真实运维证据

至少记录：

- 停止一个后端，确认 Nginx 仍可访问
- 停止全部后端，确认出现 502 并能恢复
- 制造 Nginx 配置错误，确认 `nginx -t` 能阻止错误 reload
- 制造端口冲突，使用 `ss` 和 `journalctl` 定位原因
- 重启主机，确认服务自动恢复
- 备份后解压到临时目录并完成恢复验证

### 第四阶段：提升工程质量

- 添加 ShellCheck 和 GitHub Actions
- 使用单一配置源生成服务配置
- 增加 HTTPS 和域名配置说明
- 使用 systemd timer 代替简单 cron
- 增加监控和失败告警
- 增加远程备份
- 锁定依赖版本
- 增加部署回滚方案

## 七、推荐的简历项目描述

> 基于 Ubuntu 搭建单机 Web 运维实践环境，使用 Nginx 统一接入并按权重代理三个 Gunicorn/Flask 后端；通过 systemd 实现服务托管、开机自启和故障重启，结合 UFW、日志轮转、健康检查、备份脚本和故障演练完成部署、验收与恢复流程。项目重点验证 Web 请求链路、端口隔离、服务状态检查和常见故障定位。

在真实 Ubuntu 环境完成部署验证和故障演练后，再补充“可重复部署”“重启恢复”“备份恢复”等表述。

## 八、总结

这个项目的价值在于已经从“搭建一个 Flask 页面”扩展到了“管理一个 Web 服务生命周期”。

当前最大短板是自动化脚本可靠性，而不是项目选题或总体架构。优先修复部署脚本、统一配置源并补充真实验收证据后，它可以成为一个较扎实的入门级 Linux/Web 运维作品集项目。
