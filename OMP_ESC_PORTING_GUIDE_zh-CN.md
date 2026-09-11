# EFM8BB21 + FD6288 移植 Bluejay：工程说明、Nano C2 与验收流程

> 适用对象：本项目中的商业闭源电调，MCU 为 **EFM8BB21F16G-QFN20**，三相驱动为 **FD6288**。
> 文档状态：2026-09-11。源码已迁移到 Bluejay 稳定版 **v0.21.0**，自定义布局已完成静态接入；在下述硬件门槛和示波器验收完成前，只能称为“工程测试版本”，不能称为可装机版本。

## 0. 先看结论

- 使用维护中的 [bird-sanctuary/bluejay](https://github.com/bird-sanctuary/bluejay)；基线固定为 [v0.21.0](https://github.com/bird-sanctuary/bluejay/releases/tag/v0.21.0)，提交 `93bf3e1a081ee87357aface06e535480dcc191d8`。
- `v0.21.1-RC1` 是预发布版，不用于第一次上电。
- 常见的ATmega328P/16MHz国产经典Nano可以作为C2读写桥；它能在无读保护时备份16KiB用户程序Flash，但不提供源码级单步仿真，也不能绕过芯片读保护。
- 自定义布局为 **X**，MCU 类型为 **H**；首个台架目标为 `X_H_5_24`。
- FD6288 与 Bluejay 的 `DEADTIME=0` 模式不兼容。代码和 Makefile 已同时禁止 X 布局使用零死区。
- P1.4、P1.5、P1.6 分别是三相 BEMF 分压采样，这一点有较强证据。
- **仅靠现有阻值不能证明 P1.3 是物理中性点，也不能证明它一定是有效比较基准。** 它目前只是 `V_Mux` 候选，刷除原厂程序前必须动态测得约 `P1.3 = VBUS/22`。
- Bluejay 需要的是“与 BEMF 分压同比例的半母线比较参考”，不要求真实电机星形中性点；但这个参考本身是必要的。
- 还必须确认信号焊盘确实到 P0.5、信号确为 DShot，以及 FD6288 通道 1/2/3 与物理输出 A/B/C 的对应关系。

当前完成度：

| 等级 | 定义 | 当前状态 |
|---|---|---|
| 静态移植 | 最新稳定源码、引脚布局、构建规则和防呆完成 | 已完成 |
| 可编译 | 使用有许可的 Keil 工具链实际生成并校验 HEX | 已完成 |
| 可上台架 | P1.3、P0.5、相位配对通过，且原厂备份完成或已明确接受不可恢复风险 | 待硬件测量 |
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

### 1.2 高概率，但必须动态验证

| 项目 | 当前代码假设 | 验收条件 |
|---|---|---|
| 比较参考 | P1.3=`V_Mux` | 通电后 `P1.3/VBUS` 约为 `1/22`，且随 VBUS 线性变化 |

### 1.3 尚未确认

| 项目 | 为什么重要 |
|---|---|
| 电调信号焊盘是否到 P0.5 | 当前 `RTX_PIN=5`；若实际不是 P0 口，不能只改一个常量解决 |
| 输入是否为 DShot | Bluejay v0.21.0 面向 DShot300/600，不是普通 1～2ms 舵机 PWM 固件 |
| FD 通道1/2/3分别驱动物理 A/B/C 中哪一相 | 每一组 HIN、LIN 和 BEMF 必须属于同一个半桥，否则无法正确换相 |

代码中的 A/B/C 目前首先表示“FD6288 通道1/2/3”。只有确认通道1/2/3的桥臂中点恰好是物理 A/B/C 后，名称才完全等价。

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

### 2.4 刷机前必须完成的动态测量

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

如果实测约为 `0.27～0.28 × VBUS`、固定接近0V/3.3V、明显不线性，或者远离上述范围，**不要进行电机试验**。此时 P1.3 不能直接作为当前布局的 `V_Mux`，需要继续追电路或增加匹配的外部参考网络。

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
| `bluejay/tools/verify_efm8_hex.py` | 校验 Intel HEX、16KiB边界、目标标签、备份和回读 |

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
| `RTX_PIN` | P0.5 | DShot候选输入，待确认 |
| `V_Mux` | P1.3 | BEMF比较参考候选，待动态确认 |
| `A_Mux` | P1.4 | 物理A采样；最终需与FD通道1配对 |
| `B_Mux` | P1.5 | 物理B采样；最终需与FD通道2配对 |
| `C_Mux` | P1.6 | 物理C采样；最终需与FD通道3配对 |

比较器配置为：

```asm
COMPARATOR_PORT   EQU 1
COMPARATOR_INVERT EQU 0
```

P1.3～P1.6 被设置为模拟输入；其端口锁存保持高，符合 EFM8 对模拟/高阻输入的建议，同时 P1.0/LIN3 在初始化时保持低。

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
- 首个工程值为 `DEADTIME=5`，在BB21/49MHz侧约102ns，用来启用互补CEX0/CEX1；
- FD内部和MCU侧的实际总间隔不能简单相加，最终只以HO/LO或两只MOS的Vgs波形为准。

## 4. 刷除原厂固件前的四个硬门槛

### 4.1 P1.3 比例

完成第2.4节的双电压点测量，确认约为 `VBUS/22`。

### 4.2 DShot 输入脚与协议

1. 断电测信号焊盘到 P0.5 的连通路径；中间可能有串联电阻，不能只把“非零阻值”判定为不通。
2. 在原厂固件仍在时，用示波器观察 MCU P0.5：确认信号到达该脚。
3. 确认它是数字 DShot，而不是普通舵机 PWM。DShot300 位周期约3.33µs，DShot600约1.67µs；首次测试用 DShot300。
4. 如果要使用双向DShot，外部信号路径还必须允许ESC反向驱动，不能存在单向缓冲器。

如果实际信号不在P0上，Bluejay当前基于 `IT01CF` 的输入中断不能通过简单修改 `RTX_PIN` 迁移到P1；应先停下来重新评估。

### 4.3 驱动通道与物理相位配对

必须填写：

| FD6288通道 | HIN/LIN | 实际桥臂中点 | 对应BEMF脚 |
|---|---|---|---|
| 1 | P0.0/P0.1 |  | 必须是同一输出对应的P1.4/5/6之一 |
| 2 | P0.2/P0.3 |  | 必须是同一输出对应的P1.4/5/6之一 |
| 3 | P0.7/P1.0 |  | 必须是同一输出对应的P1.4/5/6之一 |

若通道1实际驱动物理B，就应让 `A_Mux` 指向物理B的采样脚；HIN、LIN、BEMF必须作为完整相位组一起调整。

**不要只交换 `A_Mux` 与 `C_Mux` 来处理电机反转。** 正常反转应使用Bluejay方向设置，或交换两根电机线。

### 4.4 原厂16KiB备份

首选做法是在任何 erase/write 前完成第6节的两次完整备份。如果芯片有读保护而无法备份，或决定跳过读取，必须先明确接受：第一次整片擦除后，原厂固件将永久丢失且无法由本项目恢复。

本项目当前决策（2026-09-11）：使用者选择不尝试读取原厂固件，并接受上述不可恢复风险。这只豁免“保留原厂镜像”这一项，不豁免P1.3、P0.5、相位配对、限流和门极无重叠等安全验收。

## 5. 构建工程测试 HEX

### 5.1 工具链事实

Bluejay 使用 Keil A51/AX51、LX51 和 OHX51。Keil评估版只有2KiB代码限制，不足以链接Bluejay；“评估版32KiB、可直接使用”的旧说明是错误的。

官方开发流程是在 Windows/Simplicity Studio，或 x86 Linux + Wine 中安装 C51，然后通过 [Silicon Labs PK51 页面](https://www.silabs.com/developers/keil-pk51)申请无代码大小限制的免费许可。具体步骤见 [Bluejay Development Wiki](https://github.com/bird-sanctuary/bluejay/wiki/Development)。当前 Makefile 默认按 Unix/Wine 路径调用 Keil，不能把它描述成“Windows Git Bash开箱即用”。

当前 Apple Silicon Mac 上的临时 Wine/Keil 环境已经激活正式 PK51 许可，并已完成实际汇编、链接和 HEX 生成。许可证只存在于本机临时 Wine 前缀中，未写入项目源码或文档。

### 5.2 只构建保守目标

进入源码目录：

```bash
cd /Users/nxf75465/codex/bluejay_on_omp_esc/bluejay
make omp VERSION=v0.21.0-omp1
```

等价的显式命令：

```bash
make single_target LAYOUT=X MCU=H DEADTIME=5 PWM=24 VERSION=v0.21.0-omp1
```

不要为本次工作运行 `make all`，也不要改成 `DEADTIME=0`。

预期产物：

```text
build/hex/X_H_5_24_v0.21.0-omp1.hex
```

### 5.3 已完成的构建验证

2026-09-09 已在当前工作区连续强制构建两次，结果完全一致：

- AX51 汇编成功；
- LX51 链接成功，0错误；唯一的 `L30` DATA叠加警告是Bluejay上游Makefile明确预期的警告；
- OHX51 成功生成Intel HEX；
- 程序代码量5393字节，HEX数据地址范围 `0x0000～0x1DF5`，未越过BB21的16KiB Flash；
- 两次构建的SHA-256完全相同；
- 直接强制汇编 `DEADTIME=0` 时，AX51按设计报错并拒绝生成固件。

当前工程测试HEX的SHA-256：

```text
0f0976fa16f9767bb86a763759387ff9d85122806d2958c46d2dd78aab3deb1a
```

固件内部布局标签应为：

```text
#X_H_05#
```

文件名里的 `v0.21.0-omp1` 用于区分私有构建；不要随意改动Bluejay内部EEPROM版本和设置布局版本，以免破坏配置兼容。

### 5.4 校验 HEX

```bash
python3 tools/verify_efm8_hex.py \
  build/hex/X_H_5_24_v0.21.0-omp1.hex
```

校验器会检查：

- 每条Intel HEX校验和与EOF；
- 所有数据均在 EFM8BB21 的 `0x0000～0x3FFF`；
- 复位向量非空；
- MCU标签为 `#BLHELI$EFM8B21#`；
- 布局标签为 `#X_H_05#`；
- 输出文件SHA-256。

配置器看到 `#X_H_05#` 只证明镜像身份，**不能证明电气连接正确**。不要使用在线配置器给这个私有X布局执行“自动刷最新版”；应保存并手动使用本项目生成的HEX。

## 6. Arduino Nano 的三种C2烧录方法

### 6.1 先选路线

`tools/efm8load.py` 是UART bootloader客户端，不是C2客户端。经典ATmega328P/16MHz Nano或复刻版可以变成C2烧录桥；CH340/CH341只影响电脑串口，不改变D2/D3功能。Nano Every、Nano 33、ESP32版Nano、LGT8F328P或8MHz板不能直接套用。

| 方法 | 给Nano安装接口 | 图形界面 | 原厂完整16KiB备份 | 适合用途 |
|---|---|---|---|---|
| 浏览器版C2 Flasher | 网页自动完成 | 有 | 不适合 | 最省事地识别、擦除和写入 |
| BLHeliSuite 4-way C2 | BLHeliSuite的Make Interfaces | 有 | `Read Setup`不等于完整固件备份 | Windows下传统GUI烧录 |
| Arduino C2 + Python | PlatformIO或整理后用Arduino IDE | 无 | 可读取 `0x0000～0x3FFF` | 最可审计的备份和写后回读 |

这三种方法写入时都会涉及整片擦除，不能绕过EFM8BB2读保护，也不是Keil式的断点/单步仿真器。三种Nano固件互不兼容：换方法时通常需要重新给Nano烧接口程序。

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

### 6.3 方法A：浏览器版 Arduino C2 Flasher

这是步骤最少的方案，不需要BLHeliSuite、PlatformIO或Arduino IDE。使用支持Web Serial的桌面版Chrome或Edge打开：

<https://stylesuxx.github.io/arduino-c2-flasher/>

操作顺序：

1. 先只插Nano的USB，点击 `Connect to Arduino`，在浏览器弹窗中选择Nano的串口。
2. 第一次会提示没有检测到C2接口；选择 `Arduino Nano`，让网页自动把接口固件写入Nano。网页会依次尝试新引导程序的115200和老引导程序的57600波特率。
3. 断电后按第6.2节连接D2、D3和GND，再用限流电源给电调正常供电。
4. 再次点击 `Connect to Arduino` 并选择Nano串口。成功时应显示接口已检测到以及MCU设备信息；EFM8BB2的设备ID应为 `0x32`。
5. 进入 `Write` 页，把 `X_H_5_24_v0.21.0-omp1.hex` 拖入文件框，或点击文件框选择该HEX。
6. 确认第4节其他门槛已经完成后才开始；网页在写入前会先整片擦除。完成后断开并给电调重新上电。

浏览器版有三个重要限制：

- 当前源码的 `Read MCU` 只读取 `0x0000～0x37FF`，不是BB21完整的 `0x0000～0x3FFF`；页面也没有把结果直接保存为标准完整备份HEX的流程。
- `Write` 内部会先执行Device Erase；不要把拖入文件框理解为无损检查。
- 显示 `Data has been written` 代表命令完成，但不等于本项目校验器所做的完整逐字节回读比较。

因此它适合已经明确放弃原厂备份、希望用GUI完成首次烧录的情况；若要严格保存或验证Flash，使用方法C。

### 6.4 方法B：BLHeliSuite 的 Arduino 4-way C2

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
5. 完成第4节门槛并接受原厂不可恢复后，点击 `Flash Other`，手动选择本项目的 `X_H_5_24_v0.21.0-omp1.hex`。
6. 刷完重新连接并执行 `Read Setup`。若软件仍不认识私有布局X，不要点击自动修复或自动升级；配置器识别能力不能证明电气布局正确。

`Read Setup`读取的是固件身份和设置，不应当作原厂16KiB程序备份。BLHeliSuite中的4-way接口固件与方法A/C的接口不同；切换回其他方法时需要重刷Nano。

### 6.5 方法C：Arduino C2接口加Python

这是备份和写后回读最严谨的方法。取得 [bird-sanctuary/arduino-c2-interface](https://github.com/bird-sanctuary/arduino-c2-interface)：

```bash
git clone https://github.com/bird-sanctuary/arduino-c2-interface.git
cd arduino-c2-interface
```

原工程使用PlatformIO；经典Nano使用 `nanoatmega328`，新引导程序使用 `nanoatmega328new`。也可以把主CPP、`C2.cpp/.h`和`Dshot.cpp/.h`整理到同一Arduino IDE工程目录后上传。无论用哪种IDE，此固件进入C2模式都要求 **D13在Nano复位前接到Nano GND**。

电脑端只依赖 `pyserial`：

```bash
python3 -m venv .venv
source .venv/bin/activate       # Windows PowerShell使用：.venv\Scripts\Activate.ps1
python -m pip install pyserial
python client/efm8.py info /dev/cu.wchusbserialXXXX
```

macOS可用 `ls /dev/cu.*` 查串口，Windows使用 `COM3` 一类名称。看到 `Connected to interface` 和设备/版本号才说明连接成功。

如需备份，连续读取两次并校验完整 `0x0000～0x3FFF`：

```bash
python client/efm8.py read PORT original_1.hex
python client/efm8.py read PORT original_2.hex
python /path/to/bluejay/tools/verify_efm8_hex.py original_1.hex --full-backup
python /path/to/bluejay/tools/verify_efm8_hex.py original_2.hex --full-backup
cmp original_1.hex original_2.hex
shasum -a 256 original_1.hex original_2.hex
```

读取失败、缺地址、全FF/全00或两份不同，可能是接触、供电、串口或读保护。该客户端只备份16KiB用户程序区，不读取BB2高地址独立非易失数据区，所以也不能称为“整颗芯片逐地址镜像”。

### 6.6 当前项目的原厂备份决定与读保护

EFM8BB2支持代码锁和数据区锁。被锁页面经C2只能整片Device Erase，不能读取、单字节写入或单页擦除；整片擦除会清除锁，同时永久销毁原厂内容，Arduino和BLHeliSuite都不能绕过。

本项目使用者已明确选择跳过原厂固件读取，并接受原厂固件永久不可恢复。因此方法A或B可以作为较省事的GUI写入路线，但第一次点击 `Write`、`Erase MCU`、`Flash Other`或接受任何重刷提示，就是不可逆边界。

### 6.7 写入文件和写后验证

无论使用哪种方法，都只选择本项目Release中的以下文件：

```text
X_H_5_24_v0.21.0-omp1.hex
SHA-256: 0f0976fa16f9767bb86a763759387ff9d85122806d2958c46d2dd78aab3deb1a
```

方法C的写入和严格回读命令为：

```bash
python3 tools/verify_efm8_hex.py build/hex/X_H_5_24_v0.21.0-omp1.hex
python /path/to/arduino-c2-interface/client/efm8.py write PORT \
  build/hex/X_H_5_24_v0.21.0-omp1.hex
python /path/to/arduino-c2-interface/client/efm8.py read PORT flashed_readback.hex
python3 tools/verify_efm8_hex.py flashed_readback.hex --full-backup \
  --compare-programmed build/hex/X_H_5_24_v0.21.0-omp1.hex
```

只有出现 `Programmed-byte comparison: OK` 才是严格的逐字节验证。若选择GUI路线而不做Python回读，至少要求工具明确报告写入成功、断电重上电后仍能重新识别MCU，并把“未做完整回读比较”记录为剩余风险。

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

- [ ] P1.3在两个母线电压点均约为 `VBUS/22`；
- [ ] 信号焊盘→P0.5及DShot300波形确认；
- [ ] FD通道1/2/3、物理输出A/B/C、P1.4/5/6完整成组；
- [x] 原厂16KiB双份备份完成，或已明确接受不可恢复风险（当前选择后者）；
- [x] 有许可的Keil工具链实际构建成功；
- [x] HEX通过地址、标签和校验和检查；
- [ ] C2刷写后逐字节回读一致；
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
- [Arduino C2接口及客户端](https://github.com/bird-sanctuary/arduino-c2-interface)
- [浏览器版Arduino C2 Flasher](https://stylesuxx.github.io/arduino-c2-flasher/)
- [浏览器版C2 Flasher源码](https://github.com/stylesuxx/arduino-c2-flasher)
- [BLHeli源码仓库与BLHeliSuite下载说明](https://github.com/bitdump/BLHeli)
- [BLHeliSuite Arduino Nano C2操作参考](https://oscarliang.com/flash-blheli-c2-interface/)
- [PlatformIO经典Nano（新引导程序）板卡说明](https://docs.platformio.org/en/latest/boards/atmelavr/nanoatmega328new.html)
- [Keil评估版限制](https://www2.keil.com/limits)
