// frame.h ─ UART 프레임 수신 상태머신 + 결과 송신 + CRC
//
//   수신은 인터럽트에서 1바이트씩 FRAME_FeedByte() 로 밀어 넣는다.
//   전송 계층에 의존하지 않으므로 나중에 DMA 나 SPI 로 바꿔도 그대로 쓴다.
//
//   위치: Core/Inc/frame.h

#ifndef FRAME_H
#define FRAME_H

#include <stdint.h>
#include "proto.h"

typedef enum {
    FRAME_NONE = 0,
    FRAME_LOAD,      // CMD_LOAD  수신 완료
    FRAME_DEMOD      // CMD_DEMOD 수신 완료 -> 복조 실행
} FrameEvent;

typedef struct {
    uint32_t n_ok;         // CRC 까지 통과한 프레임 수
    uint32_t n_crc_err;
    uint32_t n_type_err;   // 정의되지 않은 TYPE
    uint32_t n_timeout;    // 프레임 도중 끊김
    uint32_t n_uart_err;   // 오버런 등
} FrameStat;

void FRAME_Init(void);

// UART 수신 인터럽트에서 호출
void FRAME_FeedByte(uint8_t b);

// 메인 루프에서 주기적으로 호출. 프레임 도중 끊기면 파서를 되돌린다.
void FRAME_Tick(void);

// 이벤트 하나를 꺼낸다 (읽으면 지워진다). 없으면 FRAME_NONE
FrameEvent FRAME_TakeEvent(void);

// 수신 버퍼의 신호를 처리 버퍼로 옮긴다. 메인 루프에서 호출.
// 새로 확정된 신호가 없으면 아무것도 하지 않는다.
void FRAME_CommitSignal(void);

// 처리 버퍼를 int16 배열로 본 것. seg[k*SEG_LEN + n]
const int16_t *FRAME_Signal(void);

// 처리 버퍼에 유효한 신호가 있는지. 결과의 status 필드에 쓴다.
int FRAME_SignalReady(void);

// UART 에러 콜백에서 호출
void FRAME_NotifyUartError(void);

const FrameStat *FRAME_Stats(void);

// RSP_RESULT 송신 (블로킹, 36 B). payload 는 31 B.
void FRAME_SendResult(const uint8_t *payload);

#endif // FRAME_H
