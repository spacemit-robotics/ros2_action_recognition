# action_recognition

## 项目简介

ROS2 动作识别节点，使用 STGCN 模型对骨架序列进行 7 类动作识别（含 Fall Down）。通过订阅人体姿态关键点数据，实现实时动作识别功能。

## 功能特性

- 支持 7 类动作识别（包括摔倒检测）
- 基于 STGCN 时空图卷积网络
- 实时处理骨架序列数据
- 支持多人同时识别
- 不支持：单帧图像直接识别（需要时序信息）

## 快速开始

### 环境准备

- ROS2 Humble 或更高版本
- 已编译的 `components/model_zoo/vision` 组件
- STGCN 模型文件（stgcn.onnx）

### 构建编译

```bash
colcon build --packages-select action_recognition
source install/setup.bash
```

### 运行示例

```bash
# 启动动作识别节点
ros2 launch action_recognition action_recognition.launch.py
```

需先启动 body_pose 节点提供骨架数据。

## 详细使用

### 依赖

- **body_pose**：订阅 `/perception/body_poses`（`body_pose/msg/BodyPoseArray`）获取人体关键点
- **model_zoo/vision**：需先编译 `components/model_zoo/vision`，提供 `libvision.so` 与 `vision_service.h`

### 话题

- **订阅**：`/perception/body_poses` — `body_pose/msg/BodyPoseArray`
- **发布**：`/perception/actions` — `action_recognition/msg/ActionArray`
  - `ActionArray.header`：与 body_poses 的 header 一致
  - `ActionArray.actions`：每条 `Action` 含 `person_id`、`action_name`、`confidence`、`start_frame`、`end_frame`

### 配置

- `config/action_recognition.yaml`：节点参数（话题、序列长度、推理间隔等）
- `config/stgcn.yaml`：STGCN 模型配置，需正确设置 `model_path`（如将 `stgcn.onnx` 放在同目录或配置绝对路径）

## 常见问题

### 无输出时排查

1. **确认 body_poses 有数据**（否则 action 不会发布）：
   ```bash
   ros2 topic echo /perception/body_poses --once
   ```
   若一直无输出，检查 body_pose 是否正常、图像话题是否为 `/camera/image_raw`。

2. **确认图像有在发布**：
   ```bash
   ros2 topic hz /camera/image_raw
   ```

3. **action_recognition 节点日志**：启动后终端每约 2 秒会打印 `body_poses: N poses, frame=..., buffers=...`；若从未出现，说明未收到 `/perception/body_poses`。攒满 30 帧且 STGCN 推理成功时会打印 `STGCN: person_id=... action=...`。

## 版本与发布

当前版本：1.0.0

变更记录：
- 初始版本发布

## 贡献方式

欢迎提交 Issue 和 Pull Request。

贡献者与维护者名单见：`CONTRIBUTORS.md`（如有）

## License

本组件源码文件头声明为 Apache-2.0，最终以本目录 `LICENSE` 文件为准。
