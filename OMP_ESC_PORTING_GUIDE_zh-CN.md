# EFM8BB21 + FD6288 移植 Bluejay：工程说明、Nano C2 与验收流程

> 适用对象：本项目中的商业闭源电调，MCU 为 **EFM8BB21F16G-QFN20**，三相驱动为 **FD6288**。
> 文档状态：2026-09-15。源码已迁移到 Bluejay 稳定版 **v0.21.0**；原厂BLHeli_S 16.7双份一致备份的反汇编已确认全部控制引脚、三相顺序、比较器和306ns死区。修正后的 `omp2` 已由有许可的Keil从当前源码连续独立构建两次并通过软件校验，现作为工程测试HEX发布；硬件台架验收尚未完成。

## 0. 先看结论

- 使用维护中的 [bird-sanctuary/bluejay](https://github.com/bird-sanctuary/bluejay)；基线固定为 [v0.21.0](https://github.com/bird-sanctuary/bluejay/releases/tag/v0.21.0)，提交 `93bf3e1a081ee87357aface06e535480dcc191d8`。
- `v0.21.1-RC1` 是预发布版，不用于第一次上电。
- 常见的ATmega328P/16MHz国产经典Nano可以作为C2读写桥；它能在无读保护时备份16KiB用户程序Flash，但不提供源码级单步仿真，也不能绕过芯片读保护。
- 自定义布局为 **X**，MCU 类型为 **H**；首个台架目标为 `X_H_15_24`。
- FD6288 与 Bluejay 的 `DEADTIME=0` 模式不兼容。代码和 Makefile 已同时禁止 X 布局使用零死区。
- 原厂机器码确认P1.4、P1.5、P1.6依次是逻辑A/B/C反馈，P1.3是三相共用比较参考；它不是由现有阻值能证明的物理三相星点。
- Bluejay 需要的是“与 BEMF 分压同比例的半母线比较参考”，不要求真实电机星形中性点；但这个参考本身是必要的。
- 原厂机器码确认信号输入为P0.5、FD6288通道1/2/3就是逻辑A/B/C，并直接确认 `FETON_DELAY=15`（约306ns）。完整证据见[反汇编报告](docs/ORIGINAL_FIRMWARE_REVERSE_ENGINEERING_zh-CN.md)。

当前完成度：

| 等级 | 定义 | 当前状态 |
|---|---|---|
| 静态移植 | 最新稳定源码、引脚布局、构建规则和防呆完成 | 已完成 |
| 可编译 | 使用有许可的 Keil 工具链从当前源码实际生成并校验 HEX | `omp2`已连续独立构建两次并通过校验 |
| 可上台架 | 固件映射和备份完成，发布版HEX及P1.3比例做电气复核 | 工程测试HEX已就绪；待上电复核 |
| 可驱动电机 | HO/LO 或 Vgs 无重叠，限流低速运行正常 | 待示波器及电机测试 |
| 可实际使用 | 全转速、负载、温升、失步与保护测试通过 | 未开始 |

## 1. 硬件结论及可信度

### 1.1 已确认

| 项目 | 结论 |
|---|---|
| MCU | EFM8BB21F16G-QFN20，Bluejay MCU 代码 `H` |
| 驱动器 | FD6288，HIN/LIN 均为高有效输入 |
| C2 | C2D 与 C2CK/RST 已引出 |
| 驱动通道 1 | HIN1=P0.0，LIN1=P0.1 |
| 驱动通道 2 | HIN2=P0.2，LIN2=P0.3 |
| 驱动通道 3 | HIN3=P0.7，LIN3=P1.0 |
| 相位采样 | P1.4→输出A约10k；P1.5→输出B约10k；P1.6→输出C约10k |
| 采样脚对地 | P1.4/P1.5/P1.6 均约0.94k |
| 原厂程序映射 | 通道1/2/3=逻辑A/B/C；反馈=P1.4/P1.5/P1.6；公共参考=P1.3 |
| 控制信号 | 原厂程序通过INT0/INT1读取P0.5 |
| 原厂死区 | 机器码 `SUBB A,#0x0F`，即15步、约306ns |

### 1.2 程序用途已确认，建议动态复核

| 项目 | 当前代码假设 | 验收条件 |
|---|---|---|
| 比较参考 | P1.3=`V_Mux`，原厂程序明确使用 | 通电后记录 `P1.3/VBUS` 并确认随VBUS线性变化 |

### 1.3 尚未确认

| 项目 | 为什么重要 |
|---|---|
| 输入是否为 DShot | Bluejay v0.21.0 面向 DShot300/600，不是普通 1～2ms 舵机 PWM 固件 |

代码中的 A/B/C 表示FD6288通道1/2/3。用户给电机焊盘起的A/B/C名称若顺序不同，不影响该完整相位组；不要拆开交换某一路的HIN、LIN和BEMF。

## 2. P1.3 与“中性点”问题

### 2.1 三个相位采样网络

现有测量很符合三个独立的约 `10k/1k` 分压器：

```text
物理 A ──约10k── P1.4 ──约1k── GND
物理 B ──约10k── P1.5 ──约1k── GND
物理 C ──约10k── P1.6 ──约1k── GND
```

几个阻值可以互相解释：

```text
A 到 B ≈ 10k + 0.94k + 0.94k + 10k = 21.88k
P1.4 到 B ≈ 0.94k + 0.94k + 10k = 11.88k
```

这与测到的约21.8k和11.8k非常接近。它说明三相采样大概率是独立分压，不是由 P1.3 直接形成的三相电阻星形中点。

### 2.2 为什么“P1.3 到 A/B/C 都是13.9k”可能是假象

已知：

- P1.3→GND：正反表笔均约3.67k；
- P1.4/P1.5/P1.6→GND：均约0.94k；
- P1.3→P1.4/P1.5/P1.6：均约3.9k；
- P1.3→VBAT+：正反表笔均约9.7k；
- P1.3→A/B/C：均约13.9k。

这些都是整板未断开元件时的**在路等效阻值**。P1.3 可以经公共地、三个相位分压、母线负载和保护结构形成多条并联路径。因此“到三相相等”只说明网络对称或共享路径，不能单独证明 P1.3 是物理虚拟中性点；`9.7k` 也不等于某一颗确定的上拉电阻。

### 2.3 Bluejay 到底需不需要中性点

不需要把电机真实星形中点引出来，但需要一个等效比较阈值。

若相位采样约为 `10k/1k`：

```text
Vsense ≈ Vphase / 11
反电动势过零时，Vphase ≈ VBUS / 2
所以比较参考 Vref ≈ VBUS / 22 ≈ 0.0455 × VBUS
```

Bluejay 用模拟比较器比较浮空相位采样与 `V_Mux`。因此 P1.3 可以是缩放的半母线参考，也可以来自某种等效虚拟中性点网络，但其动态电压必须与三相采样比例匹配。

如果 P1.3 的下臂确为3.9k，那么产生 `VBUS/22` 的简单分压上臂约为：

```text
Rtop ≈ 21 × 3.9k ≈ 81.9k
```

这只是候选模型，不能由当前在路阻值确认。

### 2.4 建议在刷机前完成的动态复核

1. 不接电机、不接控制信号，使用板子额定范围内的两个安全母线电压点，限流给原板上电。
2. 万用表地接电池负极，分别记录 VBUS 与 P1.3 对地电压。
3. 两个点都计算 `P1.3/VBUS`。
4. 目标值约为 `0.0455`；初步可接受范围取 `0.041～0.050`（约±10%），并且两点比例应基本一致。

记录表：

| 测试点 | VBUS | P1.3 对地 | P1.3/VBUS | 结论 |
|---|---:|---:|---:|---|
| 1 |  |  |  |  |
| 2 |  |  |  |  |

示例：VBUS=8.4V时，理想 P1.3 约为0.382V。

原厂程序已经证明P1.3是实际使用的参考输入，所以无法接触测试点时不再把本项当作“映射未知”的硬阻断项。如果能测量而结果固定接近0V/3.3V、明显不线性或严重偏离上述候选模型，仍应停止电机试验并排查网络。

## 3. v0.21.0 源码移植

工作区中的旧版修改已保存为 Git stash：

```text
stash@{0}: legacy Bluejay 0.16 OMP port before v0.21.0 migration
```

不要删除该 stash。当前分支为 `omp-esc-v0.21.0`，上游基线为 v0.21.0。

### 3.1 修改文件

| 文件 | 作用 |
|---|---|
| `bluejay/src/Layouts/X.inc` | 自定义引脚、模拟输入和跨端口 PWM 路由 |
| `bluejay/src/Modules/Common.asm` | 启用预留的 X 布局 |
| `bluejay/Makefile` | 生成 X/H 目标、排除零死区、增加 `make omp` |
| `bluejay/tools/verify_efm8_hex.py` | 校验 Intel HEX、16KiB边界、目标标签、关键机器码、备份和回读 |
| `bluejay/docs/ORIGINAL_FIRMWARE_REVERSE_ENGINEERING_zh-CN.md` | 原厂16.7反汇编证据和换相表 |

`src/Bluejay.asm` 原本已经定义 `X_ EQU 24`，无需另改枚举。

### 3.2 Layout X 引脚定义

| Bluejay 名称 | MCU | FD6288/反馈功能 |
|---|---|---|
| `A_Pwm` | P0.0 | HIN1 |
| `A_Com` | P0.1 | LIN1 |
| `B_Pwm` | P0.2 | HIN2 |
| `B_Com` | P0.3 | LIN2 |
| `C_Pwm` | P0.7 | HIN3 |
| `C_Com` | P1.0 | LIN3 |
| `RTX_PIN` | P0.5 | 原厂程序控制信号输入 |
| `V_Mux` | P1.3 | 原厂程序三相共用比较参考 |
| `A_Mux` | P1.4 | 逻辑A/FD通道1反馈 |
| `B_Mux` | P1.5 | 逻辑B/FD通道2反馈 |
| `C_Mux` | P1.6 | 逻辑C/FD通道3反馈 |

比较器配置为：

```asm
COMPARATOR_PORT   EQU 1
COMPARATOR_INVERT EQU 0
```

P1.3～P1.6 被设置为模拟输入；其端口锁存保持高，符合 EFM8 对模拟/高阻输入的建议，同时 P1.0/LIN3 在初始化时保持低。P2.0/C2D也按原厂程序保持非推挽，并从Crossbar跳过。

### 3.3 跨端口 CEX0/CEX1 路由

EFM8BB2 Crossbar 按 P0→P1、每个端口从低位到高位，把 CEX0、CEX1 分配到未跳过的引脚：

| 选中相位 | P0SKIP | P1SKIP | CEX0（HIN） | CEX1（LIN） |
|---|---:|---:|---|---|
| A/通道1 | `FCh` | `FFh` | P0.0/HIN1 | P0.1/LIN1 |
| B/通道2 | `F3h` | `FFh` | P0.2/HIN2 | P0.3/LIN2 |
| C/通道3 | `7Fh` | `FEh` | P0.7/HIN3 | P1.0/LIN3 |

C 相跨越 P0.7→P1.0，但仍是两个连续的未跳过引脚。Bluejay 官方 `Q.inc` 使用了相同类型的跨端口路由。

### 3.4 FD6288 与死区

FD6288 输入真值关系：

| HIN | LIN | HO | LO |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1 | 0 | 1 | 0 |
| 0 | 1 | 0 | 1 |
| 1 | 1 | 0 | 0（互锁保护） |

Bluejay 的 `DEADTIME=0` 是一种特殊单 PWM 路径：阻尼模块关闭，LIN保持有效，只把 PWM 送到 HIN。对于 FD6288，HIN=1、LIN=1会令HO/LO同时关闭，所以高边不会按预期工作。FD6288内部100～300ns死区不能修复这个输入逻辑问题。

因此：

- X 布局汇编时若 `DEADTIME=0` 会由 `__ERROR__` 终止；
- Makefile 根本不生成 X 的零死区目标；
- 原厂机器码在 `0x04CA` 明确执行 `SUBB A,#0Fh`，确认 `FETON_DELAY=15`；
- 首个工程值因此改为 `DEADTIME=15`，约306ns，并启用互补CEX0/CEX1；
- FD内部和MCU侧的实际总间隔不能简单相加，最终只以HO/LO或两只MOS的Vgs波形为准。

## 4. 刷除原厂固件前的四个硬门槛

### 4.1 P1.3 比例

原厂程序已确认P1.3就是公共比较参考。条件允许时仍完成第2.4节的双电压点测量，复核其比例和线性；焊点无法安全接触时不要因探测造成短路。

### 4.2 DShot 输入脚与协议

1. 原厂程序两次把外部中断路由到P0.5，并直接读取P0.5，已确认该脚是控制输入。
2. 飞控必须配置为DShot；Bluejay不接受普通1～2ms舵机PWM。首次测试用DShot300，位周期约3.33µs。
3. 如果使用双向DShot，外部信号路径还必须允许ESC反向驱动，不能存在单向缓冲器。

### 4.3 驱动通道与物理相位配对

原厂六步换相代码已把三组完整配对还原如下：

| FD6288通道 | HIN/LIN | 实际桥臂中点 | 对应BEMF脚 |
|---|---|---|---|
| 1 / 逻辑A | P0.0/P0.1 | 用户命名A | P1.4 |
| 2 / 逻辑B | P0.2/P0.3 | 用户命名B | P1.5 |
| 3 / 逻辑C | P0.7/P1.0 | 用户命名C | P1.6 |

**不要只交换 `A_Mux` 与 `C_Mux` 来处理电机反转。** 正常反转应使用Bluejay方向设置，或交换两根电机线。

### 4.4 原厂16KiB备份

首选做法是在任何 erase/write 前完成两次完整备份。如果芯片有读保护而无法备份，或决定跳过读取，必须先明确接受：第一次整片擦除后，原厂固件将永久丢失且无法由本项目恢复。BLHeliSuite的`Read Setup`只能读取身份和设置，不是完整程序备份。

本项目现状（2026-09-15）：已经通过C2读取完整 `0x0000～0x3FFF`，用户确认第二次独立读取一致。规范镜像SHA-256为 `f4dfe722c0b07da2e552387c5a98b31fa326bd29c115e1b46e6a1bbbbee62291`。镜像未上传仓库；请另存至少两份。

## 5. 构建工程测试 HEX

### 5.1 工具链事实

Bluejay 使用 Keil A51/AX51、LX51 和 OHX51。Keil评估版只有2KiB代码限制，不足以链接Bluejay；“评估版32KiB、可直接使用”的旧说明是错误的。

官方开发流程是在 Windows/Simplicity Studio，或 x86 Linux + Wine 中安装 C51，然后通过 [Silicon Labs PK51 页面](https://www.silabs.com/developers/keil-pk51)申请无代码大小限制的免费许可。具体步骤见 [Bluejay Development Wiki](https://github.com/bird-sanctuary/bluejay/wiki/Development)。当前 Makefile 默认按 Unix/Wine 路径调用 Keil，不能把它描述成“Windows Git Bash开箱即用”。

此前在 Apple Silicon Mac 的临时Wine/Keil环境中，`omp1`曾使用正式PK51许可完成实际汇编、链接和HEX生成。2026-09-15重新建立工具链并激活许可后，已从当前源码连续两次构建`omp2`。许可证只存在于本机Wine配置，没有写入项目源码、构建产物或文档。

### 5.2 只构建保守目标

进入源码目录：

```bash
cd /Users/nxf75465/codex/bluejay_on_omp_esc/bluejay
make omp VERSION=v0.21.0-omp2
```

等价的显式命令：

```bash
make single_target LAYOUT=X MCU=H DEADTIME=15 PWM=24 VERSION=v0.21.0-omp2
```

不要为本次工作运行 `make all`，也不要改成 `DEADTIME=0`。

预期产物：

```text
build/hex/X_H_15_24_v0.21.0-omp2.hex
```

### 5.3 `omp2`正式源码构建验证

2026-09-15根据原厂反汇编把死区从5改为15，并让P2.0/C2D保持高阻。随后使用已激活许可的Keil PK51 V9.59从当前源码连续强制构建两次`omp2`：

- AX51 汇编成功；
- LX51 链接成功，0错误；唯一的 `L30` DATA叠加警告是Bluejay上游Makefile明确预期的警告；
- OHX51 成功生成Intel HEX；
- 程序代码量5393字节，HEX数据地址范围 `0x0000～0x1DF5`，未越过BB21的16KiB Flash；
- 两次完整构建的HEX文件SHA-256完全相同；
- 直接强制汇编 `DEADTIME=0` 时，AX51按设计报错并拒绝生成固件。
- `omp2` Intel HEX的每条记录校验和、地址边界、关键SFR初始化、三组CEX路由、CMP1三相选择和15步死区机器码均通过校验器。

正式构建与此前机械生成的候选HEX在Intel HEX文本分行方式上不同，所以文件哈希不同；解析Intel HEX后，全部5393个实际编程字节和地址逐字节一致。仓库和Release以Keil正式输出为唯一权威文件，其SHA-256为：

```text
f4f6096085b4cd31fa7f97703450dfbb45f2a3b0e19cfdaa589efc82655131e4
```

固件内部布局标签应为：

```text
#X_H_15#
```

文件名里的 `v0.21.0-omp2` 用于区分私有构建；不要随意改动Bluejay内部EEPROM版本和设置布局版本，以免破坏配置兼容。

### 5.4 校验 HEX

```bash
python3 tools/verify_efm8_hex.py \
  build/hex/X_H_15_24_v0.21.0-omp2.hex
```

校验器会检查：

- 每条Intel HEX校验和与EOF；
- 所有数据均在 EFM8BB21 的 `0x0000～0x3FFF`；
- 复位向量非空；
- MCU标签为 `#BLHELI$EFM8B21#`；
- 布局标签为 `#X_H_15#`；
- 布局X的关键端口、CMP1、三相路由和15步死区机器码存在；
- 输出文件SHA-256。

配置器看到 `#X_H_15#` 只证明镜像身份，**不能证明电气连接正确**。不要使用在线配置器给这个私有X布局执行“自动刷最新版”；应保存并手动使用本项目生成的HEX。

## 6. 使用BLHeliSuite和Arduino Nano烧录

> **工程测试警告：** `omp2`已完成有许可Keil源码重建和软件校验，但尚未完成真实电调的门极波形、限流低速和温升验收。只有在接受可能擦除原厂固件和损坏电调风险、完成第4节门槛并具备限流与快速断电条件时，才进入写入和第7节台架验证；它还不是量产或飞行固件。

### 6.1 工具范围

后续烧录与读取操作统一使用8位版 **BLHeliSuite 16.7 + Arduino Nano 4-way C2** 这一种GUI方法。经典ATmega328P/16MHz Nano及其CH340/CH341复刻版可以作为C2桥；Nano Every、Nano 33、ESP32版Nano、LGT8F328P或8MHz板不能直接套用。

这种方法写入时会涉及整片擦除，不能绕过EFM8BB2读保护，也不是Keil式的断点/单步仿真器。`Read Setup`不等于完整16KiB固件备份。

### 6.2 共用接线和供电

除特别注明外，单路Nano接线为：

| 经典Nano | 串联保护 | EFM8BB21 |
|---|---:|---|
| D2 | 约1k | C2D |
| D3 | 约1k | C2CK/RST |
| GND | 直接 | 电调GND |

- C2CK与目标RST是同一根脚，**不要把Nano的RESET脚接到电调**。
- EFM8BB2的I/O为5V容忍，仍建议D2、D3各串约1k，降低误接或双方同时输出时的风险。
- **不要把Nano的5V接到电调VDD，也不要依靠Nano的3.3V脚给整块电调供电。** 让电调板载稳压器给MCU提供正常约3.3V，并与Nano共地。
- 拆下电机和桨；电调从电池输入端供电时使用限流电源，并从板子允许的最低母线电压开始。
- 给Nano安装任何接口固件时，先断开电调，只连接Nano的USB。

### 6.3 制作接口、读取和烧录

使用8位版 **BLHeliSuite 16.7**，不要使用BLHeliSuite32。Windows最省事；macOS虽可经Wine运行，但CH340串口到Wine的COM映射更容易出问题。

先制作Nano接口：

1. 只连接Nano的USB，打开BLHeliSuite的 `Make Interfaces` 页。
2. `Arduino Board` 选择 `Nano w/ATmega328`，选择Nano对应的COM口。多数国产老引导程序先试57600，失败再试115200。
3. 点击 `Arduino 4way-interface`。
4. 在固件列表选择名称包含 `Nano`、`16`、`PD3PD2` 的文件，例如 `4wArduino_Nano__16_PD3PD2v20xxx.hex`。不要选 `PB3PB4`，否则接口会改到D11/D12。

制作完成后按第6.2节连接。此4-way固件已经专门用于C2，**不需要D13接地**。然后：

1. 打开 `SiLabs ESC Setup`。
2. 从 `Select ATMEL / SILABS Interface` 选择 `B SILABS C2 (4way-if)`。
3. 选择Nano的COM口，点击 `Connect`，再点 `Read Setup`。
4. 原厂闭源固件可能显示Unknown，或弹出建议刷入已知BLHeli固件。此时先取消，不要接受自动匹配。
5. 确认原厂备份哈希和第4节门槛，再点击 `Flash Other`，手动选择仓库[`firmware/X_H_15_24_v0.21.0-omp2.hex`](firmware/X_H_15_24_v0.21.0-omp2.hex)或Release中的同名HEX。不要选择BLHeliSuite自动推荐的其他布局。
6. 刷完重新连接并执行 `Read Setup`。若软件仍不认识私有布局X，不要点击自动修复或自动升级；配置器识别能力不能证明电气布局正确。

`Read Setup`读取的是固件身份和设置，不应当作原厂16KiB程序备份。

只使用BLHeliSuite的独立图文式步骤清单见[`docs/BLHELISUITE_FLASHING_zh-CN.md`](docs/BLHELISUITE_FLASHING_zh-CN.md)。

### 6.4 当前项目的原厂备份决定与读保护

EFM8BB2支持代码锁和数据区锁。被锁页面经C2只能整片Device Erase，不能读取、单字节写入或单页擦除；整片擦除会清除锁，同时永久销毁原厂内容，Arduino和BLHeliSuite都不能绕过。

本项目已经成功读取完整主Flash且两次结果一致，说明用户程序区没有阻止本次读取的保护。仍应保存规范镜像及其SHA-256；第一次点击 `Write`、`Erase MCU`、`Flash Other`或接受任何重刷提示，会擦除板上原厂内容，之后只能依靠备份恢复。

### 6.5 写入文件和写后确认

使用BLHeliSuite时，只选择本项目工程测试Release中的以下文件，并核对SHA-256：

```text
X_H_15_24_v0.21.0-omp2.hex
SHA-256: f4f6096085b4cd31fa7f97703450dfbb45f2a3b0e19cfdaa589efc82655131e4
```

烧录只使用第6.3节的 `Flash Other`。BLHeliSuite必须明确报告写入完成；随后完全断电重上电，重新连接并执行`Read Setup`。这能确认通讯和设置读取恢复，但不是完整Flash逐字节比较，因此“未做完整回读比较”仍作为剩余风险记录。

## 7. 第一次上电与示波器验收

### 7.1 通用安全条件

- 拆桨；首次使用无电机或小电机，绝不带负载直接试。
- 使用限流电源，并从板子允许的最低安全母线电压开始。
- 串接方便快速断电的开关；监视静态及脉冲电流。
- MCU/FD6288输入脚可用普通地参考探头观察。
- 测高边HO、HS或高边MOS Vgs时，必须使用合适的差分/隔离探头；普通示波器地夹不能接到相位节点。

### 7.2 无电机检查

1. 上电前持续发送 DShot300 零油门。
2. 同时观察每一桥臂的 HIN/LIN。固件启动音流程会主动切换输出，不能只用万用表要求六路始终为低。
3. 启动过程后无油门时，所有桥臂回到关闭状态。
4. 对A/B/C三个选择状态分别确认：只有对应那组CEX0/CEX1被路由；HIN/LIN为互补波形，切换间有双方均低的非重叠时间。
5. 观察FD6288的HO/LO或两只MOS的Vgs：任何时刻同一桥臂两只MOS都不能同时超过导通阈值。
6. 电源不得出现异常脉冲电流，FD6288与MOS不得迅速升温。

任何一项异常都应立即断电；不要靠反复改极性或随机换采样脚碰运气。

### 7.3 带电机低功率检查

1. 使用无桨小电机或原电机拆桨，限流供电。
2. 保持DShot300零油门上电，确认正常初始化。
3. 从最低有效油门开始，观察启动电流、抖动、失步、MOS和驱动温升。
4. 确认三个相位采样相对于比较基准能产生稳定过零换相。
5. 单向DShot和24kHz稳定后，再测试双向DShot、遥测或更高PWM频率。
6. 若方向相反，通过Bluejay方向设置或交换两根电机线处理，不单独交换BEMF脚。

## 8. “可用”的最终验收定义

只有以下全部通过，才可把工程测试版升级为可用版：

- [x] 原厂程序确认P1.3为公共比较参考；有条件时仍复核其动态比例；
- [x] 原厂程序确认控制输入为P0.5；首次台架使用DShot300；
- [x] 原厂程序确认FD通道1/2/3与P1.4/P1.5/P1.6依次成组；
- [x] 原厂16KiB双份备份完成且一致；
- [x] 修正后的`omp2`由有许可的Keil从当前源码连续构建两次，且实际编程字节与候选逐字节一致；
- [x] 工程测试Release HEX通过地址、标签、校验和及关键机器码检查；
- [ ] BLHeliSuite写入成功，断电重上电后仍可执行`Read Setup`；未做完整Flash回读比较列为剩余风险；
- [ ] 三个桥臂的HIN/LIN、HO/LO或Vgs均无重叠；
- [ ] 限流低速、启动、加减速和温升测试通过；
- [ ] 实际电池电压、全转速和目标负载范围验证通过。

## 9. 主要资料

- [Bluejay v0.21.0稳定发布](https://github.com/bird-sanctuary/bluejay/releases/tag/v0.21.0)
- [Bluejay源码](https://github.com/bird-sanctuary/bluejay/tree/v0.21.0)
- [Bluejay开发与Keil工具链](https://github.com/bird-sanctuary/bluejay/wiki/Development)
- [Bluejay死区概念](https://github.com/bird-sanctuary/bluejay/wiki/Concepts-explained)
- [FD6288官方数据手册](https://download.fortiortech.com/datasheet/HVIC-DS-28-EN_FD6288.pdf)
- [EFM8BB2参考手册](https://www.silabs.com/documents/public/reference-manuals/efm8bb2-rm.pdf)
- [EFM8BB2数据手册](https://www.silabs.com/documents/public/data-sheets/efm8bb2-datasheet.pdf)
- [Silicon Labs AN127：C2接口](https://www.silabs.com/documents/public/application-notes/AN127.pdf)
- [BLHeli源码仓库与BLHeliSuite下载说明](https://github.com/bitdump/BLHeli)
- [BLHeliSuite Arduino Nano C2操作参考](https://oscarliang.com/flash-blheli-c2-interface/)
- [Keil评估版限制](https://www2.keil.com/limits)
