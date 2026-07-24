%% ========================================================================
%  EXTRACT_SIGNALS_D_20260724.m
%
%  EXTRACT_SIGNALS_20260404 의 데시메이션 적용판.
%  SWEEP_DECIM 으로 확정한 배수 D 를 적용해 MCU/FPGA 로 보낼 신호를 뽑는다.
%
%  [원본 대비 달라진 점]
%    1. 조각을 D 배 데시메이션하여 저장 (통신량 1/D)
%    2. 안티에일리어싱 LPF(영위상 filtfilt) 후 서브샘플
%    3. 템플릿도 동일 배수/위상으로 데시메이션하여 함께 저장
%    4. MCU 플래시에 넣을 템플릿 C 헤더를 자동 생성
%
%  [좌표계] MCU 구현 시 이 부분을 그대로 따를 것
%    full-rate 0-based 후보 = [9, 19, 29]
%    시작 위상 r = mod(9, D)
%    데시메이션 후 1-based 후보 = (CAND0 - r)/D + 1
%      D=1  -> [10, 20, 30]      (원본과 동일)
%      D=2  -> [ 5, 10, 15]
%      D=5  -> [ 2,  4,  6]
%      D=10 -> [ 1,  2,  3]
%
%  [출력]
%    signal_SNR{snr}_D{D}.bin   : int16, column-major [SEG_D x 6 x N_ITER]
%    dataset_SNR{snr}_D{D}.mat  : 정답 + MATLAB결과 + 메타 + 데시메이션 정보
%    tpl_D{D}.h                 : MCU용 템플릿 상수 배열 헤더
%  ========================================================================

clear; clc;

%% ---------------- 사용자 설정 ----------------
DECIM    = 10;                    % SWEEP_DECIM 결과로 확정한 값
SNR_LIST = [-12, -8, -4, 0, 4];
N_ITER   = 30;
out_dir  = 'mcu_dataset';

WIN_GUARD = 20;      % 조각 내 nominal (1-based) -> full-rate 기준
WIN_LEN   = 3050;    % 조각 길이 (샘플)           -> full-rate 기준
TPL_USE   = 3000;    % 템플릿 길이 (샘플)         -> full-rate 기준
SHIFT     = 10;      % PPM 1us = 10 샘플

USE_LPF   = false;    % 안티에일리어싱 LPF 사용 (SWEEP 결과에 맞출 것)
LPF_ORDER = 64;

INT16_MAX = 32767;
MAKE_C_HEADER = true;

rng(993);            % 재현성: 원본과 동일 시드 → 동일 신호

if ~exist(out_dir, 'dir'); mkdir(out_dir); end

%% ---------------- 데시메이션 좌표 계산 ----------------
if mod(SHIFT, DECIM) ~= 0
    error('DECIM=%d 는 SHIFT=%d 의 약수가 아님. 후보가 격자를 벗어난다.', ...
          DECIM, SHIFT);
end

CAND0  = [WIN_GUARD-SHIFT, WIN_GUARD, WIN_GUARD+SHIFT] - 1;  % 0-based [9 19 29]
r      = mod(CAND0(1), DECIM);              % 시작 위상 (0-based)
cand_d = (CAND0 - r) / DECIM + 1;           % 데시메이션 후 1-based 후보
idx_keep = (r : DECIM : WIN_LEN-1) + 1;     % 조각 내 유지 인덱스 (1-based)
SEG_D    = numel(idx_keep);                 % 데시메이션 후 조각 길이

%% ---------------- 템플릿 준비 ----------------
ppm_cfg  = F01_PPMCFG_20260116();
tpl_full = abs(real(P10_PULSE_20251223(ppm_cfg.fs)));
tpl_full = tpl_full(:);
tpl_use  = tpl_full(1:TPL_USE);

if USE_LPF && DECIM > 1
    h_lpf = fir1(LPF_ORDER, 1/DECIM);
    tpl_d = filtfilt(h_lpf, 1, tpl_use);
    tpl_d = tpl_d(1:DECIM:end);
else
    h_lpf = [];
    tpl_d = tpl_use(1:DECIM:end);
end
tpl_d  = tpl_d(:);
TPL_D  = numel(tpl_d);

% 조각 길이 충분성 확인
need = cand_d(3) + TPL_D - 1;
if need > SEG_D
    error('조각 부족: 필요 %d > 보유 %d (WIN_LEN 을 늘릴 것)', need, SEG_D);
end

DATA_IDX = ppm_cfg.data_pulse_idx;      % 3:8
N_DATA   = numel(DATA_IDX);             % 6

