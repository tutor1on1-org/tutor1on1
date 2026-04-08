# 当前 Sync 做法说明

## 总体原则

现在的正式同步模型只有一种：基于 zip artifact manifest 的同步。

不再把 session / progress / enrollment 的行级数据直接当作服务端和客户端的“对等同步对象”。现在真正参与跨端一致性判断的，只有 artifact 清单，也就是：

- `course_bundle`：课程包
- `student_kp`：学生在某个课程某个 KP 下的学习数据包

标准流程是：

1. 先比 `state2`
2. 不一致时再取 `state1`
3. 按 `artifact_id` 找差异
4. 只传输变化的 zip artifact
5. 再做一次一致性确认

## 1. 服务器和客户端的数据格式

### 服务器端

服务器端有两层数据：

- 实际 artifact 文件
- 给同步用的 manifest 状态

实际 artifact 文件分两类：

- `course_bundle`
  - 一个课程对应一个课程包 zip
  - `artifact_id` 形如 `course_bundle:<courseId>`
- `student_kp`
  - 一个学生、一个课程、一个 KP 对应一个 zip
  - `artifact_id` 形如 `student_kp:<studentUserId>:<courseId>:<kpKey>`

服务器对外暴露的 `state1` 项目，核心字段是：

- `artifact_id`
- `artifact_class`
- `course_id`
- `teacher_user_id`
- `student_user_id`
- `kp_key`
- `bundle_version_id`
- `sha256`
- `last_modified`

服务器对外暴露的 `state2` 是一个字符串哈希，格式是：

- `artifact_state2_v1:<sha256>`

它不是对业务表直接算的，而是对当前用户可见的 artifact 清单做规范化后再算出来的。

其中 `student_kp` artifact 的 zip 内容不是任意文件集合，而是一个标准化 zip，里面核心只有一个 `payload.json`。这个 JSON 里会带：

- `schema`
- `course_id`
- `course_subject`
- `kp_key`
- `teacher_remote_user_id`
- `student_remote_user_id`
- `student_username`
- `updated_at`
- `progress`
- `sessions`

也就是说，学生某个 KP 的 progress 和该 KP 下的 session 历史，会一起打进一个 artifact。

### 客户端

客户端也有两层数据：

- 本地业务数据
- 本地同步状态

对 `course_bundle` 来说，客户端本地真正使用的是导入后的课程数据；同步时不靠扫服务器表，而是靠本地保存的课程同步状态来参与比较。

客户端在课程同步上会保存：

- 每个课程 scope 的本地 `state1` 指纹
- 每个同步域的本地 `state2`
- 每个远程课程的同步状态
  - 已安装 bundle version
  - 当前同步 hash
  - `lastChangedAt`
  - `lastSyncedAt`

对 `student_kp` 来说，客户端会保存一个本地 manifest 文件，加上每个 artifact 的 zip 文件。

本地 `student_kp` manifest 结构大致是：

- `remote_user_id`
- `state2`
- `updated_at`
- `items`

每个 item 会记录：

- `artifact_id`
- `sha256`
- `base_sha256`
- `last_modified`
- `storage_file`
- `deleted`

这里的 `base_sha256` 很关键，它表示“本地这份数据是基于服务端哪一个版本改出来的”。后面判断能不能安全上传，就靠它。

## 2. 数据何时生成

### 服务器端何时生成

服务器端的 artifact 数据会在真正有内容变更后生成或更新：

- 教师上传新的课程 bundle 后，服务器生成新的课程包版本
- 学生上传某个 KP 的学习 artifact 后，服务器更新该 KP 对应的 zip

这些更新完成后，服务器会刷新受影响用户的 artifact manifest，也就是重新生成该用户可见的：

- `state1`
- `state2`

所以服务器端的 `state1/state2` 是持久化结果，不是每次请求临时从业务明细现算。

### 客户端何时生成

客户端会在两类时机生成同步数据：

第一类是“本地业务数据变化后”：

