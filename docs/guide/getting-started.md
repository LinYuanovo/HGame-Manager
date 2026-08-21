# 下载与安装

**黄油仓库（HGame-Manager）** 是一款基于 Flutter 开发的 Windows 本地 HGame 管理器。

## 环境要求

### 用户使用（直接下载）

- **操作系统**：Windows 10 / 11（64 位）
- **内存**：建议 4GB+
- **磁盘空间**：200MB+（解压后）

### 开发构建

- **Flutter SDK**：>= 3.41.9
- **Dart SDK**：>= 3.11.5
- **内存**：建议 8GB+
- **磁盘空间**：2GB+（含构建缓存）

如果你想从源码构建，请查看 [从源码构建](/development/build)。

## 下载安装

在 [GitHub Releases](https://github.com/LinYuanovo/HGame-Manager/releases) 页面下载最新版本的 zip 压缩包，**解压**后即可使用，无需安装。

也可以在 [网盘](https://docs.qq.com/sheet/DVXZ6U2xmbFZuVGtQ?tab=BB08J2) 中下载（含视频教程）。

## 游戏库目录结构

应用期望以下目录结构来正确识别和管理游戏：

```
游戏库根目录/
├── SLG/                        # 按系列分类
│   └── GameName/
│       └── source_url.txt      # 来源URL（必需）
├── RPG/
│   └── ...
└── 未分类/
    └── ...
```

### 关键文件说明

| 文件 | 说明 | 是否必需 |
| --- | --- | --- |
| `source_url.txt` | 游戏来源页面 URL，用于刮削和导入 | 是 |
| `metadata.json` | 游戏元数据（标题、版本、简介等） | 否（刮削后自动生成） |
| `images/` | 游戏截图和封面图 | 否（刮削后自动下载） |

### 刮削整理后的目录

刮削功能会自动将游戏按系列分类移动到整理目录：

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

安装完成后，首先你需要把游戏添加进软件：[添加游戏（四种方式）](/guide/add-games)。
