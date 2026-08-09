# ops-demo 项目交接文档

> 本文用于把项目当前状态、架构、已完成工作、已知问题和下一步验证要求交接给新的对话或协作者。

## 一、项目基本信息

- 项目路径：`C:\Users\Nahida\ops-demo`
- Git 分支：`main`
- Git 远程仓库：`https://github.com/Fangyuan147/test.git`
- 项目定位：Ubuntu 单机 Flask/Gunicorn/Nginx 运维实践项目。
- 当前状态：已加入 Prometheus、Node Exporter、Blackbox Exporter 和 Grafana 自动化配置，但仍需完成当前版本的 Ubuntu 实机验证。

先确认实际仓库根目录：

```bash
git rev-parse --show-toplevel
git status --short --branch
```

不要把 Codex 输出目录当作项目仓库根目录。

## 二、当前架构

```text
客户端
  ↓
UFW
  ↓
Nginx :80
  ↓ upstream 权重 3:2:1
Gunicorn/Flask
  ├─ ops-demo  → 127.0.0.1:8000
  ├─ ops-demo1 → 127.0.0.1:8001
  └─ ops-demo2 → 127.0.0.1:8002
```

运行约定：

- Ubuntu 项目目录：`/opt/ops-demo/`
- 运行用户：`opsdemo`
- 共享虚拟环境：`/opt/ops-demo/venv`
- 应用日志：`/var/log/ops-demo/`
- 项目备份：`/var/backups/ops-demo/`
- 三个后端只监听回环地址。

监控端口：

| 组件 | 端口 | 作用 |
|---|---:|---|
| Prometheus | 9090 | 采集和查询指标 |
| Node Exporter | 9100 | 提供主机指标 |
| Blackbox Exporter | 9115 | 探测 HTTP 健康接口 |
| Grafana | 3000 | 展示 Prometheus 数据 |

## 三、重要文件

基础配置：

- `config/nginx/sites.conf`：Nginx、用户、项目路径、虚拟环境和站点列表。
- `requirements.txt`：Flask 3.0.3、Gunicorn 22.0.0。

运维脚本：

- `scripts/install.sh`：安装 Ubuntu 系统依赖、Prometheus、Exporter 和 Grafana。
- `scripts/deploy.sh`：部署应用，生成 systemd/Nginx 配置，复制监控配置并启动服务。
- `scripts/check.sh`：较完整的验收检查。
- `scripts/health-check.sh`：服务和 HTTP 健康检查。
- `scripts/backup.sh`：项目文件和部分系统配置备份。
- `scripts/back.sh`：调用备份脚本的别名。

Prometheus：

- `config/prometheus/prometheus.conf`：Prometheus、Exporter 和 Grafana 端口及系统路径。
- `config/prometheus/prometheus.yml`：Prometheus 抓取配置。
- `config/prometheus/blackbox.yml`：Blackbox HTTP 探测模块。
- `config/prometheus/rules/ops-demo.yml`：告警规则。

Grafana：

- `config/grafana/provisioning/prometheus.yml`：自动创建 Prometheus 数据源。
- `config/grafana/provisioning/dashboard/ops-demo.yml`：Dashboard provider 配置。
- `config/grafana/dashboard/ops-demo-overview.json`：计划自动加载的 Dashboard JSON。

## 四、已经完成的工作

当前版本已经完成或基本完成：

- 三个后端统一使用 `opsdemo` 用户和共享虚拟环境。
- `deploy.sh` 动态生成三个 systemd 服务和 Nginx upstream。
- systemd 服务加入了基础安全限制。
- `install.sh` 安装 Prometheus、Node Exporter、Blackbox Exporter 和 Grafana。
- `deploy.sh` 复制 Prometheus、规则、Blackbox 和 Grafana provisioning 配置。
- Grafana 数据源使用 provisioning 自动配置，数据源 UID 为 `prometheus`。
- Prometheus 使用 Blackbox Exporter 检查 Nginx 和三个后端的 `/health`。
- 检查脚本已经包含 Prometheus、Exporter 和 Grafana 服务检查。

以上是静态文件结论，不等同于真实 Ubuntu 部署成功。

## 五、当前必须先处理的问题

### 1. Grafana Dashboard 路径不一致

仓库实际目录是单数：

```text
config/grafana/dashboard/ops-demo-overview.json
config/grafana/provisioning/dashboard/ops-demo.yml
```

但 `scripts/deploy.sh` 当前引用复数目录：

```text
config/grafana/dashboards/ops-demo-overview.json
config/grafana/provisioning/dashboards/ops-demo.yml
```

这会导致部署时找不到文件。建议统一使用复数目录：

```text
config/grafana/dashboards/ops-demo-overview.json
config/grafana/provisioning/dashboards/ops-demo.yml
```

并让 `deploy.sh`、provider 的路径和仓库目录保持一致。

### 2. Dashboard JSON 当前为空

`config/grafana/dashboard/ops-demo-overview.json` 当前为 0 字节。即使路径修正，Grafana 也无法加载有效 Dashboard。

