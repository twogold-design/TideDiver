# 游戏字体

首页和游戏界面统一使用 **Noto Sans CJK SC Regular（思源黑体）**。
游戏通过 `ui_font.tres` 引用；首页通过本地 `@font-face` 引用同一字体文件。
字体随工程提供，运行时不需要联网。

- 官方项目：https://github.com/notofonts/noto-cjk
- 许可：SIL Open Font License 1.1，见同目录 `OFL.txt`。

保留原始字体文件，未裁剪字形或修改字体。导入配置保留完整提示和抗锯齿；
出发页通过 `pixel_text.gd` 在实际像素字号下绘制小字。
