# LymphMutSig

淋巴系统肿瘤突变特征浏览，以及用用户上传的突变表做特征拟合。界面是现有的 R Shiny 应用（`app/app.R`）。特征拟合仍调用 `app/scripts/run_sigprofiler.py`，使用与现有分析结果一致的 **SigProfilerAssignment 0.2.6**。

部署按 [SciLifeLab Serve 的 Shiny 说明](https://serve.scilifelab.se/docs/application-hosting/shiny/) 和 [serve-app-template](https://github.com/ScilifelabDataCentre/serve-app-template) 的 Shiny 配置：

| 项目 | 值 |
| --- | --- |
| 应用类型 | Shiny |
| 入口 | `app/app.R`，容器内为 `/srv/shiny-server/app.R` |
| 端口 | `3838` |
| 运行用户 | `shiny`，UID `999` |
| 启动命令 | `/usr/bin/shiny-server` |
| 镜像平台 | `linux/amd64` |
| 基础镜像 | `rocker/shiny:4.6.1` |

当前 Serve Shiny 文档使用 `rocker/shiny:4.6.1`。模板仓库里的 Shiny Dockerfile 仍写着 `rocker/shiny:4.4.1`。端口、用户和 Shiny Server 启动方式两边一致，基础镜像采用当前 Serve 文档。

应用代码没有改。`app/tmp/` 是以前本地运行留下的中间文件，不会打进镜像，也不要提交到 GitHub。

## 本地测试

先安装并启动 [Docker Desktop](https://docs.docker.com/get-started/get-docker/)。

在本目录（`LymphMutSig/`，也就是 `Dockerfile` 所在目录）执行：

```bash
cd /Users/hui.wan/Library/CloudStorage/OneDrive-KarolinskaInstitutet/Documents/Project/Kataegis1260_2026/LymphMutSig

docker build --platform linux/amd64 -t lymphmutsig:local .
docker run --rm -p 3838:3838 lymphmutsig:local
```

浏览器打开：

```text
http://localhost:3838
```

第一次构建会安装 R 包、Python 包，并下载 GRCh37 和 GRCh38 参考基因组。这一步需要网络，镜像会到数 GB，时间会比较长。

建议检查：

1. Home 和 Signature Browser 能打开，签名图能显示。
2. Signature Analyser 里点击 **Load Example Data**，再点击 **Run Signature Analysis**。示例文件较小，但拟合仍可能要几分钟。
3. 终端里按 `Ctrl+C` 停止容器。

这台电脑上当前没有可用的 Docker，所以上面的镜像还没有在这里构建过。

## 放到 GitHub 并发布镜像

只把 `LymphMutSig` 这个目录做成一个 **公开** 仓库。不要把上一级的整个课题目录推上去，里面有别的数据。

在 GitHub 上新建一个空的公开仓库，例如 `LymphMutSig`。不要勾选添加 README。然后在本目录执行，把尖括号里的内容换成你的账号和仓库名：

```bash
cd /Users/hui.wan/Library/CloudStorage/OneDrive-KarolinskaInstitutet/Documents/Project/Kataegis1260_2026/LymphMutSig

git init
git add .
git commit -m "Package LymphMutSig for SciLifeLab Serve"
git branch -M main
git remote add origin https://github.com/<你的GitHub账号>/LymphMutSig.git
git push -u origin main
```

推送到 `main` 之后：

1. 打开该仓库的 **Actions**。
2. 等 **Publish container image** 成功。构建同样会下载参考基因组，GitHub 上这一步也会比较久。
3. 打开该次运行的 **Summary**，复制里面的镜像地址。形式类似：

```text
ghcr.io/<你的GitHub账号>/lymphmutsig:20261110-140000-a1b2c3d-1-1
```

4. 打开仓库右侧或账号下的 **Packages**，进入这个镜像包，把可见性改成 **Public**。Serve 必须能在不登录的情况下反复拉取它。

每次部署都要用一个新的 tag。工作流不会发布 `latest`。

## 部署到 SciLifeLab Serve

1. 登录 [SciLifeLab Serve](https://serve.scilifelab.se/)。
2. 创建一个项目，模板选 Default。
3. 在项目里选择 **Shiny** 应用卡片，点击 Create。
4. 按下面填写。

| 字段 | 填写 |
| --- | --- |
| Subdomain | 你想要的名字，或留空让 Serve 生成 |
| Storage / Mount path | None。参考数据和示例数据已经在镜像里 |
| Hardware | 先用默认 2 vCPU、4 GB。如果示例拟合被杀掉，再向 serve@scilifelab.se 说明需要更多内存 |
| Port | `3838` |
| Image | Actions Summary 里的完整地址，必须带唯一 tag |
| Title | LymphMutSig |
| Description | 淋巴系统肿瘤突变特征浏览，以及基于用户突变表的 SBS、DBS、indel 特征拟合 |
| Source code URL | `https://github.com/<你的GitHub账号>/LymphMutSig` |
| Creators | 填写实际作者 |
| Permission | 给别人看用 Link；正式公开用 Public。Private 和 Project 只适合临时调试 |

Path to site_dir 留空。应用已经放在 `/srv/shiny-server/`。

更新已发布的应用时：改代码，推送到 `main`，等新镜像构建完成，把 Serve 里的 Image 改成新 tag，再点 Update。不要重复使用旧 tag。

镜像在应用上线期间必须一直保持公开可拉取。

## 使用时的限制

- 不要把患者或敏感数据放进仓库、镜像或 Serve。
- Serve 文档目前写明 Shiny 上传上限是 100 MB。应用代码里的单文件上限是 500 MB；超过 100 MB 的文件需要先邮件联系 Serve。
- 不同访客各自看到默认页面，应用没有用户注册或用户数据库。
- 容器里的拟合临时文件在会话结束后按应用原有逻辑清理，不会当作持久存储。

## 参考

- [SciLifeLab Serve Shiny 托管说明](https://serve.scilifelab.se/docs/application-hosting/shiny/)
- [其他应用类型的通用要求](https://serve.scilifelab.se/docs/application-hosting/other/)
- [serve-app-template](https://github.com/ScilifelabDataCentre/serve-app-template)