应先在现有 Grafana 页面创建面板，使用 Dashboard 的 JSON Model 导出完整 JSON，再保存到统一目录。

检查 JSON：

```powershell
Get-Content -Raw config/grafana/dashboards/ops-demo-overview.json | ConvertFrom-Json
```

### 3. `git diff --check` 未通过

`scripts/deploy.sh` 约第 195-196 行存在只包含空格的行。清理后执行：

```bash
git diff --check
```

必须没有输出。

### 4. 尚未完成真实 Ubuntu 验证

还没有证据证明当前版本已经在全新 Ubuntu 完成：

- APT、Grafana 软件源和 GPG key 安装；
- Prometheus、Exporter 和 Grafana 启动；
- Prometheus 配置和规则加载；
- Grafana 数据源自动加载；
- Dashboard 自动加载；
- Ubuntu 重启后的服务恢复。

因此暂时不要把项目描述为已完成全新 Ubuntu 一键部署。

## 六、脚本检查边界

`check.sh` 中：

- Grafana `/api/health` 只能证明 Grafana 服务正常，不能单独证明数据源连接成功；
- Node Exporter 和 Blackbox 的 `/metrics` 只能证明 exporter 自身可访问；
- Prometheus 查询 `up{job="node"}` 和 `probe_success{job="ops-demo-http"}` 才能验证实际采集结果。

`health-check.sh` 也应保持以下关系：

```text
Node Exporter 自身       → 9100/metrics
Blackbox Exporter 自身  → 9115/metrics
Prometheus 查询结果     → 9090/api/v1/query
Grafana 服务健康         → 3000/api/health
```

## 七、Grafana 自动化方式

Grafana 可以通过 provisioning 自动连接 Prometheus 并加载 Dashboard：

```text
deploy.sh
  ↓
复制 Prometheus datasource provisioning
  ↓
复制 Dashboard JSON
  ↓
复制 Dashboard provider provisioning
  ↓
重启 grafana-server
  ↓
自动创建数据源并加载 Dashboard
```

数据源配置应包含：

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: true
```

Dashboard provider 应指向 Ubuntu 上实际存在的目录：

```yaml
apiVersion: 1

providers:
  - name: ops-demo
    orgId: 1
    folder: Ops Demo
    type: file
    disableDeletion: true
    editable: true
    options:
      path: /etc/grafana/dashboards/ops-demo
```

Dashboard JSON 中应引用数据源 UID `prometheus`。

Ubuntu 验证：

```bash
sudo systemctl restart grafana-server
sudo systemctl status grafana-server --no-pager
curl --fail http://127.0.0.1:3000/api/health
```

然后在 Grafana 页面确认 `Ops Demo` 文件夹和 Dashboard 已出现。

## 八、推荐下一步

### 第一步：修复 Dashboard

统一 `dashboard`/ `dashboards` 目录名称，填入有效 Dashboard JSON，并把 provisioning 文件路径统一。

### 第二步：静态检查

```bash
bash -n scripts/install.sh scripts/deploy.sh scripts/check.sh scripts/health-check.sh scripts/backup.sh scripts/back.sh
git diff --check
```

### 第三步：当前 Ubuntu 验证

```bash
sudo ./scripts/install.sh
sudo ./scripts/deploy.sh
sudo ./scripts/check.sh
sudo ./scripts/health-check.sh
```

### 第四步：监控验证

```bash
systemctl is-active grafana-server prometheus
curl --fail http://127.0.0.1:3000/api/health
curl --fail http://127.0.0.1:9090/-/ready
```

还要确认 Prometheus 数据源、Dashboard 和 Dashboard 面板有数据。

### 第五步：全新 Ubuntu 验证

当前 Ubuntu 验证通过后，再在全新 Ubuntu 执行：

```bash
git clone <仓库地址>
cd ops-demo
chmod +x scripts/*.sh
sudo ./scripts/install.sh
sudo ./scripts/deploy.sh
sudo ./scripts/check.sh
```

## 九、后续路线

以后关于项目推进建议，优先参考 `docs/upgrade-roadmap.md`：

```text
项目收尾和 Ubuntu 验收
→ systemd 安全加固
→ systemd timer 自动备份
→ Prometheus/Grafana 监控完善
→ 故障告警
→ Ansible
→ GitHub Actions
→ Docker
→ 数据库和数据库备份
```

域名和 HTTPS 对当前本地或虚拟机学习项目不是必需条件，可以暂时跳过。

## 十、给下一位协作者的要求

1. 先阅读本文和 `docs/upgrade-roadmap.md`。
2. 先做只读检查，不要直接运行会修改 Ubuntu 系统的命令。
3. 确认实际 Git 根目录和工作区状态。
4. 不要把 Windows Bash 语法通过当作 Ubuntu 部署成功。
5. 修改脚本前说明文件、行号、影响和验证命令。
6. 不要自动 commit 或 push，除非用户明确授权。
7. Grafana 优先使用 provisioning，不要把密码、API token 或私钥写入仓库。
8. 发现问题时按“阻塞部署 / 需要改进 / 后续优化”分类。
9. 继续使用中文、面向新手的可复制命令。
