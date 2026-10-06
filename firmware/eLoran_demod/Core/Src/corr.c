/* corr.c ─ 위치: Core/Src/corr.c
 *
 *   TPL[], CAND[] 는 tpl_D10.h (EXTRACT_SIGNALS_D 자동 생성) 에서 온다.
 *   TPL 은 이 파일에서만 참조하므로 tpl_D10.h 도 여기서만 실제로 쓰인다.
 */

#include "corr.h"
#include "arm_math.h"

void CORR_Compute(const int16_t *seg, int64_t corr[N_PULSE][N_CAND])
{
    for (int k = 0; k < N_PULSE; k++) {

        const int16_t *slice = &seg[k * SEG_LEN];   /* 305 샘플 */

        for (int c = 0; c < N_CAND; c++) {

            const int16_t *x = &slice[CAND[c]];     /* 후보 시작점 0/1/2 */
            int64_t acc = 0;

            for (int n = 0; n < TPL_LEN; n++)
                acc += (int32_t)x[n] * (int32_t)TPL[n];

            corr[k][c] = acc;
        }
    }
}

void CORR_Compute_DSP(const int16_t *seg, int64_t corr[N_PULSE][N_CAND])
{
    for (int k = 0; k < N_PULSE; k++) {
        const q15_t *slice = &seg[k * SEG_LEN];

        for (int c = 0; c < N_CAND; c++) {
            arm_dot_prod_q15(&slice[CAND[c]], TPL, TPL_LEN, &corr[k][c]);
        }
    }
}
