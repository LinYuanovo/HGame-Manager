# 封面画质设置与构建目录恢复

日期：2026-11-10。基线为 `b823990`，工作分支为 `codex/integration-ui-translation`。

## 封面画质

在「设置 → 管理 → 封面画质」新增「节省封面内存」开关，使用现有主题与设置保存方式。

- 默认关闭：新安装和未设置此选项的旧配置均使用原图分辨率。
- 开启：列表和海报封面按 768px 宽度解码，减少大图的内存占用。
- 切换立即生效且自动保存为 `cover_memory_saving`。切换时驱逐原模式封面缓存，避免两种解码结果同时驻留。
- 关闭详情后同时失效原图和缩小图缓存，保留同路径封面更新的修复。
- 原图片文件保持不变；详情正文图片的加载行为保持原状。

## C 盘误写原因

这是开发构建过程中的安装步骤误写。`windows/CMakeLists.txt` 原先先配置 Flutter 和插件，之后才在 `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 为真时修正安装前缀。

首次插件配置因媒体依赖下载失败提前中断，CMake 已把默认 `C:/Program Files/hgame_manager` 写入缓存，但尚未执行项目的前缀修正。重试时该值已在缓存，`CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 不再为真，因此跳过修正。Visual Studio 默认构建包含 INSTALL 目标，于是把测试运行文件和 `data/flutter_assets` 写到了该系统目录。恢复前核对该目录创建于 2026-06-20，属于既有目录。首次构建重试前未检查安装前缀，是此次执行失误。

CMake 3.30.5 的本机 `--help-variable CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 明确说明该标志只在前缀刚初始化为默认值时为真。修复将 bundle 前缀设置提前到插件配置前，并在每次配置时强制采用当前目标程序输出目录，纠正历史错误缓存。

`test/windows_bundle_prefix_test.ps1` 使用当前真实项目 CMake 文件和本地插件替身，覆盖首次配置中断、配置重试及旧系统目录前缀三种场景；只做配置，不执行安装。三项检查均通过。

## 存储边界

主要持久化数据由 `AppPaths` 放在 exe 同级的 `hgame_manager_data`。此前新增日志的 `%LOCALAPPDATA%` 兜底已移除，日志回到 exe 同级 `logs`；软件目录不可写时记录初始化失败，诊断导出会报告目录不可用。

“完全不写 C 盘”并非当前实现能够保证的描述：程序放在 C 盘时，其相邻数据也在 C 盘；浏览器挑战、更新下载、备份导入和 2DFan 解压等现有流程还会使用 Windows 系统临时目录。此次没有改变这些临时文件流程。`C:\Program Files\hgame_manager` 的误写来自构建安装，与上述应用数据目录和临时文件用途不同。

## 恢复结果

- 恢复对象：`C:\Program Files\hgame_manager`。
- 完整备份：`E:\Programs\Trae Projects\HGame-Manager\dist\recovery\hgame-manager-20261110-081111\before`，共 43 个文件，备份逐文件哈希校验通过。
- 恢复来源：主工作区原有 `build/windows/x64/runner/Release`，文件版本 `1.5.5+36`。
- 正式程序 SHA-256：`C0C732EDEBFFEF4FFA012A6480B3A671EA613382015ACA359A68B75760886066`。
- 正式 `data/app.so` SHA-256：`C753131FDFE6D2399FB4D53100ED2058AC138A4D3E416075D5DFEF02EE20544D`。
- 共恢复并核对 45 个运行文件；恢复前该目录未发现数据库、设置或其他非运行文件。只替换程序与资源，完整备份继续保留。
- 将恢复后的文件复制到 E 盘隔离目录，预置空设置并禁用旧数据迁移、自动更新和全局快捷键。窗口就绪、独立数据库创建及正常关闭均通过，退出码为 0；测试副本已清理。
- `dist/recovery/hgame-manager-20261110-081111` 下保留恢复前清单、Release 清单、恢复结果和启动结果。没有误写前快照，恢复到已知的 1.5.5+36，无法证明等同于系统目录原先的程序版本。

## 验证与清理

- Windows 原生用例通过：真实 1536×864 图片默认以 1536px 宽解码，通过设置页开关变为 768px，再切回 1536px；验证开关值写入磁盘，切换前后图片字节不变，覆盖同路径文件后关闭详情能读取新像素。同时复验共享翻译流程、原文切换和诊断 ZIP。
- 243 项业务回归通过。
- 静态分析 0 error、19 warning、481 info，与修改前逐项去除行号后完全一致；命令因历史诊断返回 1。
- CMake 三项回归通过；真实原生构建的安装清单含 41 个条目，全部位于工作区 `build/windows/x64/runner/Debug`。
- 原生日志确认默认写入测试 exe 同级 `logs`；诊断包导出通过。
- C 盘恢复后的 45 个文件复查仍与 Release 清单全部相同；隔离启动与正常退出测试通过。
- 临时原生构建与启动测试副本已清理，项目原有 `build` 已恢复，原 Release 主程序及 `app.so` 哈希保持一致。恢复前的完整备份和清单持续保留在 `dist/recovery/hgame-manager-20261110-081111`。
- 本聊天证据目录 `C:\Users\Administrator\.codex\visualizations\2026\11\09\01a1c0fd-df6b-7430-a0dd-a05761a18417` 保留 `cover-native.log`、`cover-regression.log`、`cover-analyze.log`、`cover-results.json`；临时启动脚本已清理。

修改保留在同一本地整合分支，应用版本仍为 `1.5.5+36`。恢复到 C 盘的程序使用已知旧 Release；新封面开关属于本次源码改动，需要构建此分支后使用。
