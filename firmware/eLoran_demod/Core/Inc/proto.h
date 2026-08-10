/* proto.h ─ PC(MATLAB) <-> STM32 UART 프레임 정의
 *
 *   [SOF 2B][TYPE 1B][PAYLOAD][CRC 2B]
 *
 *   CRC-16/CCITT-FALSE, 검사 범위 = TYPE ~ PAYLOAD 끝 (SOF 제외), LE 전송
 *   다중 바이트 필드는 모두 리틀엔디언
 *
 *   위치: Core/Inc/proto.h
 */
#ifndef PROTO_H
#define PROTO_H

#include <stdint.h>
#include "tpl_D10.h"      /* SEG_LEN(305), N_PULSE(6), TPL_LEN(300), N_CAND(3) */

#define N_BITS                  7        /* Eurofix 데이터 심볼 비트 수 */

/* ── SOF ─────────────────────────────────────────────────────────── */
#define PROTO_SOF0              0xA5u
#define PROTO_SOF1              0xC3u

/* ── TYPE ────────────────────────────────────────────────────────── */
#define PROTO_CMD_LOAD          0x04u    /* PC->MCU, 3660 B */
#define PROTO_CMD_DEMOD         0x05u    /* PC->MCU,    0 B */
#define PROTO_RSP_RESULT        0x85u    /* MCU->PC,   31 B */

/* ── 페이로드 길이 ───────────────────────────────────────────────── */
#define PROTO_LEN_LOAD          (SEG_LEN * N_PULSE * 2)   /* 3660 */
#define PROTO_LEN_DEMOD         0
#define PROTO_LEN_RESULT        31

#define PROTO_OVERHEAD          5        /* SOF 2 + TYPE 1 + CRC 2 */

/* ── RSP_RESULT 페이로드 오프셋 (31 B) ───────────────────────────── */
#define RES_OFF_EST_PULSES      0        /*  6 B  int8  -1/0/+1 */
#define RES_OFF_BITS            6        /*  7 B  uint8 0/1     */
#define RES_OFF_STATE          13        /*  1 B  0=hard 1=CDC 2=MDD */
#define RES_OFF_STATUS         14        /*  1 B  0=정상 1=신호 미로드 */
#define RES_OFF_T_CORR         15        /*  4 B  uint32 [us] */
#define RES_OFF_T_DECIDE       19        /*  4 B */
#define RES_OFF_T_COMM         23        /*  4 B */
#define RES_OFF_T_TOTAL        27        /*  4 B */

/* status 값 */
#define STATUS_OK               0
#define STATUS_NO_SIGNAL        1

#endif /* PROTO_H */
