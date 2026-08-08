# Ubuntu Web 运维项目进阶路线

## 一、路线目标

本路线用于把当前的 Ubuntu Flask/Gunicorn/Nginx 运维实践项目，逐步升级为更接近真实工程环境的项目。

当前项目已经具备：

- 三个 Flask/Gunicorn 后端实例
- Nginx 统一入口和 3:2:1 权重转发
- systemd 服务托管
- 健康检查、日志轮转和项目文件备份
- 基础故障演练文档
- Git 管理的代码、配置和运维脚本

当前最重要的前置条件仍然是：先在真实 Ubuntu 环境完成一次部署、验收、故障演练和备份恢复，再开始大规模引入新技术。

## 二、推荐推进顺序

```text
当前项目清理
    ↓
Ubuntu 实机验收
    ↓
systemd 安全加固
    ↓
systemd timer 自动备份
    ↓
域名和 HTTPS
    ↓
Prometheus/Grafana 监控
    ↓
邮件、企业微信或钉钉告警
    ↓
Ansible 自动部署
    ↓
GitHub Actions CI/CD
    ↓
Docker 容器化
    ↓
数据库和数据库备份
```

Git 管理贯穿整个过程，不是最后才增加的功能。

## 三、阶段一：完成当前项目收尾

### 目标

确认当前 systemd、Nginx、健康检查、备份和文档形成一个可重复验证的基础版本。

### 主要任务

1. 将 `scripts/install.sh` 加入 Git。
2. 修复 `git diff --check` 报告的格式问题。
3. 检查 README、架构说明和项目评审是否与实际脚本一致。
4. 在 Ubuntu 上执行系统依赖安装和项目部署。
5. 验证三个后端、Nginx、systemd 自启和健康检查。
6. 完成一次备份、解压和恢复验证。
7. 记录真实命令输出，补充到故障演练或验收文档。

### 验收标准

```bash
bash -n scripts/install.sh scripts/deploy.sh scripts/health-check.sh scripts/check.sh scripts/backup.sh
sudo ./scripts/install.sh
sudo ./scripts/deploy.sh
sudo ./scripts/check.sh
sudo ./scripts/health-check.sh
```

并确认以下结果：

- `ops-demo`、`ops-demo1`、`ops-demo2` 和 `nginx` 均处于 active 状态；
- 8000、8001、8002 只监听回环地址；
- Nginx 80 端口可以访问；
- 备份包可以生成并解压；
- 停止服务后可以按照文档恢复。

## 四、阶段二：加强 systemd 服务安全

### 目标

在不破坏现有服务的前提下，减少 systemd 服务的权限和系统暴露面。

当前服务已经使用：

```ini
NoNewPrivileges=true
PrivateTmp=true
```

可以逐步评估增加：

```ini
ProtectSystem=full
ProtectHome=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true
```

不要一次性加入全部限制。每增加一组限制，都要执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart ops-demo ops-demo1 ops-demo2
sudo ./scripts/check.sh
sudo journalctl -u ops-demo -n 50 --no-pager
```

如果使用 `ProtectSystem=strict`，还需要明确配置日志目录等可写路径，例如 `ReadWritePaths=/var/log/ops-demo`。这项限制应在基础限制验证通过后再尝试。

## 五、阶段三：使用 systemd timer 自动备份

### 目标

将手动执行 `backup.sh` 升级为由 systemd timer 定时触发的备份任务。

计划增加：

```text
ops-demo-backup.service
ops-demo-backup.timer
```

推进顺序：

1. 先手动执行 `backup.sh`，确认备份内容和恢复流程正常。
2. 创建一次性 `ops-demo-backup.service`。
3. 创建每日或每周执行的 `ops-demo-backup.timer`。
4. 使用 `systemctl list-timers` 检查调度状态。
5. 手动启动 service，确认生成备份包。
6. 测试保留天数和旧备份清理逻辑。

### 验收命令

```bash
systemctl list-timers --all
sudo systemctl start ops-demo-backup.service
sudo systemctl status ops-demo-backup.service --no-pager
sudo ls -lh /var/backups/ops-demo
```

## 六、阶段四：域名和 HTTPS

### 前置条件

只有服务器能够被公网访问时，才开始购买域名和申请证书。若当前只是本地 Ubuntu 或虚拟机，可以先跳过这一阶段。

### 推进顺序

```text
购买域名
    ↓
配置 DNS A/AAAA 记录
    ↓
确认域名解析到服务器
    ↓
放行 80 和 443 端口
    ↓
配置 Nginx server_name
    ↓
使用 Certbot 申请证书
    ↓
验证 HTTPS 访问
    ↓
