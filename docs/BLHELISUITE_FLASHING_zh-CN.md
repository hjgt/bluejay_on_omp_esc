# 使用 BLHeliSuite 和 Arduino Nano 烧录 OMP 电调

本文只说明本项目已经验证过的 **BLHeliSuite 16.7 + Arduino Nano 4-way C2** 路线。完整的硬件依据、备份方法和台架验收要求见[主移植说明](../OMP_ESC_PORTING_GUIDE_zh-CN.md)。

> **警告：** 当前HEX是工程测试版，尚未完成真实电调的门极波形、限流低速和温升验收。`Flash Other`会擦除MCU中的原厂程序；拆桨、断开电机并使用限流供电。不要把本文件当作量产或飞行使用许可。

## 1. 只能使用这个目标文件

- MCU：EFM8BB21F16G-QFN20
- Bluejay布局：`X_H_15`
- PWM：24kHz
- 固件：[X_H_15_24_v0.21.0-omp2.hex](../firmware/X_H_15_24_v0.21.0-omp2.hex)
- SHA-256：`f4f6096085b4cd31fa7f97703450dfbb45f2a3b0e19cfdaa589efc82655131e4`

该文件由已许可的Keil PK51 V9.59从当前源码连续构建两次，两次结果一致，并通过地址、标签、Intel HEX校验和及关键机器码检查。它也作为附件发布在[GitHub工程测试Release](https://github.com/hjgt/bluejay_on_omp_esc/releases/tag/v0.21.0-omp2)。

Windows校验命令可使用：

```powershell
Get-FileHash .\X_H_15_24_v0.21.0-omp2.hex -Algorithm SHA256
```

显示的哈希必须与上文完全相同。

## 2. Nano与电调接线

先拔掉电调电源，只给Nano连接USB：

| Arduino Nano | 串联保护 | 电调 |
|---|---:|---|
| D2 | 约1kΩ | C2D |
| D3 | 约1kΩ | C2CK/RST |
| GND | 直连 | GND |

- 不要把Nano的RESET接到电调。
- 不要把Nano的5V或3.3V接到电调VDD。
- 电调由自身板载稳压器正常供电，Nano与电调只共地。
- 当前4-way接口不要求D13接地。

## 3. 第一次制作Nano 4-way接口

如果你的Nano已经能在BLHeliSuite中通过 `B SILABS C2 (4way-if)`读取设置，可跳过本节。

1. 断开Nano与电调之间的D2、D3和GND，只把Nano通过USB连接Windows电脑。
2. 打开8位版 **BLHeliSuite 16.7**，不要使用BLHeliSuite32。
3. 进入 `Make Interfaces`。
4. `Arduino Board`选择 `Nano w/ATmega328`，并选择Nano的COM口。
5. 国产老引导程序通常先试57600；失败再试115200。
6. 点击 `Arduino 4way-interface`。
7. 选择名称包含 `Nano`、`16`、`PD3PD2` 的接口固件，例如 `4wArduino_Nano__16_PD3PD2v20xxx.hex`。
8. 不要选择 `PB3PB4`，那会把C2接口改到D11/D12。

接口写入完成后关闭串口连接，再按第2节接线。

## 4. 写入前检查

1. 拆桨并断开电机；保存好已经读取的原厂16KiB备份及其哈希。
2. Nano连接USB，电调使用具有限流能力且可快速断开的电源正常供电。
3. 打开 `SiLabs ESC Setup`。
4. 在 `Select ATMEL / SILABS Interface`中选择 `B SILABS C2 (4way-if)`。
5. 选择Nano的COM口，点击 `Connect`，再点击 `Read Setup`。
6. 必须确认能够读到MCU/固件信息。你此前读到BLHeli_S 16.7设置，只说明C2链路和设置读取正常；`Read Setup`不是完整固件备份。

如果出现串口占用、连接失败或读数不稳定，应先修复供电、共地、COM口和焊接问题，不要直接尝试擦除。

## 5. 使用 Flash Other 手动烧录

1. 在连接和读取正常后点击 `Flash Other`。
2. 手动选择本仓库中的 `X_H_15_24_v0.21.0-omp2.hex`。
3. 再次核对文件名必须同时包含 `X_H_15_24`和`omp2`，并核对SHA-256。
4. BLHeliSuite若推荐自动匹配、自动升级或另一个已知布局，一律取消；这是私有布局X，只能使用上述手选文件。
5. 确认后开始烧录。此步骤会擦除原厂程序；过程中不要断USB、断电或碰动C2焊线。
6. 等待BLHeliSuite明确报告完成，再断开连接并给电调完全断电重启。

若BLHeliSuite在私有布局提示名称未知，不要据此换刷官方相似布局。只有写入过程明确报错时才停止，并保留完整错误信息。

## 6. 写入后检查

1. 重新选择 `B SILABS C2 (4way-if)`并连接。
2. 点击 `Read Setup`，检查固件身份应包含Bluejay和布局标签 `#X_H_15#`。
3. 不要点击自动修复或自动刷最新版。
4. BLHeliSuite能重新读取设置只证明通讯和设置区可访问，不是完整Flash逐字节验证；后续只保留这一种GUI路线，因此把“未做完整Flash回读比较”明确记录为剩余风险。
5. 刷写完成不等于硬件安全。首次上电必须继续执行[无电机检查和限流低速测试](../OMP_ESC_PORTING_GUIDE_zh-CN.md#7-第一次上电与示波器验收)，确认同一桥臂高低边不存在重叠后才可扩大测试范围。

## 7. 出错时立即停止的情况

- 选择的文件不是 `X_H_15_24_v0.21.0-omp2.hex`；
- SHA-256不一致；
- 无法稳定执行 `Read Setup`；
- BLHeliSuite识别到的MCU不是EFM8BB21；
- 写入时意外断电或C2线脱落；
- 上电后静态电流异常，FD6288或MOS迅速升温；
- 示波器发现同一桥臂高低边同时导通。

发生以上任一情况，不要反复尝试加油门；断开电调电源并先检查接线、供电和回读结果。
