# 入水音效

`dive_splash.wav` 是用户提供的 `SFX_JumpIntooSea.wav` 的原样副本，替换旧入水声。

- 来源：`D:/Work4_Project/GuiOu_Project/20261029_GO/SFX_JumpIntooSea.wav`
- 源文件：立体声 PCM 24-bit，44,800 Hz，191,787 帧（约 4.281 秒）
- SHA-256：`d5cd6e6ae4bf2f8d97a6c90c5573e9ab0d72bc7f2bb8fb55a70982c0c00a8c27`
- 播放：潜水员首次穿过水面时触发，独立播放器保留完整尾音；暂停同步，静音、离开潜水或 GM 换点时停止。
- 导入保持原始声道、采样率和时长，不裁剪、不归一化、不循环；沿用工程的 QOA 导入压缩。
- 网页端只在暂停状态变化时设置 `stream_paused`，避免每帧恢复导致声音反复从静音开头重播。
- `npm run test:entry-audio` 从真实网页出发按钮检测入水音效的启动次数和 WebAudio 输出；加 `-- --pause` 验证暂停恢复。