测试证书自动续期
```

### 验收重点

- HTTP 请求能够跳转到 HTTPS；
- 证书域名匹配；
- Nginx 配置通过 `nginx -t`；
- `certbot renew --dry-run` 执行成功；
- 续期后 Nginx 可以正常 reload。

## 七、阶段五：Prometheus 和 Grafana 监控

### 目标

让项目从“主动检查”升级为“持续采集和可视化观察”。

推荐顺序：

1. 安装 Prometheus。
2. 安装 node_exporter，采集 CPU、内存、磁盘和网络指标。
3. 增加服务存活和 HTTP 健康检查指标。
4. 确认 Prometheus 能持续抓取数据。
5. 再安装 Grafana。
6. 导入或创建主机和服务仪表盘。

第一版建议监控：

- CPU、内存和磁盘使用率；
- Nginx 进程和端口状态；
- 三个 systemd 服务状态；
- `/health` HTTP 响应状态和耗时；
- 备份任务最近一次成功时间。

不要在监控数据还不稳定时急着配置告警。

## 八、阶段六：增加故障告警

### 目标

当服务、主机、磁盘或备份出现异常时，主动通知维护者。

推荐链路：

```text
Prometheus
    ↓
Alertmanager
    ↓
邮件 / 企业微信 / 钉钉 Webhook
```

先配置少量高价值告警：

- Nginx 停止；
- 任一后端连续失败；
- 磁盘使用率过高；
- 内存不足；
- 备份任务失败或长时间没有新备份；
- HTTPS 证书即将过期。

告警配置完成后，要主动制造故障，确认收到通知，并记录恢复后的告警关闭行为。

## 九、阶段七：使用 Ansible 自动部署

### 目标

把当前 Shell 脚本中的系统安装、用户管理、目录权限、配置分发和服务管理，逐步转换为可重复执行的 Ansible Playbook。

建议先管理这些内容：

- APT 软件包；
- `opsdemo` 用户和用户组；
- `/opt/ops-demo`、日志和备份目录；
- Nginx 配置；
- systemd 服务；
- logrotate 和 systemd timer；
- UFW 规则。

推进方式：

1. 先在本地 Ubuntu 或虚拟机中测试。
2. 让 Ansible 完成一台主机的初始化。
3. 对同一主机重复执行，确认第二次执行不会产生无意义变化。
4. 再将三个后端实例抽象为变量或列表。
5. 最后决定是否逐步替代 `deploy.sh`。

不要在没有验证 Ansible 版本的情况下，同时维护多套相互冲突的部署逻辑。

## 十、阶段八：GitHub Actions

### 第一阶段：先做 CI

先让每次提交自动执行静态检查：

```text
bash -n
ShellCheck
Python 语法检查
Markdown 检查
```

### 第二阶段：再做部署

CI 稳定后，再考虑通过 SSH 或 Ansible 部署到 Ubuntu。自动部署前必须解决：

- SSH 密钥安全保存；
- 生产环境和测试环境区分；
- 部署失败回滚；
- 部署后健康检查；
- 并发部署控制；
- 日志和失败通知。

不要把服务器密码或私钥写进仓库，也不要一开始就把每次提交直接部署到公网服务器。

## 十一、阶段九：Docker 容器化

Docker 会形成另一套运行和部署体系。建议在 systemd 版本稳定后，再用独立目录或分支实现 Docker Compose 版本。

Docker 版本至少应明确：

- Flask/Gunicorn 应用镜像；
- Nginx 是否单独容器化；
- 端口和网络；
- 环境变量和密钥；
- 日志输出；
- 数据卷；
- 健康检查；
- 重启策略；
- 镜像版本和回滚方式。

不要长期无计划地同时维护 systemd、Ansible 和 Docker 三套部署方案。应明确哪一套是主路线，哪一套是学习对照方案。

## 十二、阶段十：数据库和数据库备份

当前三个 Flask 应用是无状态演示应用，暂时不需要数据库。只有增加用户、业务记录或管理后台后，再引入 PostgreSQL 等数据库。

引入数据库时应同时设计：

- 数据库用户和最小权限；
- 密码和密钥存储；
- schema 或迁移管理；
- `pg_dump` 逻辑备份；
- 定时备份；
- 备份保留策略；
- 备份异地保存；
- 恢复演练；
- 数据库版本升级方案。

数据库备份不能只验证“备份文件生成”，还必须验证备份可以恢复并读取关键数据。

## 十三、每阶段通用验收原则

每完成一个阶段，都应记录以下内容：

1. 修改了哪些代码或配置。
2. 执行了哪些命令。
3. 观察到了什么结果。
4. 出错时如何定位和恢复。
5. 如何证明重启或重复执行后仍然有效。

只有“写完配置”而没有“执行和验证”的阶段，不应在简历中描述为已经完成。

## 十四、最终目标

当以下证据都具备后，项目可以较完整地展示 Linux/Web 运维能力：

- Ubuntu 上可重复部署；
- systemd 服务有安全限制；
- systemd timer 自动备份并完成恢复演练；
- 域名和 HTTPS 可用且证书可自动续期；
- Prometheus/Grafana 能持续观察主机和服务；
- 故障告警能够触达并在恢复后关闭；
- Ansible 可以初始化或部署主机；
- GitHub Actions 能通过 CI 检查代码，并在明确边界下执行部署；
- Docker 版本能够独立运行并回滚；
- 数据库有权限、备份和恢复策略。

这条路线不要求一次完成。当前最适合的下一步是：完成 Ubuntu 实机验收，然后进行 systemd 安全加固。
