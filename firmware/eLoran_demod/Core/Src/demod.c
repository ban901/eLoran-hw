/* demod.c ─ 위치: Core/Src/demod.c */

#include "demod.h"

/* ══════════════════════════════════════════════════════════════════
 *  CDC 임계값 (논문 식 (3) 의 epsilon)
 *
 *  논문값 0.001 은 상관값이 21.4 수준인 실수 도메인 기준이다.
 *  정수 도메인으로 환산하면 다음 세 배율이 곱해진다.
 *
 *      신호 int16 스케일        x 32,900
 *      템플릿 int16 스케일      x 1.277229e6
 *      데시메이션 (3000->300)   x 1/10
 *      ------------------------------------
 *      합계                     x 4.202e9
 *
 *      0.001 x 4.202e9 = 4.2e6
 *
 *  SNR -8 dB 데이터셋 실측에서도 이 값이 최적점이었다.
 * ══════════════════════════════════════════════════════════════════ */
#define CDC_EPSILON   4200000LL

/* ── Eurofix 변조 패턴 표 (F07_PULMAP, 128 x 6) ────────────────────
 *  ITU-R Report TF.2487-0, Table 17.
 *  행 번호가 곧 7비트 데이터 심볼 값이다 (0번 행 = 0000000). */
static const int8_t PULSE_TABLE[128][N_PULSE] = {
    {-1,-1, 0, 0, 1, 1}, {-1,-1, 0, 1, 0, 1}, {-1,-1, 0, 1, 1, 0},
    {-1,-1, 1, 0, 0, 1}, {-1,-1, 1, 0, 1, 0}, {-1,-1, 1, 1, 0, 0},
    {-1, 0,-1, 0, 1, 1}, {-1, 0,-1, 1, 0, 1}, {-1, 0,-1, 1, 1, 0},
    {-1, 0, 0,-1, 1, 1}, {-1, 0, 0, 1,-1, 1}, {-1, 0, 0, 1, 1,-1},
    {-1, 0, 1,-1, 0, 1}, {-1, 0, 1,-1, 1, 0}, {-1, 0, 1, 0,-1, 1},
    {-1, 0, 1, 0, 1,-1}, {-1, 0, 1, 1,-1, 0}, {-1, 0, 1, 1, 0,-1},
    {-1, 1,-1, 0, 0, 1}, {-1, 1,-1, 0, 1, 0}, {-1, 1,-1, 1, 0, 0},
    {-1, 1, 0,-1, 0, 1}, {-1, 1, 0,-1, 1, 0}, {-1, 1, 0, 0,-1, 1},
    {-1, 1, 0, 0, 1,-1}, {-1, 1, 0, 1,-1, 0}, {-1, 1, 0, 1, 0,-1},
    {-1, 1, 1,-1, 0, 0}, {-1, 1, 1, 0,-1, 0}, {-1, 1, 1, 0, 0,-1},
    { 0,-1,-1, 0, 1, 1}, { 0,-1,-1, 1, 0, 1}, { 0,-1,-1, 1, 1, 0},
    { 0,-1, 0,-1, 1, 1}, { 0,-1, 0, 1,-1, 1}, { 0,-1, 0, 1, 1,-1},
    { 0,-1, 1,-1, 0, 1}, { 0,-1, 1,-1, 1, 0}, { 0,-1, 1, 0,-1, 1},
    { 0,-1, 1, 0, 1,-1}, { 0,-1, 1, 1,-1, 0}, { 0,-1, 1, 1, 0,-1},
    { 0, 0,-1,-1, 1, 1}, { 0, 0,-1, 1,-1, 1}, { 0, 0,-1, 1, 1,-1},
    { 0, 0, 1,-1,-1, 1}, { 0, 0, 1,-1, 1,-1}, { 0, 0, 1, 1,-1,-1},
    { 0, 1,-1,-1, 0, 1}, { 0, 1,-1,-1, 1, 0}, { 0, 1,-1, 0,-1, 1},
    { 0, 1,-1, 0, 1,-1}, { 0, 1,-1, 1,-1, 0}, { 0, 1,-1, 1, 0,-1},
    { 0, 1, 0,-1,-1, 1}, { 0, 1, 0,-1, 1,-1}, { 0, 1, 0, 1,-1,-1},
    { 0, 1, 1,-1,-1, 0}, { 0, 1, 1,-1, 0,-1}, { 0, 1, 1, 0,-1,-1},
    { 1,-1,-1, 0, 0, 1}, { 1,-1,-1, 0, 1, 0}, { 1,-1,-1, 1, 0, 0},
    { 1,-1, 0,-1, 0, 1}, { 1,-1, 0,-1, 1, 0}, { 1,-1, 0, 0,-1, 1},
    { 1,-1, 0, 0, 1,-1}, { 1,-1, 0, 1,-1, 0}, { 1,-1, 0, 1, 0,-1},
    { 1,-1, 1,-1, 0, 0}, { 1,-1, 1, 0,-1, 0}, { 1,-1, 1, 0, 0,-1},
    { 1, 0,-1,-1, 0, 1}, { 1, 0,-1,-1, 1, 0}, { 1, 0,-1, 0,-1, 1},
    { 1, 0,-1, 0, 1,-1}, { 1, 0,-1, 1,-1, 0}, { 1, 0,-1, 1, 0,-1},
    { 1, 0, 0,-1,-1, 1}, { 1, 0, 0,-1, 1,-1}, { 1, 0, 0, 1,-1,-1},
    { 1, 0, 1,-1,-1, 0}, { 1, 0, 1,-1, 0,-1}, { 1, 0, 1, 0,-1,-1},
    { 1, 1,-1,-1, 0, 0}, { 1, 1,-1, 0,-1, 0}, { 1, 1,-1, 0, 0,-1},
    { 1, 1, 0,-1,-1, 0}, { 1, 1, 0,-1, 0,-1}, { 1, 1, 0, 0,-1,-1},
    {-1, 0, 0, 0, 0, 1}, {-1, 0, 0, 0, 1, 0}, {-1, 0, 0, 1, 0, 0},
    {-1, 0, 1, 0, 0, 0}, {-1, 1, 0, 0, 0, 0}, { 0,-1, 0, 0, 0, 1},
    { 0,-1, 0, 0, 1, 0}, { 0,-1, 0, 1, 0, 0}, { 0,-1, 1, 0, 0, 0},
    { 0, 0,-1, 0, 0, 1}, { 0, 0,-1, 0, 1, 0}, { 0, 0,-1, 1, 0, 0},
    { 0, 0, 0,-1, 0, 1}, { 0, 0, 0,-1, 1, 0}, { 0, 0, 0, 0,-1, 1},
    { 0, 0, 0, 0, 1,-1}, { 0, 0, 0, 1,-1, 0}, { 0, 0, 0, 1, 0,-1},
    { 0, 0, 1,-1, 0, 0}, { 0, 0, 1, 0,-1, 0}, { 0, 0, 1, 0, 0,-1},
    { 0, 1,-1, 0, 0, 0}, { 0, 1, 0,-1, 0, 0}, { 0, 1, 0, 0,-1, 0},
    { 0, 1, 0, 0, 0,-1}, { 1,-1, 0, 0, 0, 0}, { 1, 0,-1, 0, 0, 0},
    { 1, 0, 0,-1, 0, 0}, { 1, 0, 0, 0,-1, 0}, { 1,-1, 1,-1, 1,-1},
    {-1, 1,-1, 1,-1, 1}, { 1,-1, 1,-1,-1, 1}, {-1, 1,-1, 1, 1,-1},
    { 1,-1,-1, 1,-1, 1}, {-1, 1, 1,-1, 1,-1}, { 1,-1,-1, 1, 1,-1},
    {-1, 1, 1,-1,-1, 1}, { 1, 0, 0, 0, 0,-1}
};