fprintf('=== 신호 추출 (D=%d) ===\n', DECIM);
fprintf('조각 %d -> %d 샘플 | 템플릿 %d -> %d 탭\n', ...
        WIN_LEN, SEG_D, TPL_USE, TPL_D);
fprintf('후보 위치(1-based): [%d %d %d] | 시작 위상 r=%d | LPF=%d\n', ...
        cand_d(1), cand_d(2), cand_d(3), r, USE_LPF);
fprintf('iteration 당 %d B (D=1 대비 %.1f%%)\n\n', ...
        SEG_D*N_DATA*2, SEG_D/WIN_LEN*100);

%% ---------------- SNR 루프 ----------------
for si = 1:numel(SNR_LIST)

    snr = SNR_LIST(si);

    sig_i16       = zeros(SEG_D, N_DATA, N_ITER, 'int16');
    tx_pulses_all = zeros(N_ITER, N_DATA);
    tx_bits_all   = zeros(N_ITER, 7);
    est_pulses_ml = zeros(N_ITER, N_DATA);
    est_bits_ml   = zeros(N_ITER, 7);
    state_ml      = zeros(N_ITER, 1);
    est_pulses_sl = zeros(N_ITER, N_DATA);   % 데시메이션+양자화 후 재상관
    nominal_all   = zeros(N_ITER, N_DATA);
    scale_all     = zeros(N_ITER, 1);

    n_mismatch = 0;

    for it = 1:N_ITER

        % ---- (1) M10 실행 ----
        [tx_bits, est_bits, tx_pulses, est_pulses, ~, state, x_lp, fa] = ...
            M10_EXTRACT_20260404(snr);

        y_env   = abs(x_lp(:)).';
        nom_pos = fa.master_pulse_idx;

        % ---- (2) 안티에일리어싱: 전체 신호에 1회 적용 ----
        %      (조각별로 필터링하면 경계 과도응답이 생기므로 통짜로 처리)
        if isempty(h_lpf)
            y_flt = y_env;
        else
            y_flt = filtfilt(h_lpf, 1, y_env);
        end

        % ---- (3) 스케일 결정 (데시메이션 후 값 기준) ----
        seg_max = 0;
        for k = 1:N_DATA
            p  = DATA_IDX(k);
            s0 = nom_pos(p) - WIN_GUARD + 1;
            s1 = s0 + WIN_LEN - 1;
            if s0 >= 1 && s1 <= numel(y_flt)
                seg_f = y_flt(s0:s1);
                seg_max = max(seg_max, max(seg_f(idx_keep)));
            end
        end
        if seg_max <= 0; seg_max = 1; end
        scale = INT16_MAX / seg_max;
        scale_all(it) = scale;

        % ---- (4) 조각 추출 + 데시메이션 + int16 변환 ----
        for k = 1:N_DATA

            p       = DATA_IDX(k);
            nominal = nom_pos(p);
            s0 = nominal - WIN_GUARD + 1;
            s1 = s0 + WIN_LEN - 1;

            if s0 >= 1 && s1 <= numel(y_flt)
                seg_f = y_flt(s0:s1);
                seg_d = seg_f(idx_keep);
            else
                seg_d = zeros(1, SEG_D);
            end

            sig_i16(:, k, it) = int16(round(seg_d * scale));
            nominal_all(it,k) = nominal;

            % ---- (5) 재상관 검증: MCU가 실제로 받을 int16 값으로 수행 ----
            segq = double(sig_i16(:, k, it));
            cval = zeros(1, 3);
            for c = 1:3
                s = cand_d(c);
                cval(c) = segq(s : s+TPL_D-1).' * tpl_d;
            end
            [~, sel] = max(cval);
            est_pulses_sl(it,k) = sel - 2;
        end

        tx_pulses_all(it,:) = tx_pulses(:).';
        tx_bits_all(it,:)   = tx_bits(:).';
        est_pulses_ml(it,:) = est_pulses(:).';
        est_bits_ml(it,:)   = est_bits(:).';
        state_ml(it)        = state;

        if ~isequal(est_pulses_sl(it,:), est_pulses_ml(it,:))
            n_mismatch = n_mismatch + 1;
        end
    end

    % ---------------- 저장 ----------------
    bin_path = fullfile(out_dir, sprintf('signal_SNR%+03d_D%02d.bin', snr, DECIM));
    fid = fopen(bin_path, 'wb');
    fwrite(fid, sig_i16(:), 'int16');
    fclose(fid);

    ds = struct();
    ds.snr           = snr;
    ds.n_iter        = N_ITER;
    ds.n_data        = N_DATA;
    ds.data_idx      = DATA_IDX;

    % --- 데시메이션 정보 (MCU 구현이 참조할 값) ---
    ds.decim         = DECIM;
    ds.decim_phase   = r;              % full-rate 0-based 시작 위상
    ds.seg_len       = SEG_D;          % 데시메이션 후 조각 길이
    ds.tpl_len       = TPL_D;          % 데시메이션 후 템플릿 탭 수
    ds.cand_idx      = cand_d;         % 1-based 후보 (MCU는 -1 해서 0-based로)
    ds.use_lpf       = USE_LPF;
    ds.lpf_order     = LPF_ORDER;

    % --- full-rate 원본 파라미터 (참고) ---
    ds.win_len_full  = WIN_LEN;
    ds.win_guard     = WIN_GUARD;
    ds.tpl_use_full  = TPL_USE;
    ds.shift_full    = SHIFT;

    ds.int16_scale   = scale_all;
    ds.bin_layout    = sprintf('int16, column-major of [%d x %d x %d]', ...
                               SEG_D, N_DATA, N_ITER);
    ds.tx_pulses     = tx_pulses_all;
    ds.tx_bits       = tx_bits_all;
    ds.est_pulses_ml = est_pulses_ml;
    ds.est_bits_ml   = est_bits_ml;
    ds.state_ml      = state_ml;
    ds.est_pulses_sl = est_pulses_sl;
    ds.nominal       = nominal_all;
    ds.tpl_d         = tpl_d;          % 데시메이션된 템플릿 (double)

    mat_path = fullfile(out_dir, sprintf('dataset_SNR%+03d_D%02d.mat', snr, DECIM));
    save(mat_path, 'ds');

    acc_sl = mean(est_pulses_sl(:) == tx_pulses_all(:)) * 100;
    acc_ml = mean(est_pulses_ml(:) == tx_pulses_all(:)) * 100;

    fprintf('SNR %+3d dB | 재상관 vs MATLAB 불일치: %d/%d\n', ...
            snr, n_mismatch, N_ITER);
    fprintf('           | 펄스 정확도  D=%d+int16=%.1f%%  MATLAB=%.1f%%\n', ...
            DECIM, acc_sl, acc_ml);
    fprintf('           | 저장: %s\n\n', bin_path);
