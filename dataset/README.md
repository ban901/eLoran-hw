# Dataset Format Specification

`EXTRACT_SIGNALS_20260404.m` 로 생성된 MCU 입력용 데이터셋.
MATLAB 없이도 펌웨어 개발/검증이 가능하도록 신호와 정답을 함께 제공한다.

생성 조건: `rng(993)` 고정 → 동일 시드로 언제 재생성해도 동일 데이터.

---

## 1. `signal_SNR{±xx}.bin` — 신호 조각

| 항목 | 값 |
|---|---|
| 자료형 | `int16` (little-endian) |
| 배열 형상 | `[3050 × 6 × 30]` = `[WIN_LEN × N_DATA × N_ITER]` |
| 저장 순서 | **column-major** (MATLAB 기본) |
| 파일 크기 | 3050 × 6 × 30 × 2 B = 1,098,000 B |
| SNR | -12, -8, -4, 0, +4 dB (5개 파일) |

### 읽는 순서 (C 기준)

```c
/* sample 이 가장 빠르게 변하고, iteration 이 가장 느리게 변한다 */
for (it = 0; it < 30; it++)
    for (k = 0; k < 6; k++)          /* 데이터펄스 3~8번 */
        for (n = 0; n < 3050; n++)   /* 샘플 */
            read(&buf[((it*6) + k)*3050 + n]);
```

한 조각(펄스 1개) = 3050 샘플 = 6100 B
한 iteration = 6 조각 = 36,600 B

### 값의 의미

각 샘플은 **전처리 완료된 수신신호의 포락선** `abs(x_lp)` 를 int16으로
스케일링한 값이다.

```
sig_i16 = round( env * scale )
scale   = 32767 / max(env of this iteration)
```

`scale` 은 iteration 단위로 다르며 `.mat` 의 `int16_scale` 에 저장된다.
**단, 복조는 argmax 기반이라 스케일에 무관하므로 MCU에서는 복원 불필요.**
(정확한 상관값 비교/디버깅 시에만 사용)

---

## 2. 조각 좌표계 ★중요★

```
원신호 좌표:      ... ─────┬──────────────────────── ...
                        nominal
조각 시작 s0 = nominal - WIN_GUARD + 1   (WIN_GUARD = 20)

조각 내부 (1-based):
  index:  1 ......... 10 ......... 20 ......... 30 ......... 3050
                       │           │            │
                    후보(-1)   후보(0/nominal)  후보(+1)
```

| 상수 | 값 | 의미 |
|---|---|---|
| `WIN_LEN` | 3050 | 조각 길이 [샘플] |
| `WIN_GUARD` | 20 | 조각 내 nominal 위치 (1-based) |
| `SHIFT` | 10 | PPM 1 µs @ fs=10 MHz = 10 샘플 |
| `TPL_USE` | 3000 | 상관에 쓰는 템플릿 길이 |
| 후보 위치 | 10, 20, 30 | 각각 shift = -1, 0, +1 에 대응 |

**0-based(C) 로는 후보 = 9, 19, 29.**

상관 연산:
```
cval[c] = Σ_{n=0}^{2999}  seg[cand[c] + n] * tpl[n]
sel     = argmax(cval)            →  pulse = sel - 1  (0/1/2 → -1/0/+1)
```

`TPL_USE = 3000` 은 500~10000 스윕(`SWEEP_TPL_20260404.m`) 결과
정확도 저하 없이 사용 가능한 최소 길이로 결정했다.
(3000 미만은 펄스 봉우리를 절반만 포함해 정확도가 랜덤 수준으로 급락)

---

## 3. `dataset_SNR{±xx}.mat` — 정답 및 기준결과

구조체 `ds` 하나로 저장.

| 필드 | 크기 | 내용 |
|---|---|---|
| `snr` | 1 | SNR [dB] |
| `n_iter` / `n_data` | 1 / 1 | 30 / 6 |
| `data_idx` | 1×6 | 데이터펄스 번호 (3:8) |
| `win_len` / `win_guard` / `tpl_use` / `shift` | 1 | 3050 / 20 / 3000 / 10 |
| `nom_in_slice` | 1 | 조각 내 nominal (1-based) = 20 |
| `int16_scale` | 30×1 | iteration별 스케일 계수 |
| `bin_layout` | str | `.bin` 배치 설명 |
| **`tx_pulses`** | 30×6 | **정답 펄스 (-1/0/+1)** |
| **`tx_bits`** | 30×7 | **정답 비트** |
| `est_pulses_ml` | 30×6 | MATLAB(F03) 추정 펄스 — 기준선 |
| `est_bits_ml` | 30×7 | MATLAB(F03) 추정 비트 |
| `state_ml` | 30×1 | 복조 경로 (0=hard, 1=CDC, 2=fallback) |
| `est_pulses_sl` | 30×6 | 조각 재상관 결과 (좌표계 검증용) |
| `nominal` | 30×6 | 원신호 좌표의 nominal (참고용) |
| `tpl_use_vec` | 3000×1 | 상관에 쓴 템플릿 |

### MCU 검증 방법

MCU 복조 결과를 `tx_pulses` (정답) 와 비교하면 절대 정확도,
`est_pulses_ml` 과 비교하면 **MATLAB 대비 비트-정합성**을 확인할 수 있다.
이식 검증 단계에서는 후자가 우선 — 두 결과가 완전히 일치해야
"알고리즘이 올바르게 옮겨졌다"고 말할 수 있다.

---

## 4. UART 전송량 참고

한 iteration = 36,600 B.
460800 bps (8N1, 프레임당 10 bit) 기준 ≈ **0.79 s / iteration**.

→ 이 값이 성능 측정 시 통신 오버헤드로 잡히는 부분이며,
   MCU↔FPGA 구간을 SPI로 전환하려는 근거가 된다.
