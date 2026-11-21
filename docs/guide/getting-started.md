# 下载与安装

**黄油仓库（HGame-Manager）** 是一款基于 Flutter 开发的 Windows 本地 HGame 管理器。

::: info 文档版本
导航栏版本对应文档构建时的源码版本，「下载最新版」指向已经发布的安装包；两者可能暂时不同。部分教程截图保留自旧版，操作时以正文和当前界面的按钮名称为准。
:::

## 环境要求

### 用户使用（直接下载）

- **操作系统**：Windows 10 / 11（64 位）
- **内存**：建议 4GB+
- **磁盘空间**：200MB+（解压后）

### 开发构建

- **Flutter SDK**：>= 3.41.9
- **Dart SDK**：>= 3.11.5
- **构建工具**：Visual Studio 2022 / Build Tools 的 C++ 桌面工作负载、Windows SDK，以及 PATH 中可用的 NuGet CLI
- **内存**：建议 8GB+
- **磁盘空间**：2GB+（含构建缓存）

如果你想从源码构建，请查看 [从源码构建](/development/build)。

## 下载安装

在 [GitHub Releases](https://github.com/LinYuanovo/HGame-Manager/releases) 页面下载最新版本的 zip 压缩包，**解压**后即可使用，无需安装。

也可以在 [网盘](https://docs.qq.com/sheet/DVXZ6U2xmbFZuVGtQ?tab=BB08J2) 中下载（含视频教程）。

## 游戏库目录结构

每个游戏使用独立文件夹，可按系列放在子目录中。直接添加本地游戏不需要来源链接；用刮削中心抓取帖子信息时，需要准备 `source_url.txt`。

```
游戏库根目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       ├── Game.exe            # 游戏启动程序（示例）
│       └── HGMDatas/           # 管理器数据目录
│           ├── source_url.txt  # 来源链接（按需）
│           ├── metadata.json   # 游戏信息
│           ├── images/         # 管理器配图
│           └── backup/         # 存档备份
├── RPG/
│   └── ...
└── 未分类/
    └── ...
```

### 关键文件说明

| 文件 | 说明 | 是否必需 |
| --- | --- | --- |
| `HGMDatas/source_url.txt` | 来源页面链接；刮削中心据此发现游戏 | 本地添加不需要，帖子刮削时需要 |
| `HGMDatas/metadata.json` | 游戏信息，含已刮削标记；游戏库刷新按此扫描 | 导入或刮削时生成 |
| `HGMDatas/images/` | 管理器保存的封面、截图和攻略图片 | 按需生成 |
| `HGMDatas/backup/` | 游戏存档的 ZIP 备份 | 备份或导入存档时生成 |

兼容放在游戏根目录的旧版来源文件和元数据。手动准备 `source_url.txt` 时，可与启动程序放在同一目录。请保留游戏自带的 `image/`、`images/` 资源目录，不要手动移入 `HGMDatas`。

软件本身的数据库和设置位于 EXE 同级的 `hgame_manager_data/`，与各游戏的 `HGMDatas/` 分开保存。

### 刮削整理后的目录

配置整理目录，并在「设置 → 管理 → 刮削行为管理」为相应入口启用移动后，游戏会按系列分类移入整理目录：

```
整理目录/
├── SLG/
│   └── GameName/
│       └── HGMDatas/
│         ├── source_url.txt
│         ├── metadata.json
│         └── images/
├── RPG/
│   └── ...
└── Unclassified/               # 无系列标签的游戏
    └── ...
```

## 下一步

安装完成后，首先你需要把游戏添加进软件：[添加游戏（多种方式）](/guide/add-games)。
