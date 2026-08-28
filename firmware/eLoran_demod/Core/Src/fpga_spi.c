/* fpga_spi.c ─ 위치: Core/Src/fpga_spi.c */

#include "fpga_spi.h"
#include "spi.h"       /* hspi2  (CubeMX 가 SPI2 활성화 시 생성) */
#include "tim.h"       /* htim2  (타임아웃용 us 카운터) */

#define SPI_BYTES        (N_PULSE * N_CAND * 8)   /* 18 * 8 = 144 */
#define FPGA_TIMEOUT_US  2000u                    /* DONE 대기 상한 */

static inline uint32_t us_now(void) { return __HAL_TIM_GET_COUNTER(&htim2); }

int FPGA_ReadCorr(int64_t corr[N_PULSE][N_CAND])
{
    uint8_t rx[SPI_BYTES];

    /* 1) 시작: START 상승엣지 */
    HAL_GPIO_WritePin(FPGA_START_PORT, FPGA_START_PIN, GPIO_PIN_SET);

    /* FPGA 는 이 엣지 후 ~40 ns 안에 DONE 을 0 으로 내린다.
     * 이전 실행의 DONE=1 을 잘못 읽지 않도록 충분히(수 us) 안정화한다. */
    for (volatile int i = 0; i < 300; i++) __NOP();

    /* 2) 완료 대기 (DONE High) */
    uint32_t t0 = us_now();
    while (HAL_GPIO_ReadPin(FPGA_DONE_PORT, FPGA_DONE_PIN) == GPIO_PIN_RESET) {
        if ((uint32_t)(us_now() - t0) > FPGA_TIMEOUT_US) {
            HAL_GPIO_WritePin(FPGA_START_PORT, FPGA_START_PIN, GPIO_PIN_RESET);
            return 1;                                  /* 타임아웃 */
        }
    }

    /* 3) 결과 144 B 수신 (CS 액티브 로우) */
    HAL_GPIO_WritePin(FPGA_CS_PORT, FPGA_CS_PIN, GPIO_PIN_RESET);
    HAL_SPI_Receive(&hspi2, rx, SPI_BYTES, HAL_MAX_DELAY);
    HAL_GPIO_WritePin(FPGA_CS_PORT, FPGA_CS_PIN, GPIO_PIN_SET);

    HAL_GPIO_WritePin(FPGA_START_PORT, FPGA_START_PIN, GPIO_PIN_RESET); /* 해제 */

    /* 4) 18 x int64 재조립 (각 값 LE, 순서 = 펄스-메이저·후보-마이너)
     *    p = k*N_CAND + c  ->  corr[k][c] = rx[p*8 .. p*8+7] (LE) */
    for (int p = 0; p < N_PULSE * N_CAND; p++) {
        int k = p / N_CAND;
        int c = p % N_CAND;
        int64_t v = 0;
        for (int i = 0; i < 8; i++)
            v |= (int64_t)rx[p * 8 + i] << (8 * i);
        corr[k][c] = v;
    }
    return 0;
}