end

%% ---------------- MCU용 템플릿 C 헤더 생성 ----------------
if MAKE_C_HEADER

    % 템플릿도 int16 로 양자화 (MCU에서 int16 x int16 -> int32 MAC)
    tpl_scale = INT16_MAX / max(abs(tpl_d));
    tpl_i16   = int16(round(tpl_d * tpl_scale));

    hdr_path = fullfile(out_dir, sprintf('tpl_D%02d.h', DECIM));
    fid = fopen(hdr_path, 'w');

    fprintf(fid, '/* Auto-generated by EXTRACT_SIGNALS_D_20260724.m */\n');
    fprintf(fid, '/* eLoran PPM demodulation: decimated pulse template   */\n\n');
    fprintf(fid, '#ifndef TPL_D%02d_H\n#define TPL_D%02d_H\n\n', DECIM, DECIM);
    fprintf(fid, '#include <stdint.h>\n\n');
    fprintf(fid, '#define DECIM        %d\n',   DECIM);
    fprintf(fid, '#define SEG_LEN      %d   /* samples per pulse slice */\n', SEG_D);
    fprintf(fid, '#define N_PULSE      %d\n',   N_DATA);
    fprintf(fid, '#define TPL_LEN      %d   /* correlation taps */\n', TPL_D);
    fprintf(fid, '#define N_CAND       3\n\n');
    fprintf(fid, '/* candidate start offsets, 0-based */\n');
    fprintf(fid, 'static const uint16_t CAND[N_CAND] = {%d, %d, %d};\n\n', ...
            cand_d(1)-1, cand_d(2)-1, cand_d(3)-1);
    fprintf(fid, '/* template scaled to int16 (scale = %.6e) */\n', tpl_scale);
    fprintf(fid, 'static const int16_t TPL[TPL_LEN] = {\n');
    for i = 1:TPL_D
        if mod(i-1, 10) == 0; fprintf(fid, '    '); end
        fprintf(fid, '%6d', tpl_i16(i));
        if i < TPL_D; fprintf(fid, ','); end
        if mod(i, 10) == 0 || i == TPL_D; fprintf(fid, '\n'); end
    end
    fprintf(fid, '};\n\n#endif\n');
    fclose(fid);

    fprintf('템플릿 헤더 생성: %s  (%d 탭, %d B 플래시)\n', ...
            hdr_path, TPL_D, TPL_D*2);
end

fprintf('\n=== 완료 ===\n');
