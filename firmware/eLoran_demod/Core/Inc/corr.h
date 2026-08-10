/* corr.h ─ 논문 식 (2) 앞단: 후보 위치별 상관값 계산
 *
 *   위치: Core/Inc/corr.h
 */
#ifndef CORR_H
#define CORR_H

#include <stdint.h>
#include "proto.h"

/* 6펄스 × 3후보 = 18회 상관.
 *
 *   seg  : CMD_LOAD 페이로드를 int16 로 본 것. 길이 SEG_LEN*N_PULSE (=1830)
 *          펄스 k 의 n 번째 샘플 = seg[k*SEG_LEN + n]
 *   corr : 결과. corr[k][c] = 펄스 k, 후보 c 의 상관값
 *          c = 0/1/2 는 각각 PPM shift -1/0/+1 에 대응
 *
 *   누산기는 int64. 실측 최대 상관값이 8.99e10 으로 int32 한계(2.15e9)의
 *   약 42배이므로 int32 로는 반드시 넘친다.
 */
void CORR_Compute(const int16_t *seg, int64_t corr[N_PULSE][N_CAND]);

#endif /* CORR_H */
