/* demod.h ─ 논문 Fig.2 의 3단계 심볼 결정
 *
 *   Step 1  Baseline : 후보별 최대 상관 -> 변조 패턴 표 직접 조회
 *   Step 2  CDC      : 상관차가 작은 후보를 대체하여 유효 패턴 재탐색
 *   Step 3  MDD      : 표의 모든 패턴과 L1 거리 비교, 최소 거리 강제 선택
 *
 *   위치: Core/Inc/demod.h
 */
#ifndef DEMOD_H
#define DEMOD_H

#include <stdint.h>
#include "proto.h"

/* state 값 */
#define STATE_HARD  0
#define STATE_CDC   1
#define STATE_MDD   2

typedef struct {
    int8_t  est_pulses[N_PULSE];  /* Step 1 의 argmax 결과 (보정 전). 검증용 */
    int8_t  rx_pulses[N_PULSE];   /* 최종 확정된 변조 패턴 */
    uint8_t bits[N_BITS];         /* 최종 7비트 */
    uint8_t state;                /* STATE_HARD / STATE_CDC / STATE_MDD */
} DemodResult;

/* 729-entry 해시 테이블 생성. main 진입 직후 1회 호출. */
void DEMOD_Init(void);

/* 상관값 -> 최종 심볼.
 * est_pulses 는 보정 전 값을 그대로 남기므로 est_pulses_sl 과 대조할 수 있다. */
void DEMOD_Run(const int64_t corr[N_PULSE][N_CAND], DemodResult *out);

#endif /* DEMOD_H */
