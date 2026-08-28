/* fpga_spi.h ─ FPGA(Basys3) 상관 오프로딩 인터페이스
 *
 *   MCU(SPI2 마스터)가 START 를 올려 FPGA 상관을 시작시키고,
 *   DONE 이 뜨면 18개 int64 상관값(144 B, LE)을 SPI 로 읽어온다.
 *
 *   제어는 GPIO(START/DONE), 데이터는 SPI(읽기 전용). MOSI 미사용.
 *   위치: Core/Inc/fpga_spi.h
 */
#ifndef FPGA_SPI_H
#define FPGA_SPI_H

#include <stdint.h>
#include "main.h"      /* HAL, GPIOx, GPIO_PIN_x */
#include "proto.h"     /* N_PULSE(6), N_CAND(3) */

/* ── 핀맵 (NUCLEO Morpho CN10  <->  Basys3 Pmod JC) ──────────────────
 *  SCK  PB13 CN10-30 -> JC1     MISO PB14 CN10-28 <- JC4
 *  MOSI PB15 CN10-26 -> JC3     (미사용)
 *  아래 3개는 GPIO 로 직접 제어한다.                                    */
#define FPGA_CS_PORT     GPIOB
#define FPGA_CS_PIN      GPIO_PIN_12   /* CN10-16 -> JC2  (SPI CS, 액티브 로우) */
#define FPGA_START_PORT  GPIOB
#define FPGA_START_PIN   GPIO_PIN_1    /* CN10-24 -> JC7  (상승엣지 = 시작)     */
#define FPGA_DONE_PORT   GPIOB
#define FPGA_DONE_PIN    GPIO_PIN_2    /* CN10-22 <- JC8  (High = 완료)         */

/* START 펄스 -> DONE 대기 -> 144 B 수신 -> corr[k][c] 재조립.
 * 반환 0 = 성공, 1 = 타임아웃(배선/보드 확인). */
int FPGA_ReadCorr(int64_t corr[N_PULSE][N_CAND]);

#endif /* FPGA_SPI_H */