- 教师课程内容、提示词、配置等影响 bundle hash 的内容变化后，会更新课程同步 hash / 本地 `state1` / 本地 `state2`
- 学生 session 或 progress 变化后，会重建对应 KP 的本地 artifact zip，并更新本地 manifest

第二类是“同步导入后”：

- 下载并导入远端 `course_bundle` 后，会写入该课程的同步状态
- 下载并应用远端 `student_kp` 后，会把本地 manifest 的 `sha256` 和 `base_sha256` 一起更新成服务器版本

也就是说，客户端不是只在上传前才整理同步状态，而是本地变更和远端导入这两种路径都会维护同步基线。

## 3. state1 list 和 state2 何时生成

### 服务器端

服务器端：

- `state1` 是当前用户可见 artifact 的清单
- `state2` 是对这个清单按 `artifact_id|sha256` 排序拼接后再做哈希

在服务端，`state1/state2` 会在 artifact 变更完成后刷新并持久化。对外读接口只是读取已保存的状态；如果调用时传了 `artifact_class` 过滤条件，则会基于可见 item 再做一次对应范围内的 `state2`。

### 客户端课程同步

课程同步的本地 `state1` 不是一个完整文件清单，而是“按课程 scope 存下来的指纹集合”。

老师侧：

- 一个远程课程对应一个 scope
- 一个尚未绑定远程课程、只存在本地的课程，也会有一个 local scope
- scope 指纹主要体现该课程当前 bundle hash

学生侧：

- 一个远程课程对应一个 scope
- scope 指纹主要体现 `remoteCourseId + teacherRemoteUserId + bundleHash`

客户端会把这些 scope 指纹汇总，再生成课程同步用的本地 `state2`。

### 客户端 student_kp 同步

`student_kp` 的本地 `state1` 就是 manifest 里的 item 列表。

本地 `state2` 的生成规则是：

- 只看未删除的 item
- 只取 `artifact_id` 和 `sha256`
- 排序后按 `artifact_id|sha256` 拼接
- 再算出 `artifact_state2_v1:<sha256>`

所以无论服务器还是客户端，真正决定“是否一致”的核心都只有 artifact id 和 artifact 内容 hash。

## 4. login sync 老师和学生要做哪些操作

## 老师登录

老师登录时，先走课程同步，再走学习数据同步；但学习数据同步不会卡住首屏。

老师课程同步有一个特殊点：

- 首次同步以“先建立和服务器一致的课程基线”为主
- 这一轮会优先拉服务器课程，不会立刻把老师本地课程自动上传上去
- 本地课程上传属于后续正常同步阶段

阻塞登录阶段主要做：

1. 读取服务器 `course_bundle` 的 `state2`
2. 如果和本地课程同步 `state2` 一致，则跳过课程同步
3. 如果不一致，再取服务器 `state1`
4. 找出变化的远程课程和被移除的远程课程
5. 先把服务器上有变化的课程 bundle 拉下来并导入本地
6. 如果不是首次同步，再检查老师本地是否有可以上传的课程变更
7. 如可安全上传，则上传本地课程 bundle
8. 上传后再次读取服务器状态，并把服务器最新 bundle 再拉一轮，确保最终一致
9. 刷新本地课程同步 `state1/state2`

老师登录后，还会继续做 `student_kp` 同步，但这一步会放到后台，不阻塞老师首页首次可用。

老师侧的 `student_kp` 同步以“下载和本地可见性建立”为主：

- 先比 `student_kp` 的 `state2`
- 不一致时取服务器 `state1`
- 下载缺失或变化的学生 artifact
- 本地保存 zip 和 manifest
- 主要用于老师后续查看学生学习数据
- 老师不会把这些学生 artifact 反向上传到服务器

## 学生登录

学生登录会同时做两块，而且两块都在正常登录同步流程里：

1. 课程/报名同步
2. `student_kp` 学习数据同步

课程/报名同步会做：

