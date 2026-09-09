# EFM8BB21 + FD6288 移植 Bluejay：工程说明、Nano C2 与验收流程

> 适用对象：本项目中的商业闭源电调，MCU 为 **EFM8BB21F16G-QFN20**，三相驱动为 **FD6288**。
> 文档状态：2026-09-09。源码已迁移到 Bluejay 最新稳定版 **v0.21.0**，自定义布局已完成静态接入；在下述硬件门槛和示波器验收完成前，只能称为“工程测试版本”，不能称为可装机版本。

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
| 可上台架 | P1.3、P0.5、相位配对和原厂备份全部通过 | 待硬件测量 |
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

在任何 erase/write 前完成第6节的两次完整备份。如果芯片有读保护且无法备份，应停止并由你明确决定是否接受原厂固件永久丢失。

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

## 6. C2备份与烧录

### 6.1 经典 Nano 可以用，但它是烧录桥而不是完整仿真器

`tools/efm8load.py` 是 UART bootloader 客户端，不是C2客户端；它没有旧说明中虚构的 `-a` 自动上传参数。本项目采用 [bird-sanctuary/arduino-c2-interface](https://github.com/bird-sanctuary/arduino-c2-interface) 把Arduino变成C2烧录桥。

可用的是常见的 **ATmega328P、16MHz经典Nano或复刻版**。板上的CH340、CH341或其他USB串口芯片只影响电脑识别出的串口和驱动，不改变D2/D3功能。Nano Every、Nano 33、ESP32版Nano、8MHz Pro Mini或其他非ATmega328P板不能直接套用本步骤。

这个方案能做设备识别、Flash读取、整片擦除和写入；它不能提供Keil那种断点、单步和寄存器观察，因此严格说是“C2烧录器/读写器”，不是源码级仿真器。

### 6.2 把C2接口程序烧进Nano

推荐安装VS Code和PlatformIO扩展，然后取得C2项目：

```bash
git clone https://github.com/bird-sanctuary/arduino-c2-interface.git
cd arduino-c2-interface
```

原项目默认只列出Uno。把下面一个环境追加到 `platformio.ini`；多数国产老引导程序Nano先用第一个，新引导程序用第二个：

```ini
[env:nanoatmega328]
platform = atmelavr
board = nanoatmega328
framework = arduino
monitor_speed = 115200

[env:nanoatmega328new]
platform = atmelavr
board = nanoatmega328new
framework = arduino
monitor_speed = 115200
```

插入Nano后，在PlatformIO中先选择 `nanoatmega328` 并执行Upload；如果只出现 `avrdude` 同步失败，再改选 `nanoatmega328new`。也可以从终端上传：

```bash
pio run -e nanoatmega328 -t upload
# 老引导程序失败时再试：
pio run -e nanoatmega328new -t upload
```

macOS可用 `ls /dev/cu.*` 查串口，CH340复刻板通常类似 `/dev/cu.wchusbserial...` 或 `/dev/cu.usbserial-...`。上传阶段不要连接电调；先只确认Nano自身上传成功。

### 6.3 Nano与电调接线

断电完成以下接线：

| 经典Nano | 串联保护 | EFM8BB21 |
|---|---:|---|
| D2 | 约1k | C2D |
| D3 | 约1k | C2CK/RST |
| GND | 直接 | 电调GND |
| D13 | 跳线到Nano GND | 仅用于选择C2模式 |

注意：

- D13必须在Nano复位或上电前已经拉到GND；接好后按一下Nano的RESET。解除D13-GND再复位，程序才回到DShot测试模式。
- C2CK与目标RST是同一根脚，**不要把Nano的RESET脚接到电调**。
- EFM8BB2的I/O为5V容忍，官方C2项目也以5V/16MHz Uno为目标；仍建议D2、D3各串约1k，降低误接或双方同时输出时的风险。
- **不要把Nano的5V接到电调VDD，也不要依靠Nano的3.3V脚给整块电调供电。** 让电调板载稳压器给MCU提供正常约3.3V，并与Nano共地。
- 拆下电机和桨；电调若必须从电池输入端供电，应使用限流电源并从板子允许的最低母线电压开始。未确认电源结构前，不要同时外灌3.3V和接主电源。

### 6.4 安装电脑端客户端并先读设备信息

C2项目的电脑端只依赖 `pyserial`。在C2项目根目录执行：

```bash
python3 -m venv .venv
source .venv/bin/activate       # Windows PowerShell使用：.venv\Scripts\Activate.ps1
python -m pip install pyserial
python client/efm8.py info /dev/cu.wchusbserialXXXX
```

把最后的串口名换成自己的；Windows通常是 `COM3` 一类。客户端以1,000,000波特率与Nano通信。看到 `Connected to interface` 和设备/版本号，才说明USB串口、Nano程序、D13模式及C2接线这四部分已经连通。

### 6.5 擦除前双份备份

Nano方案能够备份EFM8BB21的16KiB用户程序Flash，**前提是原厂没有锁住相应页面**。EFM8BB2支持代码锁和数据区锁：被锁页面经C2只能执行整片Device Erase，不能读取、单字节写入或单页擦除；整片擦除会清除锁，同时永久销毁原厂内容，Arduino不能绕过保护。

先连续读取两次：

```bash
python client/efm8.py read /dev/cu.wchusbserialXXXX original_1.hex
python client/efm8.py read /dev/cu.wchusbserialXXXX original_2.hex
```

分别检查两份读取覆盖完整 `0x0000～0x3FFF`，且不是全00/全FF：

```bash
python /path/to/bluejay/tools/verify_efm8_hex.py original_1.hex --full-backup
python /path/to/bluejay/tools/verify_efm8_hex.py original_2.hex --full-backup
cmp original_1.hex original_2.hex
shasum -a 256 original_1.hex original_2.hex
```

两份校验结果和SHA-256必须一致，并把备份复制到另一个磁盘。读取提前结束、校验器报告缺地址、内容全FF/全00或两份不同，都视为备份失败；很可能是接触不良、供电/串口问题或读保护。此时不要继续。

该开源客户端目前只备份 `0x0000～0x3FFF` 的16KiB用户程序区，不读取EFM8BB2位于高地址的独立非易失数据区；对保存、恢复原厂程序镜像是主要备份，但不能宣称是“整颗芯片逐地址镜像”。

### 6.6 写入与逐字节回读

**到这里仍不要立即写。** 还要先完成第4节的P1.3、信号脚和相位配对确认。所有门槛满足后，先校验待刷固件，再写入：

```bash
python3 tools/verify_efm8_hex.py build/hex/X_H_5_24_v0.21.0-omp1.hex
python /path/to/arduino-c2-interface/client/efm8.py write /dev/cu.wchusbserialXXXX \
  build/hex/X_H_5_24_v0.21.0-omp1.hex
```

请特别注意：这个客户端的 `write` 会**先执行整片擦除**，不存在无损“试写”。写完重新完整读取：

```bash
python /path/to/arduino-c2-interface/client/efm8.py read \
  /dev/cu.wchusbserialXXXX flashed_readback.hex
python3 tools/verify_efm8_hex.py flashed_readback.hex --full-backup \
  --compare-programmed build/hex/X_H_5_24_v0.21.0-omp1.hex
```

只有出现 `Programmed-byte comparison: OK`，才算写入验证通过。

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
- [ ] 原厂16KiB双份备份一致且已保存SHA-256；
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
- [PlatformIO经典Nano（新引导程序）板卡说明](https://docs.platformio.org/en/latest/boards/atmelavr/nanoatmega328new.html)
- [Keil评估版限制](https://www2.keil.com/limits)
