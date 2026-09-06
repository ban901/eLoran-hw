# eLoran PPM Demodulation: MATLAB → FPGA → MCU

논문에서 제안한 eLoran 신호 PPM 복조 개선 알고리즘(CDC / MDD)을
실제 임베디드 하드웨어로 이식하고, 실시간 처리 성능을 최적화하는 프로젝트.

> Park & Son, CDC/MDD 보정 알고리즘을 이용한 Eurofix 기반 eLoran LDC 복조 성능 향상,
> JPNT 15(2), 175-181, 2026.

개발 과정과 설계 근거는 [노션 문서](https://ban91.notion.site/eLoran-HW-3a6c4613717d80fe9330dda7ed12e0ce)에 정리하였다.

---

## 1. 시스템 구성

```
┌─────────────────────┐
│    PC (MATLAB)      │  전처리 + Coarse TOA 추정
│                     │  → 펄스 조각 신호 생성
└──────────┬──────────┘
           │  UART 460800 bps
           ▼
┌─────────────────────┐
│  Basys3 (Artix-7)   │  Correlation
└─────────────────────┘
           │  SPI (상관 결과 전송)
           ▼
┌─────────────────────┐
│ STM32 NUCLEO-F401RE │  PPM 복조
│ (Cortex-M4, 84 MHz) │  CDC → MDD
└──────────┬──────────┘
```

PC는 ADC를 대신하는 시험용 신호원이며, 전처리와 Coarse TOA 추정을 담당한다.
실제 수신기에서는 이 경로가 ADC → DMA로 대체된다.

FPGA는 상관 연산만 담당하고 결과값(6 펄스 * 3 후보)을 MCU로 넘긴다.
상용 항법 수신기가 반복 연산은 FPGA에, 분기가 많은 판정 로직은 프로세서에
배치하는 것과 같은 이종 구조이다.

**목표 처리시간**: GRI 99.3 ms의 1 %인 993 µs 이하 (1 iteration = 6 펄스 = 1 심볼)

---

## 2. 알고리즘 개요

Eurofix 에서 7-bit 데이터는 6개 펄스의 PPM shift(−1 / 0 / +1 µs)로 전송된다.
수신 포락선(envelope)과 펄스 템플릿의 상관을 이용해 각 펄스의 shift를 추정하고,
테이블 매핑으로 비트를 복원한다.

| Stage | 처리 | state |
|:---:|---|:---:|
| 1 | 3개 후보 위치 상관 → argmax (hard decision) | 0 |
| 2 | 상관값 차이가 임계 이하인 펄스를 재탐색 (CDC) | 1 |
| 3 | 최소 거리 펄스 패턴으로 강제 매핑 (MDD) | 2 |

**MCU 이식을 고려한 연산 최적화**

- 펄스패턴 → 인덱스 : 3진수 키(729-entry LUT)로 O(1) 조회
  (`F09_PULIDX`, 기존 테이블 선형탐색 대체)
- 비트 → 인덱스 : 이진 가중합으로 O(1) 계산 (`F08_BITIDX`)
- 템플릿 길이 10,000 → **3,000 샘플** (`SWEEP_TPL` 스윕, 정확도 동일)
- 샘플링률 10 MHz → 1 MHz (D=10 데시메이션)
- 결과: iteration 당 전송량 **120,000 B → 3,660 B (3 %)**, MATLAB 동치성 유지

---

## 3. 진행 상황

- [x] MATLAB 알고리즘 검증 — BER / PER / SER, SNR −14 ~ +2 dB, 1000 iteration
- [x] 템플릿 길이 최적화 (10,000 → 3,000 샘플)
- [x] MCU 입력 데이터셋 추출 — SNR −12 ~ +4 dB * 30 iteration
- [x] 샘플링률 최적화 (D=10, 3,665 B / iteration)
- [x] PC ↔ MCU UART 통신 프레임 구현 및 무결성 검증
- [x] MCU 복조 이식 — MATLAB 대비 동치성 30/30
- [x] 처리시간 프로파일링 — `-O2` 733 µs / 993 µs (74 %)
- [x] 구조 재설계 — FPGA를 프론트엔드로 재배치 (전송량 3,665 B → 149 B)
- [x] FPGA 상관 IP 설계
- [x] MCU-FPGA 연동 및 처리시간 비교

**측정 결과 (STM32F401RE, `-O2`, 1 iteration)**

| 구간 | 최대 |
|---|---|
| Correlation | 599.7 µs (전체의 82 %) |
| Decision (Step 1 / CDC / MDD) | 133.2 µs |
| **Total** | **733.3 µs** |

---

## 4. 저장소 구조

```
matlab/
  ppm/        PPM 변조 / 복조 / 매핑 테이블
  eval/       BER / PER / SER 성능 평가
  extract/    MCU용 데이터셋 추출 및 템플릿 길이 스윕
  external/   본 저장소 제외분(연구실 IP)의 인터페이스 명세
dataset/      추출된 신호(.bin) + 정답/기준결과(.mat) + 포맷 명세
firmware/     STM32CubeIDE 프로젝트
fpga/         Basys3 HDL
```

**주요 파일**

| 파일 | 내용 |
|---|---|
| `matlab/ppm/F03_PPMDEM_20260305.m` | **제안 복조 알고리즘** (Corr → CDC → MDD) |
| `matlab/ppm/F09_PULIDX_20260115.m` | 3진수 해시 기반 O(1) 코드워드 매칭 |
| `matlab/eval/F10_LDCMAIN_20260119.m` | 성능 통계 누적 (BER / PER / SER) |
| `matlab/extract/EXTRACT_SIGNALS_20260404.m` | MCU 데이터셋 최종 추출 |
| `matlab/extract/SWEEP_TPL_20260404.m` | 템플릿 길이 vs 정확도 스윕 |
| `matlab/comm/DEMOD_TEST.m` | MCU 복조 검증 (동치성 대조 및 처리시간 수집) |
| `firmware/eLoran_demod/Core/Src/corr.c` | 상관 연산 |
| `firmware/eLoran_demod/Core/Src/demod.c` | Step 1 / CDC / MDD |
| `firmware/eLoran_demod/Core/Src/frame.c` | UART 프레임 상태머신 / CRC-16 |

---

## 5. 개발 환경

| 항목 | 사양 |
|---|---|
| S/W Validation | MATLAB R2025b (fs = 10 MHz, GRI 99300 µs) |
| MCU | STM32 NUCLEO-F401RE, HSE BYPASS 8 → 84 MHz |
| 성능 측정 | TIM2 (32-bit, Prescaler 83 → 1 µs tick) |
| 통신 | USART2 (PA2 / PA3, Virtual COM), 460800 bps |
| FPGA | Basys3 (Artix-7 XC7A35T, 100 MHz) |
| Tools | STM32CubeIDE 2.1.1, Vivado 2022.2 |

---

## 6. 저장소 범위에 대한 안내

수신신호 생성(`G*`), 펄스 템플릿(`P*`), 전처리 및 Coarse TOA 추정 체인은
소속 연구실의 자산에 해당하여 본 저장소에서 **제외**하였다.
공개 범위는 PPM 변복조, 성능 평가, MCU 데이터셋 추출 및 이후의 펌웨어 & HDL 구현이며,
제외된 함수의 호출 인터페이스는 [`matlab/external/README.md`](matlab/external/README.md)에
명시하였다.

이에 따라 MATLAB 코드는 단독 실행되지 않으나,
`dataset/` 에 추출 결과가 포함되어 있어
**펌웨어 개발 및 검증은 본 저장소만으로 재현 가능**하다.
