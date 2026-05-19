# 31. 音频 DSP 引擎

## 是什么

在 MCU 上实时处理音频信号：变速率播放、混音、均衡器、空间音效、动态压缩。让小喇叭发出超越硬件极限的声音质感。

## 为什么需要

- 引擎模拟需要变速率播放（RPM→音高映射）
- 多层音频需要实时混音（idle + rev + knock + turbo）
- 小喇叭频响差，需要 EQ 补偿
- 音量突变需要动态压缩防止爆音/削波
- 空间感：让单声道喇叭听起来有"立体"效果

## 技术架构

```
┌─────────────────────────────────────────────────────┐
│                   音频 DSP 管线                       │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [音源层]                                            │
│   PCM Buffer 0 (idle)  ──┐                          │
│   PCM Buffer 1 (rev)   ──┤                          │
│   PCM Buffer 2 (knock) ──┼──→ [变速率插值]          │
│   PCM Buffer 3 (start) ──┘      │                   │
│                                  ▼                   │
│  [混音层]                                            │
│   各层音量加权求和 ──→ int32 累加                    │
│                          │                           │
│                          ▼                           │
│  [效果层]                                            │
│   EQ (3-band) → Compressor → Limiter → Soft Clip   │
│                          │                           │
│                          ▼                           │
│  [输出层]                                            │
│   int16 饱和 → I2S DMA → DAC/Class-D Amp → Speaker │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型

| 组件 | 技术 | 说明 |
|------|------|------|
| 音频输出 | I2S + 外部 DAC (MAX98357) | 16-bit 44100Hz |
| 变速率播放 | 定点数线性插值 (16.16) | 零额外内存，CPU 友好 |
| 混音 | int32 累加 + 饱和截断 | 防溢出 |
| EQ | 双二阶 IIR (Biquad) | 3 段参数 EQ |
| 压缩器 | 前馈式 RMS 检测 | attack/release 可调 |
| 限幅器 | 硬限幅 + soft knee | 防止 DAC 削波 |
| DMA 缓冲 | 双缓冲 ping-pong | 零拷贝，CPU 不等待 |

## 实现步骤

### Phase 1：变速率播放引擎（3-4h）

1. **定点数步进器**
   ```c
   #define FP_SHIFT 16
   #define FP_ONE   (1 << FP_SHIFT)
   
   typedef struct {
       const int8_t *samples;
       uint32_t length;        // 样本数
       uint32_t position;      // 16.16 定点当前位置
       uint32_t step;          // 16.16 定点步进（决定音高）
       bool loop;
   } voice_t;
   
   // 线性插值取样
   static inline int16_t voice_next_sample(voice_t *v) {
       uint32_t idx = v->position >> FP_SHIFT;
       uint32_t frac = v->position & 0xFFFF;
       int16_t s0 = v->samples[idx];
       int16_t s1 = v->samples[(idx + 1) % v->length];
       int16_t out = s0 + ((s1 - s0) * frac >> FP_SHIFT);
       v->position += v->step;
       if (v->loop && (v->position >> FP_SHIFT) >= v->length)
           v->position -= (v->length << FP_SHIFT);
       return out;
   }
   ```

2. **RPM 到步进映射**
   ```c
   // RPM 0-500 → 播放速率 100%-400%
   uint32_t rpm_to_step(int rpm) {
       int pct = map(rpm, 0, 500, 100, 400);
       return BASE_STEP * pct / 100;
   }
   ```

### Phase 2：混音器（1-2h）

3. **多层加权混音**
   ```c
   int32_t mix = 0;
   mix += voice_next_sample(&idle_voice) * idle_volume / 100;
   mix += voice_next_sample(&rev_voice) * rev_volume / 100;
   mix += voice_next_sample(&knock_voice) * knock_volume / 100;
   // 饱和到 int16 范围
   if (mix > 32767) mix = 32767;
   if (mix < -32768) mix = -32768;
   output[i] = (int16_t)mix;
   ```

4. **交叉淡入淡出**
   - idle→rev 过渡：RPM 上升时 idle 音量渐弱，rev 渐强
   - 避免突变导致的"咔嗒"声

### Phase 3：效果处理链（3-4h）

5. **3 段参数 EQ（Biquad IIR）**
   ```c
   typedef struct {
       float b0, b1, b2, a1, a2;  // 系数
       float x1, x2, y1, y2;      // 状态
   } biquad_t;
   
   float biquad_process(biquad_t *f, float in) {
       float out = f->b0*in + f->b1*f->x1 + f->b2*f->x2
                   - f->a1*f->y1 - f->a2*f->y2;
       f->x2 = f->x1; f->x1 = in;
       f->y2 = f->y1; f->y1 = out;
       return out;
   }
   
   // 低频增强（小喇叭补偿）
   // 中频凹陷（去除刺耳频段）
   // 高频提升（清晰度）
   ```

6. **动态压缩器**
   ```c
   typedef struct {
       float threshold;    // -20dB
       float ratio;        // 4:1
       float attack_ms;    // 5ms
       float release_ms;   // 50ms
       float envelope;     // 当前包络
   } compressor_t;
   ```
   - 作用：大音量时自动压缩，小音量时保持，防止削波同时保留动态

7. **软限幅（Soft Clip）**
   ```c
   // tanh 近似，比硬截断更自然
   float soft_clip(float x) {
       if (x > 1.0f) return 1.0f;
       if (x < -1.0f) return -1.0f;
       return x * (1.5f - 0.5f * x * x);  // 三次近似
   }
   ```

### Phase 4：I2S DMA 输出（1-2h）

8. **双缓冲 Ping-Pong**
   ```c
   #define BUFFER_SIZE 256  // 每次填充 256 样本 = 5.8ms @44100Hz
   int16_t buf_a[BUFFER_SIZE], buf_b[BUFFER_SIZE];
   
   // I2S 写完一个 buffer 触发回调 → 填充另一个
   // CPU 利用率：256 样本的 DSP 处理必须在 5.8ms 内完成
   ```

9. **性能预算**
   - 44100Hz / 256 样本 = 172 次/秒回调
   - 每次回调预算：5.8ms x 240MHz = ~1.4M 指令
   - 4 层变速率 + 混音 + 3 段 EQ + 压缩 = 每样本 ~50 指令 x 256 = 12800 指令
   - 余量充足（<1% CPU）

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| 整数溢出 | 混音时 int16 x 4 层超范围 | 用 int32 累加再饱和 |
| 插值噪声 | 变速率播放时高频混叠 | 线性插值已够，或加低通预滤波 |
| DMA 欠载 | 填充不及时导致爆音 | 提高音频任务优先级，双缓冲 |
| EQ 系数计算 | 运行时改频率需要重算系数 | 预计算查表，或用 cookbook 公式 |
| 浮点精度 | IIR 滤波器长时间运行漂移 | 定期清零状态或用 double |
| 喇叭烧毁 | 持续满功率输出 | 限幅器 + 热保护（检测温度） |

## 与 RideWind 的关系

- 当前状态：已实现变速率播放 + 多层混音（RC Engine 方案）
- 已有：idle/rev 交叉淡入、knock 脉冲、定点步进器
- 缺失：EQ 补偿、动态压缩、软限幅
- 下一步：加 EQ 让小喇叭低频更饱满，加压缩防止高 RPM 时爆音

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| 变速率引擎（已有） | 0h | ✅ |
| 混音器（已有） | 0h | ✅ |
| 3 段 EQ | 2-3h | ⭐⭐⭐ |
| 动态压缩器 | 2h | ⭐⭐⭐ |
| 软限幅 | 0.5h | ⭐ |
| 调参（听感优化） | 2-3h | ⭐⭐⭐⭐ |
| **总计** | **~1.5 天** | |

## 学到什么

- 数字信号处理基础（采样、量化、滤波）
- IIR/FIR 滤波器设计
- 音频动态处理（压缩、限幅、门控）
- 定点数运算在嵌入式中的应用
- DMA 双缓冲和实时音频管线
- 心理声学基础（人耳对频率/响度的非线性感知）