/* 3진수 키 -> 표 행번호+1 (0 이면 해당 패턴 없음). F09_PULIDX 와 동일. */
static uint8_t PULSE_MAP[729];

/* ── 패턴 <-> 인덱스 ─────────────────────────────────────────────── */

/* (-1,0,+1) -> (0,1,2) 로 옮겨 3진수 인코딩. 0 ~ 728 */
static int pattern_key(const int8_t *p)
{
    static const int W[N_PULSE] = {243, 81, 27, 9, 3, 1};
    int key = 0;

    for (int i = 0; i < N_PULSE; i++)
        key += (p[i] + 1) * W[i];

    return key;
}

/* 표에 있으면 0~127, 없으면 -1 */
static int pattern_lookup(const int8_t *p)
{
    int key = pattern_key(p);

    if (PULSE_MAP[key] == 0) return -1;
    return PULSE_MAP[key] - 1;
}

/* 표 행번호를 그대로 7비트로 펼친다 (MSB first).
 *
 *  F06_BITMAP 은 0~127 을 이진수로 정렬한 표이므로 (F08_BITIDX 참고)
 *  128x7 배열을 따로 두지 않고 비트 시프트로 대신할 수 있다. */
static void index_to_bits(int idx, uint8_t *bits)
{
    for (int j = 0; j < N_BITS; j++)
        bits[j] = (uint8_t)((idx >> (N_BITS - 1 - j)) & 1);
}

/* ══════════════════════════════════════════════════════════════════ */

void DEMOD_Init(void)
{
    for (int k = 0; k < 729; k++)
        PULSE_MAP[k] = 0;

    for (int i = 0; i < 128; i++)
        PULSE_MAP[pattern_key(PULSE_TABLE[i])] = (uint8_t)(i + 1);
}

/* ── Step 1 : 후보별 최대 상관값 선택 (논문 식 (2)) ───────────────── */
static void step1_argmax(const int64_t corr[N_PULSE][N_CAND],
                         int8_t sel_idx[N_PULSE],
                         int8_t est_pulses[N_PULSE])
{
    for (int k = 0; k < N_PULSE; k++) {

        int best = 0;
        for (int c = 1; c < N_CAND; c++)
            if (corr[k][c] > corr[k][best]) best = c;

        sel_idx[k]    = (int8_t)best;        /* 0/1/2 */
        est_pulses[k] = (int8_t)(best - 1);  /* -1/0/+1 */
    }
}

