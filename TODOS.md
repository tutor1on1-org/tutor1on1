# TODOS
Last updated: 2026-04-08

## P0 Reliability
- [x] Teacher 自动课程同步中移除后台自动上传课程包的行为
  - 文件: `lib/services/enrollment_sync_service.dart`
  - 任务: 在 `_syncTeacherCourses` 中禁止非首轮自动调用 `_uploadLocalTeacherCourses`，仅保留拉取/对齐课程清单和课程包。
  - 任务: 若本地课程有未同步版本，优先给出提示要求手动上传，不在后台覆盖服务器。
- [x] 学生每分钟同步只执行 `student_kp` 上传，不下载
  - 文件: `lib/services/home_sync_coordinator.dart`, `lib/services/session_sync_service.dart`, `lib/ui/pages/student_home_page.dart`
  - 任务: 引入“会话同步模式（full/download-only/upload-only）”。
  - 任务: 学生登录（`showOverlay=true`）执行全量会话同步（下载+上传）；学生计时同步执行仅上传模式。
  - 任务: 上传-only 模式下不执行 `getState2` 触发式下载，不执行 `downloadArtifact*` 和删除冲突下载路径。

## P1 Product completion
- [ ] 登录/首次同步链路按“秒级可达成”收口
  - 文件: `lib/ui/pages/student_home_page.dart`, `lib/ui/pages/teacher_home_page.dart`, `lib/services/enrollment_sync_service.dart`, `lib/services/session_sync_service.dart`
  - 任务: 学生登录时只做课程与 `student_kp` 的基线建立（先比 `state2`，再 `state1` + 下载差异）并尽快回到可用态。
  - 任务: 老师登录时仅拉取服务器最新课程清单与课程包；不把本地课程改动作为强制上传路径。
- [ ] 长耗时与间歇卡住的可观测性
  - 文件: `lib/services/home_sync_coordinator.dart`, `lib/services/session_sync_service.dart`, `lib/services/enrollment_sync_service.dart`
  - 任务: 增加每轮同步阶段耗时日志（state2/state1/下载/上传/保存 manifest）与超时/重试上报。
  - 任务: 如果超过阈值（如 60s）产生告警提示，便于区分“真实网络”与“客户端长执行”问题。

## P2 Security and operations
- [ ] 无

## P3 Quality engineering
- [x] 测试更新
  - 文件: `test/enrollment_sync_service_test.dart`
  - 任务: 增加老师课程同步非首轮不自动上传课程的回归测试。
- [x] 测试更新
  - 文件: `test/session_sync_service_test.dart`
  - 任务: 增加学生周期同步“uploadOnly”模式测试，验证不会触发 `downloadArtifact*` 或删除冲突下载路径。
