# eLoran Correlation Front-End (Basys3 / Artix-7)

PC --UART 460800--> **[Basys3: 상관]** --SPI2--> STM32 복조

FPGA는 PC에서 받은 슬라이싱 신호로 상관 18회(6펄스×3후보)를 계산해 int64 결과를 MCU로 보내는 순수 상관기다. 판정(Step1/CDC/MDD)은 MCU가 한다.

검증: iteration 0 신호로 **UART→상관→SPI 전 구간 시뮬레이션 결과 18개 int64가 MATLAB `est_pulses_sl` 및 참조 상관값과 100% 일치**.

---

## 1. 데이터 흐름 / 제어

1. **신호 적재 (UART, 측정 제외)** — PC가 프레임을 Basys3 온보드 USB-UART로 전송 → `frame_rx`가 파싱·CRC 확인 후 1830개 int16을 `seg_ram`(BRAM)에 저장. 완료 시 `led[0]=loaded`, `led[1]=crc_ok`.
2. **상관 시작 (측정 포함)** — MCU가 `corr_start` GPIO를 상승 → `correlator`가 18×300 MAC 수행. `led[2]=busy`.
3. **완료 알림** — 끝나면 `corr_done` GPIO High 유지. `led[3]=done`.
4. **결과 읽기** — MCU가 CS Low로 144바이트를 클럭 → `spi_slave`가 결과를 MISO로 스트림.

> 제어는 GPIO(START/DONE)로 하고 **SPI는 읽기 전용**이다. 미결사항(9장)의 “GPIO DONE 신호” 방식을 채택했다(폴링 대비 SPI 낭비 없음, 처리시간 측정이 정확).

## 2. 모듈

| 파일 | 역할 |
|---|---|
| `uart_rx.v` | 8N1 UART 수신 (`CLKS_PER_BIT=217` = 100MHz/460800) |
| `frame_rx.v` | SOF/TYPE/PAYLOAD/CRC-16 파싱, seg 쓰기 |
| `seg_ram.v` | 신호 저장 BRAM (1830×16b, 듀얼포트) |
| `tpl_rom.v` | 템플릿 300탭 ROM (tpl_D10.h에서 자동생성) |
| `correlator.v` | 파이프라인 MAC 상관기 (int64×18) |
| `spi_slave.v` | SPI mode0 슬레이브, 144B 스트림 |
| `corr_top.v` | 전체 결선 |

## 3. 반드시 맞춰야 할 규약 (PC/MCU와 일치 확인)

- **UART 프레임**: `[0xA5 0xC3][TYPE=0x04][PAYLOAD 3660B][CRC16 2B]`
- **PAYLOAD**: int16 LE, 펄스-메이저 (`seg[k][n]` → 바이트 `(k*305+n)*2`). `.bin`의 `[305×6]` column-major와 동일.
- **CRC-16/CCITT-FALSE** (poly 0x1021, init 0xFFFF), 검증값 `"123456789"→0x29B1`.
  - ⚠️ **커버리지 = TYPE+PAYLOAD**, 전송순서 = **hi 바이트 먼저**. PC MATLAB이 다르면 `frame_rx.v`에서 수정.
  - CRC 불일치여도 데이터는 저장됨(`crc_ok=0`으로만 표시) → 브링업 디버깅 편의.
- **SPI 결과 바이트 순서**: 각 int64 **LE**, 쌍 순서는 **펄스-메이저·후보-마이너**
  `p0c0, p0c1, p0c2, p1c0, …, p5c2` (총 144B).
- **SPI 모드 0** (CPOL=0, CPHA=0), **MSB first** — MCU CubeMX 설정과 동일해야 함.

## 4. 배선 (Pmod JC ↔ MCU, 총 7가닥 + GND)

| 신호 | FPGA Pmod JC | 방향 | MCU (PB / CN10) |
|---|---|---|---|
| SCK | JC1 (K17) | MCU→FPGA | PB13 / CN10-30 |
| CS | JC2 (M18) | MCU→FPGA | PB12 / CN10-16 |
| MOSI | JC3 (N17) | (미사용) | PB15 / CN10-26 |
| MISO | JC4 (P18) | FPGA→MCU | PB14 / CN10-28 |
| START | JC7 (L17) | MCU→FPGA | GPIO out 예: PB1 / CN10-24 |
| DONE | JC8 (M19) | FPGA→MCU | GPIO EXTI 예: PB2 / CN10-22 |
| GND | JC 5 or 11 | 공통 | CN10-9 |

VCC는 연결하지 않는다(각 보드 독립 전원). PC↔FPGA UART는 Basys3 프로그래밍용 micro-USB를 그대로 사용.

## 5. 시뮬레이션 (iverilog)

```bash
cd sim
# 상관기 단독
iverilog -g2012 -o s1 tb_correlator.v ../rtl/correlator.v seg_ram_tb.v ../rtl/tpl_rom.v && vvp s1
# 전 구간 (UART→상관→SPI)
iverilog -g2012 -o s2 tb_top.v ../rtl/corr_top.v ../rtl/uart_rx.v ../rtl/frame_rx.v \
   ../rtl/seg_ram.v ../rtl/correlator.v ../rtl/tpl_rom.v ../rtl/spi_slave.v && vvp s2
```
기대 출력: `ALL 18 MATCH` / `END-TO-END: ALL 18 MATCH`. (`seg0.hex`,`expected.hex`,`frame0.hex`는 iteration 0 데이터)

## 6. MCU 읽기 예시 (참고)

```c
// corr_done 상승엣지 EXTI 콜백에서 flag set 후, main에서:
uint8_t rx[144];
HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_RESET);   // CS Low
HAL_SPI_Receive(&hspi2, rx, 144, 10);                    // 144B 수신
HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_SET);     // CS High
int64_t corr[18];
for(int p=0;p<18;p++){ int64_t v=0;
    for(int i=0;i<8;i++) v |= (int64_t)rx[p*8+i] << (8*i);  // LE
    corr[p]=v; }
// est_pulse[k] = argmax_c(corr[k*3+c]) - 1;
```

시작 트리거: `HAL_GPIO_WritePin(START)` High 펄스 → `corr_done` 대기 → 위 읽기.

## 7. 성능 / 자원

- 상관 계산 **~5436 사이클 @100MHz ≈ 54.4 µs** (1 MAC/cycle 직렬, DSP48 1개).
- SPI 전송 144B @10.5MHz ≈ 110 µs. 합계 ≈ **165 µs** (요구서 예상 123~168 µs 부합).
- **9 µs 목표로 단축하려면**: 상관기를 병렬화. 6펄스를 6개 MAC로 동시 계산(6×DSP)하면 ~9 µs. `correlator.v`의 탭 루프를 펄스별로 복제하면 됨(현재는 명료성 위해 직렬).
- BRAM: seg 1개 + tpl 1개. LUT/FF 소량. xc7a35t에 충분.

## 8. 스코프 밖 / 다음 단계

- PC 전처리(BPF/Hilbert/포락선/TOA)는 PC 담당(변경 없음).
- 다중 iteration 연속 처리: 현재는 프레임 1개 로드→상관 1회. 연속 스트리밍이 필요하면 `frame_rx`가 매 프레임 seg를 갱신하고 MCU가 START를 반복하면 됨.
- 병렬 상관기 버전이 필요하면 요청 바람.
