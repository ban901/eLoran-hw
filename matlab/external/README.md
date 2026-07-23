# External Dependencies (제외분)

아래 함수들은 소속 연구실의 자산에 해당하여 본 저장소에서 제외했습니다.
저장소에 포함된 코드가 이들을 호출하므로, **호출 인터페이스만** 명시합니다.

---

## 신호 생성 체인 (G*)

| 함수 | 시그니처 | 역할 |
|---|---|---|
| `G10_TXMAIN_20251223` | `[rcv_total, tx_bits, tx_pulses] = f(snr)` | 다중 송신국 합성 수신신호 생성 (main) |
| `G11_CFG_20251223` | `config = f(snr)` | 시뮬레이션 설정 |
| `G13_PULSE_20251223` | `nomsig = f(fs)` | Nominal 펄스 생성 |
| `G14_PHASE_20251223` | `[master, secondary] = f(nomsig, fs)` | 위상코드 펄스 트레인 |
| `G16_RXSIM_20251223` | `[rx, A_idx, bits7, pulses] = f(cfg, mPhase, sPhase, offset)` | 송신국별 수신신호 합성 + PPM 변조 적용 |
| `G17_NOISE_20251223` | `y = f(x, snr_db, mode)` | AWGN 부가 |

## 펄스 템플릿 (P*)

| 함수 | 시그니처 | 역할 |
|---|---|---|
| `P10_PULSE_20251223` | `nomsig = f(fs)` | 단일 펄스 템플릿 (길이 = 1 ms @ fs) |
| `P11_PHASE_20251223` | `[master, secondary] = f(nomsig, fs)` | 위상코드 반영 baseband 템플릿 트레인 |

## 전처리 / Coarse TOA (M10)

| 함수 | 시그니처 | 역할 |
|---|---|---|
| `M10_COARSETOA_20251223` | `[tx_bits, est_bits, tx_pulses, est_pulses, rx_pulses, state] = f(snr)` | BPF → analytic → xcorr 기반 Coarse TOA → 프레임정렬 → 복조 |

---

## 코드 연결(호출) 관계

```
F01_PPMCFG       →  (없음)
F03_PPMDEM       →  P10_PULSE                        (펄스 템플릿 생성)
F10_LDCMAIN      →  M10_COARSETOA                    (통계 루프에서 반복 호출)
EXTRACT_SIGNALS  →  P10_PULSE, M10_EXTRACT
EXTRACT_FULL     →  P10_PULSE, M10_EXTRACT
M10_EXTRACT      →  G10_TXMAIN, G13_PULSE, G14_PHASE
```

따라서 본 저장소의 MATLAB 코드는 **단독 실행되지 않으며**,
알고리즘 구현 및 설계 의도의 열람을 목적으로 공개합니다.
MCU/FPGA 이식에 필요한 신호 데이터는 `dataset/` 에 결과물 형태로 포함되어 있어,
펌웨어 개발 및 검증은 본 저장소만으로 재현 가능합니다.
