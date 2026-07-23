# eLoran PPM Demodulation: MATLAB → MCU → FPGA

논문에서 제안한 eLoran 신호 PPM 복조 개선 알고리즘(CDC / MDD)을
실제 임베디드 하드웨어로 이식하고, 실시간 처리 성능을 최적화하는 프로젝트.

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
│ STM32 NUCLEO-F401RE │  PPM 복조
│ (Cortex-M4, 84 MHz) │  Correlation → CDC → MDD
└──────────┬──────────┘
           │  SPI
           ▼
┌─────────────────────┐
│  Basys3 (Artix-7)   │  Correlation 오프로딩
└─────────────────────┘
```

수신 신호의 전처리 및 TOA 추정은 PC가 담당하고, MCU는 복조만 수행한다.
복조 연산 중 correlation 구간만 FPGA로 분리해 처리시간을 단축하는 것이 목표다.

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
- 템플릿 길이 10000 → **3000 샘플** 축소
  (`SWEEP_TPL` 스윕 결과, 정확도 동일 · 상관 연산량 70 % 감소)

---

## 3. 진행 상황

- [x] MATLAB 알고리즘 검증 — BER / PER / SER, SNR −14 ~ +2 dB, 1000 iteration
- [x] 템플릿 길이 최적화 (10000 → 3000 샘플)
- [x] MCU 입력 데이터셋 추출 — SNR −12 ~ +4 dB × 30 iteration
- [ ] PC ↔ MCU UART 통신 프레임 구현 및 무결성 검증
- [ ] MCU 복조 이식 + TIM2 기반 처리시간 측정
- [ ] Correlation FPGA 오프로딩 + 처리시간 비교 (UART → SPI)

---

## 4. 저장소 구조

```
matlab/
  ppm/        PPM 변조 / 복조 / 매핑 테이블         ← 핵심 기여
  eval/       BER · PER · SER 성능 평가
  extract/    MCU용 데이터셋 추출 및 템플릿 길이 스윕
  external/   본 저장소 제외분(연구실 IP)의 인터페이스 명세
dataset/      추출된 신호(.bin) + 정답/기준결과(.mat) + 포맷 명세
firmware/     STM32CubeIDE 프로젝트 (예정)
fpga/         Basys3 HDL (예정)
```

**주요 파일**

| 파일 | 내용 |
|---|---|
| `matlab/ppm/F03_PPMDEM_20260305.m` | **제안 복조 알고리즘** (Corr → CDC → MDD) |
| `matlab/ppm/F09_PULIDX_20260115.m` | 3진수 해시 기반 O(1) 코드워드 매칭 |
| `matlab/eval/F10_LDCMAIN_20260119.m` | 성능 통계 누적 (BER / PER / SER) |
| `matlab/extract/EXTRACT_SIGNALS_20260404.m` | MCU 데이터셋 최종 추출 |
| `matlab/extract/SWEEP_TPL_20260404.m` | 템플릿 길이 vs 정확도 스윕 |

---

## 5. 개발 환경

| 항목 | 사양 |
|---|---|
| S/W Validation | MATLAB R2025b (fs = 10 MHz, GRI 99300 µs) |
| MCU | STM32 NUCLEO-F401RE, HSE BYPASS 8 → 84 MHz |
| 성능 측정 | TIM2 (32-bit, Prescaler 83 → 1 µs tick) |
| 통신 | USART2 (PA2 / PA3, Virtual COM), 460800 bps |
| FPGA | Basys3 (Artix-7 XC7A35T) |
| Tools | STM32CubeIDE 2.1.1, Vivado 2022.2 |

---

## 6. 저장소 범위에 대한 안내

수신신호 생성(`G*`), 펄스 템플릿(`P*`), 전처리 및 Coarse TOA 추정 체인은
소속 연구실의 자산에 해당하여 본 저장소에서 **제외**했습니다.
공개 범위는 PPM 변복조, 성능 평가, MCU 데이터셋 추출 및 이후의 펌웨어 · HDL 구현이며,
제외된 함수의 호출 인터페이스는 [`matlab/external/README.md`](matlab/external/README.md)에
명시했습니다.

이에 따라 MATLAB 코드는 단독 실행되지 않으나,
`dataset/` 에 추출 결과가 포함되어 있어
**펌웨어 개발 및 검증은 본 저장소만으로 재현 가능**합니다.
