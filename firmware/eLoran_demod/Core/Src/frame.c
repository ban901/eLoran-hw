// frame.c ─ 위치: Core/Src/frame.c

#include "frame.h"
#include "main.h"
#include "usart.h"      // huart2
#include <string.h>     // memcpy

#define FRAME_TIMEOUT_MS   1000u

// ══════════════════════════════════════════════════════════════════
//  CRC-16/CCITT-FALSE
//
//    다항식 0x1021 / 초기값 0xFFFF / 최종 XOR 없음 / 비트반전 없음
//    검증: "123456789" -> 0x29B1
//
//  1바이트씩 누적하는 형태다. 프레임을 다 받은 뒤 한꺼번에 계산하지 않고
//  수신 인터럽트에서 바로 갱신한다.
//  바이트당 약 50 사이클인데 460800 bps 에서는 바이트 간격이 1,800 사이클
//  이므로 여유가 충분하다.
// ══════════════════════════════════════════════════════════════════
static uint16_t crc16_update(uint16_t crc, uint8_t byte)
{
    crc ^= (uint16_t)byte << 8;

    for (int i = 0; i < 8; i++) {
        if (crc & 0x8000u) crc = (uint16_t)((crc << 1) ^ 0x1021u);
        else               crc = (uint16_t)(crc << 1);
    }
    return crc;
}

// ── 수신 상태 ─────────────────────────────────────────────────────
typedef enum {
    S_SOF0 = 0,   // 0xA5 대기
    S_SOF1,       // 0xC3 대기
    S_TYPE,
    S_PAYLOAD,
    S_CRC_LO,
    S_CRC_HI
} RxState;

static volatile RxState    s_state;
static volatile uint8_t    s_type;
static volatile uint16_t   s_want;      // 기대 페이로드 길이
static volatile uint16_t   s_got;       // 지금까지 받은 바이트 수
static volatile uint16_t   s_crc;       // 계산 중인 CRC
static volatile uint16_t   s_crc_rx;    // 프레임에 실려온 CRC
static volatile FrameEvent s_event;
static volatile uint32_t   s_last_ms;

static volatile int s_rx_new;      // s_rx 에 새 신호가 확정됨 (복사 대기)
static volatile int s_sig_ready;   // s_work 에 유효한 신호가 있음

static FrameStat s_stat;

// ══════════════════════════════════════════════════════════════════
//  신호 버퍼 2개
//
//    s_rx   : 인터럽트가 쓴다. 수신 중인 데이터.
//    s_work : 복조가 읽는다. CRC 통과가 확정된 데이터만 들어온다.
//
//  버퍼가 하나면 복조하는 2.6 ms 동안 다음 iteration 이 도착해 같은 메모리를
//  덮어쓴다. 앞쪽 펄스는 신규, 뒤쪽 펄스는 이전 값이 되어 판정이 깨진다.
//
//  union 으로 두면 받은 바이트를 그대로 int16 로 볼 수 있다.
//  4바이트 정렬을 걸어 int16 접근이 안전하도록 한다.
// ══════════════════════════════════════════════════════════════════
typedef union {
    uint8_t u8 [PROTO_LEN_LOAD];
    int16_t i16[PROTO_LEN_LOAD / 2];
} SignalBuf;

static SignalBuf s_rx   __attribute__((aligned(4)));
static SignalBuf s_work __attribute__((aligned(4)));

// ══════════════════════════════════════════════════════════════════

void FRAME_Init(void)
{
    s_state     = S_SOF0;
    s_got       = 0;
    s_event     = FRAME_NONE;
    s_rx_new    = 0;
    s_sig_ready = 0;
    s_last_ms   = HAL_GetTick();

    s_stat.n_ok       = 0;
    s_stat.n_crc_err  = 0;
    s_stat.n_type_err = 0;
    s_stat.n_timeout  = 0;
    s_stat.n_uart_err = 0;
}