/* ── Step 2 : CDC (논문 식 (3)) ────────────────────────────────────
 *
 *  선택된 후보와 나머지 후보의 상관값 차이가 epsilon 이하이면 대체 후보로
 *  본다. 차이가 작은 것부터 하나씩 바꿔가며 표에 있는 패턴을 찾는다.
 *
 *  대체 후보는 최대 6펄스 x 2후보 = 12개.
 *
 *  MATLAB F03 은 2~3개 펄스를 동시에 바꾸는 조합까지 탐색하지만,
 *  여기서는 단일 펄스 교체까지만 수행한다. SNR -8 dB 에서 최종 심볼
 *  정확도는 MATLAB 과 동일한 19/30 이었다.
 */
typedef struct {
    int64_t diff;    /* 선택 후보와의 상관값 차이 */
    int8_t  pulse;   /* 몇 번째 펄스인지 0~5 */
    int8_t  value;   /* 바꿔 넣을 값 -1/0/+1 */
} CdcCand;

static int step2_cdc(const int64_t corr[N_PULSE][N_CAND],
                     const int8_t sel_idx[N_PULSE],
                     const int8_t est_pulses[N_PULSE],
                     DemodResult *out)
{
    CdcCand cand[N_PULSE * 2];
    int n_cand = 0;

    /* (1) 임계값을 넘지 않는 대체 후보 수집 */
    for (int k = 0; k < N_PULSE; k++) {
        for (int c = 0; c < N_CAND; c++) {

            if (c == sel_idx[k]) continue;

            int64_t diff = corr[k][sel_idx[k]] - corr[k][c];
            if (diff > CDC_EPSILON) continue;

            cand[n_cand].diff  = diff;
            cand[n_cand].pulse = (int8_t)k;
            cand[n_cand].value = (int8_t)(c - 1);
            n_cand++;
        }
    }

    /* (2) 차이가 작은 순으로 정렬 (삽입 정렬, 최대 12개) */
    for (int i = 1; i < n_cand; i++) {
        CdcCand key = cand[i];
        int j = i - 1;
        while (j >= 0 && cand[j].diff > key.diff) {
            cand[j + 1] = cand[j];
            j--;
        }
        cand[j + 1] = key;
    }

    /* (3) 하나씩 교체해보고 표에 있으면 즉시 확정 */
    for (int i = 0; i < n_cand; i++) {

        int8_t test[N_PULSE];
        for (int k = 0; k < N_PULSE; k++) test[k] = est_pulses[k];
        test[cand[i].pulse] = cand[i].value;

        int idx = pattern_lookup(test);
        if (idx < 0) continue;

        for (int k = 0; k < N_PULSE; k++) out->rx_pulses[k] = test[k];
        index_to_bits(idx, out->bits);
        out->state = STATE_CDC;
        return 1;
    }

    return 0;
}

/* ── Step 3 : MDD (논문 식 (4)) ────────────────────────────────────
 *
 *  표의 모든 패턴과 L1 거리를 계산해 최소인 것을 강제 선택한다.
 *  동일한 최소 거리가 여러 개면 표에서 먼저 정의된 패턴을 쓴다.
 *  ( d < best 로 비교하므로 뒤쪽 패턴이 앞쪽을 밀어내지 않는다 ) */
static void step3_mdd(const int8_t est_pulses[N_PULSE], DemodResult *out)
{
    int best_idx = 0;
    int best_d   = 0x7FFFFFFF;

    for (int i = 0; i < 128; i++) {

        int d = 0;
        for (int k = 0; k < N_PULSE; k++) {
            int diff = est_pulses[k] - PULSE_TABLE[i][k];
            d += (diff < 0) ? -diff : diff;
        }

        if (d < best_d) { best_d = d; best_idx = i; }
    }

    for (int k = 0; k < N_PULSE; k++)
        out->rx_pulses[k] = PULSE_TABLE[best_idx][k];

    index_to_bits(best_idx, out->bits);
    out->state = STATE_MDD;
}

/* ══════════════════════════════════════════════════════════════════ */

void DEMOD_Run(const int64_t corr[N_PULSE][N_CAND], DemodResult *out)
{
    int8_t sel_idx[N_PULSE];

    /* Step 1 */
    step1_argmax(corr, sel_idx, out->est_pulses);

    int idx = pattern_lookup(out->est_pulses);
    if (idx >= 0) {
        for (int k = 0; k < N_PULSE; k++) out->rx_pulses[k] = out->est_pulses[k];
        index_to_bits(idx, out->bits);
        out->state = STATE_HARD;
        return;
    }

    /* Step 2 */
    if (step2_cdc(corr, sel_idx, out->est_pulses, out))
        return;

    /* Step 3 */
    step3_mdd(out->est_pulses, out);
}
