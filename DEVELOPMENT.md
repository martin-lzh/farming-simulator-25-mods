# 开发说明

- 每个功能独立放在 <feature>-mod/，包含实际源码、README.md、DEVELOPMENT.md 和 CHANGELOG.md；按需要加入 assets/、tests/ 和构建入口。
- 尚未确定功能，不创建占位插件或无效构建脚本。
- 实现前核对 Farming Simulator 25 对应版本的开发资料与本机参考，记录已验证的接口与版本；不沿用其他游戏的加载器、SDK 或引擎接口。
- 游戏文件、第三方工具、提取脚本、分析笔记和日志仅放在 work/。
- 构建产物放入 outputs/，安装包只包含原创内容及允许分发的依赖。
- 游戏安装目录只读；构建不自动安装 Mod、不修改存档、不启动或关闭游戏。维护者明确要求时，代理可在游戏关闭后把指定构建复制到 mods 目录，只替换同一 Mod 的旧文件，并报告替换内容和 SHA256。
- Python 依赖优先使用 uv，前端依赖使用 npm。
- 离线检查与游戏内验收分别记录。
- 官方游戏更新：[Steam 构建监测](docs/game-build-monitor.md)每六小时匿名查询 Steam 正式分支的 Build ID，变化时在 `main` 上创建兼容性检查 Issue。游戏也在 GIANTS 商店和 Epic 销售，Steam 构建变化只是更新信号，不代表版本号或兼容性。
- 确定远程仓库后再配置 Git 同步；不得将本项目推送到其他游戏的仓库。

## 许可

2026-10-18：维护者决定把本仓库自己的代码从 MIT 改为 PolyForm Noncommercial License 1.0.0（可免费用于非商业用途，不允许商用），从下一个版本起生效；已发布的 1.0.0.0 和 1.0.0.1 仍为 MIT。`LICENSE` 第一行是 PolyForm 要求的 `Required Notice:` 版权行，其后是 polyformproject/polyform-licenses 1.0.0 标签下的原文，不改写。GitHub 不会把它识别为标准开源许可，会显示为 Other。第三方文件保留各自的许可。