1. 读取服务器 `course_bundle` 的 `state2`
2. 不一致时拉服务器 `state1`
3. 找出新增、变化、移除的课程
4. 下载新的课程 bundle 并导入本地
5. 建立或修正本地课程与远程课程的绑定关系
6. 必要时迁移旧本地课程上的学生数据到新课程
7. 删除服务器已移除的课程
8. 写回本地课程同步状态和本地 `state2`

`student_kp` 学习数据同步会做：

1. 读取本地 `student_kp` manifest
2. 先比服务器 `state2`
3. 不一致时拉服务器 `state1`
4. 先下载服务器上比本地新的 artifact
5. 再上传本地安全可上传的 artifact
6. 然后重新取一次服务器 `state1`
7. 再补一次下载，确保最终一致
8. 最后检查是否还存在未解决冲突
9. 保存最终 manifest

其中“先下后上再下”的目的是：

- 先吸收服务器已存在的新数据
- 再上传本地明确基于服务器旧版本修改出来的数据
- 最后再做一次对齐，避免自己上传后服务器状态已变化但本地没收尾

## 5. 遇到不一致如何解决

当前的不一致分几类。

### 第一类：只有 state2 不一致，但展开 state1 后可以明确判断差异

这种是正常同步场景，按 manifest diff 处理：

- 服务器有、本地没有：下载
- 本地有、服务器没有，且本地从未同步过服务器版本：允许上传
- 两边都有，hash 一样：视为一致
- 两边都有，hash 不一样：继续看 `base_sha256`

### 第二类：学生 `student_kp` 本地修改，但服务器也变了

这是最关键的冲突判断。

学生侧只有在下面条件满足时才允许上传：

- 本地 `base_sha256` 不为空
- 并且它正好等于当前服务器 `sha256`

这表示“我是在服务器这个版本上改出来的，本地改动还没有过期”，所以可以安全上传。

如果不满足，就不能自动上传。常见情况是：

- 服务器已经被别的设备改过
- 本地基线丢了
- 本地和服务器都各自改了，但已经无法证明谁基于谁

这时系统不会偷偷合并，而是直接当成冲突，需要显式处理。

### 第三类：删除不一致

客户端对 `student_kp` 删除不是简单直接消失，而是会保留一个带 `deleted=true` 的 tombstone，前提是这个 artifact 之前确实有服务器基线。

如果本地标记删除，但服务器还保留该 artifact，就说明删除尚未被明确解决；系统会把它当成需要显式处理的冲突，不会擅自覆盖。

如果本地标记删除，而服务器也已经没有这个 artifact，客户端下次会把这个 tombstone 清掉。

### 第四类：老师课程 bundle 冲突

老师课程同步不走自动合并。

老师本地课程如果有未同步本地改动，同时服务器上又出现了更新的 bundle，系统会直接报冲突，要求老师先明确拉取最新服务器版本，再决定是否继续上传本地修改。

也就是说：

- 服务器新
- 本地也改过
- 这种情况直接阻止自动上传

这里的判断单位是整个课程 bundle，不是课程内部某几行内容。

### 第五类：本地保存的同步状态自己漂移了

如果出现这种情况：

- `state2` 显示不一致
- 但展开 `state1` 后又找不到任何合理差异

系统会认为“本地保存的同步状态已经漂移”，而不是偷偷在同步过程中修补它。当前策略是直接报错，不允许 sync-time repair。

这是为了避免把真正的同步 bug 静默吞掉。

## 当前结论

现在的同步本质上是“按 artifact 做比较和传输”，不是“按业务表逐行同步”。

课程侧关注的是 `course_bundle` 的版本和 hash。
学习数据侧关注的是 `student_kp` 的版本和 hash。

是否一致，只看 manifest。
是否允许上传，关键看 `base_sha256` 是否还能证明本地改动是基于当前服务器版本产生的。
如果无法证明，就不自动合并，而是明确报冲突。
