# YewNursery - Scoop Bucket

[![Tests](https://github.com/YewFence/YewNursery/actions/workflows/ci.yml/badge.svg)](https://github.com/YewFence/YewNursery/actions/workflows/ci.yml) [![Excavator](https://github.com/YewFence/YewNursery/actions/workflows/excavator.yml/badge.svg)](https://github.com/YewFence/YewNursery/actions/workflows/excavator.yml)

叶云枫的个人 [Scoop](https://scoop.sh) Bucket，收录日常开发和使用的工具。

## 如何使用这个 Bucket？

配置步骤请参考原模板的 [使用说明](#使用模板的步骤)（如果你是从模板创建的）。

## 如何安装应用？

添加 Bucket 并安装应用：

```pwsh
scoop bucket add YewNursery https://github.com/YewFence/YewNursery
scoop install YewNursery/<app-name>
```

## 如何添加新的应用清单？

### 自动添加（推荐）

1. 进入 GitHub 仓库的 [Actions 页面](https://github.com/YewFence/YewNursery/actions)
2. 点击左侧的 **New App** 工作流
3. 点击 **Run workflow** 按钮
4. 输入 GitHub 仓库地址（例如 `https://github.com/owner/repo`）
5. 等待工作流运行完成，它会自动创建一个包含新应用的 Pull Request
6. 检查 PR 中的应用清单，使用命令 `/set-bin` `/add-shortcut` 等补充缺少的字段（详情请自己查看PR正文）

### 手动添加

1. 复制 `bucket/app-name.template.jsonc` 并重命名为 `bucket/<app-name>.json`
2. 删除所有 `//` 注释行
3. 填写实际的应用信息
4. 用 `scoop hash <url>` 获取 SHA256 校验值
5. 提交并推送

### 清单字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `version` | ✅ | 当前版本号，如 `1.0.0` |
| `description` | ✅ | 简短描述，显示在 `scoop search` 结果中 |
| `homepage` | ✅ | 应用主页，通常是 GitHub 仓库地址 |
| `license` | ✅ | 许可证，如 `MIT`, `Apache-2.0`, `GPL-3.0` |
| `url` / `architecture` | ✅ | 下载链接和 SHA256 校验值 |
| `bin` | 按需 | 注册到 PATH 的可执行文件 |
| `extract_dir` | 可选 | 解压后进入的子目录 |
| `shortcuts` | 可选 | 开始菜单快捷方式 |
| `persist` | 可选 | 升级时保留的文件/目录 |
| `checkver` | 推荐 | 版本检测配置，GitHub 项目用 `"github"` |
| `autoupdate` | 推荐 | 自动更新 URL 模板，配合 `checkver` 使用 |

### 示例：GitHub Release 命令行工具

参考 [`bucket/ripgrep.example.json`](bucket/ripgrep.example.json)：

```json
{
    "version": "15.1.0",
    "description": "快速的递归正则搜索工具",
    "homepage": "https://github.com/BurntSushi/ripgrep",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-pc-windows-msvc.zip",
            "hash": "...",
            "extract_dir": "ripgrep-15.1.0-x86_64-pc-windows-msvc"
        }
    },
    "bin": "rg.exe",
    "checkver": "github",
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/BurntSushi/ripgrep/releases/download/$version/ripgrep-$version-x86_64-pc-windows-msvc.zip",
                "extract_dir": "ripgrep-$version-x86_64-pc-windows-msvc"
            }
        }
    }
}
```

### autoupdate 变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `$version` | 完整版本号 | `1.2.3` |
| `$cleanVersion` | 无点版本号 | `123` |
| `$majorVersion` | 主版本号 | `1` |
| `$minorVersion` | 次版本号 | `2` |
| `$patchVersion` | 补丁版本号 | `3` |

更多详情请阅读 [官方文档](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)。

## 维护工具

我们在 `bin/` 目录下提供了一些脚本来帮助维护这个 Bucket：

### 代码风格与格式化

- **`bin/formatjson.ps1`**
  格式化 `bucket/` 下的所有 JSON 清单。它会自动排序键值并统一缩进（4 空格），这是提交前的必修课哦！

- **`bin/fix-style.ps1`**
  自动修复文件中的格式问题，主要是删除行尾多余的空格并确保文件以换行符结束。支持 `.ps1`, `.json`, `.yml`, `.md` 等文件。

### 测试与验证

- **`bin/test.ps1`**
  运行完整的 Pester 测试套件，这是 CI 流水线的主要关卡。

- **`bin/checkver.ps1`**
  检查应用的版本更新逻辑。可以用来测试你写的正则对不对。
  用法：`.\bin\checkver.ps1 -App <app-name>`

- **`bin/checkhashes.ps1` / `bin/checkurls.ps1`**
  分别用来验证清单中下载链接的哈希值是否匹配，以及链接是否依然有效。

---

## 使用模板的步骤

如果你想基于这个仓库创建自己的 Bucket：

1. 使用 "Use this template" 按钮创建你自己的副本
2. 启用 GitHub Actions（所有权限）：
   - 进入 `Settings` → `Actions` → `General` → `Actions permissions`
   - 选择 `Allow all actions and reusable workflows`
   - 点击 `Save`
3. 授予工作流写入权限：
   - 进入 `Settings` → `Actions` → `General` → `Workflow permissions`
   - 选择 `Read and write permissions`
   - 点击 `Save`
4. 在 `README.md` 中更新你的 Bucket 信息
5. 在 `bin/auto-pr.ps1` 中替换占位符（`<username>/<bucketname>`）
6. 复制 `bucket/app-name.json.template` 创建新的应用清单
7. 提交并推送更改
8. 如果希望在 `https://scoop.sh` 上被索引，为仓库添加 `scoop-bucket` 标签