void FRAME_FeedByte(uint8_t b)
{
    s_last_ms = HAL_GetTick();

    switch (s_state) {

    case S_SOF0:
        if (b == PROTO_SOF0) s_state = S_SOF1;
        break;

    case S_SOF1:
        if      (b == PROTO_SOF1) s_state = S_TYPE;
        else if (b == PROTO_SOF0) s_state = S_SOF1;   // A5 A5 C3 대비
        else                      s_state = S_SOF0;
        break;

    case S_TYPE:
        if (b == PROTO_CMD_LOAD) {
            s_want      = PROTO_LEN_LOAD;
            // 새 LOAD 가 시작되면 기존 신호를 무효로 본다.
            // 이 프레임이 중간에 끊겨도 이전 신호로 복조되지 않게 하려는 것.
            s_sig_ready = 0;
        }
        else if (b == PROTO_CMD_DEMOD) {
            s_want = PROTO_LEN_DEMOD;
        }
        else {
            s_stat.n_type_err++;
            s_state = (b == PROTO_SOF0) ? S_SOF1 : S_SOF0;
            break;
        }
        s_type  = b;
        s_crc   = crc16_update(0xFFFFu, b);   // CRC 는 TYPE 부터
        s_got   = 0;
        s_state = (s_want == 0) ? S_CRC_LO : S_PAYLOAD;
        break;

    case S_PAYLOAD:
        s_rx.u8[s_got++] = b;
        s_crc = crc16_update(s_crc, b);
        if (s_got >= s_want) s_state = S_CRC_LO;
        break;

    case S_CRC_LO:
        s_crc_rx = b;
        s_state  = S_CRC_HI;
        break;

    case S_CRC_HI:
        s_crc_rx |= (uint16_t)b << 8;

        if (s_crc_rx == s_crc) {
            s_stat.n_ok++;
            if (s_type == PROTO_CMD_LOAD) {
                s_rx_new = 1;               // 복사는 메인 루프가 한다
                s_event  = FRAME_LOAD;
            } else {
                s_event  = FRAME_DEMOD;
            }
        } else {
            s_stat.n_crc_err++;
        }
        s_state = S_SOF0;
        break;

    default:
        s_state = S_SOF0;
        break;
    }
}

// 수신 버퍼 -> 처리 버퍼.
//
// 복사를 인터럽트가 아니라 메인 루프에서 하는 이유는, 3,660 B 복사에 약
// 15 us 가 걸려 460800 bps 의 바이트 간격 21.7 us 를 거의 다 쓰기 때문이다.
// 인터럽트가 그만큼 길어지면 오버런 위험이 생긴다.
//
// 여러 번 불러도 안전하다. 새 신호가 없으면 그냥 돌아간다.
void FRAME_CommitSignal(void)
{
    if (!s_rx_new) return;

    s_rx_new = 0;
    memcpy(s_work.u8, s_rx.u8, PROTO_LEN_LOAD);
    s_sig_ready = 1;
}

void FRAME_Tick(void)
{
    if (s_state == S_SOF0) return;              // 프레임 밖

    // now 와 last 를 읽는 사이에 인터럽트가 s_last_ms 를 갱신하면
    // 뺄셈이 음수가 되고, uint32 라 40억이 되어 무조건 타임아웃이 된다.
    // 두 값을 한 묶음으로 읽어야 한다.
    uint32_t primask = __get_PRIMASK();
    __disable_irq();
    uint32_t now  = HAL_GetTick();
    uint32_t last = s_last_ms;
    __set_PRIMASK(primask);

    if ((now - last) < FRAME_TIMEOUT_MS) return;

    s_stat.n_timeout++;
    s_state = S_SOF0;
}

FrameEvent FRAME_TakeEvent(void)
{
    uint32_t primask = __get_PRIMASK();
    __disable_irq();

    FrameEvent e = s_event;
    s_event = FRAME_NONE;

    __set_PRIMASK(primask);
    return e;
}

const int16_t   *FRAME_Signal(void)      { return s_work.i16; }
int              FRAME_SignalReady(void) { return s_sig_ready; }
const FrameStat *FRAME_Stats(void)       { return &s_stat;     }

void FRAME_NotifyUartError(void)
{
    s_stat.n_uart_err++;
    s_state = S_SOF0;
}

// ══════════════════════════════════════════════════════════════════

void FRAME_SendResult(const uint8_t *payload)
{
    uint8_t tx[PROTO_OVERHEAD + PROTO_LEN_RESULT];   // 36 B

    tx[0] = PROTO_SOF0;
    tx[1] = PROTO_SOF1;
    tx[2] = PROTO_RSP_RESULT;

    uint16_t crc = crc16_update(0xFFFFu, PROTO_RSP_RESULT);

    for (int i = 0; i < PROTO_LEN_RESULT; i++) {
        tx[3 + i] = payload[i];
        crc = crc16_update(crc, payload[i]);
    }

    tx[3 + PROTO_LEN_RESULT]     = (uint8_t)(crc & 0xFFu);
    tx[3 + PROTO_LEN_RESULT + 1] = (uint8_t)(crc >> 8);

    HAL_UART_Transmit(&huart2, tx, sizeof(tx), 100);
}
