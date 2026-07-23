%% ========================================================================
%  EXTRACT_SIGNALS_20260404.m
%
%  [목적]
%    검증된 M10 복조 체인을 SNR × 반복 만큼 돌려서,
%    MCU로 보낼 "펄스 조각 신호" + "정답" + "MATLAB 기준결과"를 파일로 저장.
%
%    이 스크립트에는 복조 알고리즘(F03/F09 등)이 직접 들어있지 않다.
%    M10_EXTRACT(검증된 원본의 쌍둥이)를 호출해서 결과만 꺼내 쓴다.
%
%  [출력 파일] (out_dir 폴더에 저장)
%    signal_SNR{snr}.bin      : int16 신호 조각. (모든 iter, 모든 펄스 연속 저장)
%    dataset_SNR{snr}.mat     : 정답 + MATLAB결과 + 메타정보 (채점/디버깅용)
%
%  [한 조각의 구조]
%    각 데이터 펄스(3~8번, 총 6개)마다 WIN_LEN(1050) 샘플을 잘라 저장.
%    조각의 0번 샘플 = 원신호의 (nominal - WIN_GUARD) 위치.
%    → MCU는 조각 안에서만 좌표를 쓰면 되므로, 원신호 좌표를 몰라도 된다.
%
%  [슬라이스 좌표계]
%    원본 F03 : nominal 위치에서 [nominal-10, nominal, nominal+10] 상관
%    슬라이스 : 조각 시작이 (nominal - WIN_GUARD) 이므로,
%               조각 안에서 nominal 은 인덱스 WIN_GUARD(=20, 1-based)에 온다.
%               후보는 [WIN_GUARD-10, WIN_GUARD, WIN_GUARD+10] = [10,20,30].
%  ========================================================================

clear; clc;

%% 설정
SNR_LIST = [-12, -8, -4, 0, 4];   % 뽑을 SNR 목록
N_ITER   = 30;                    % SNR당 반복 횟수
out_dir  = 'mcu_dataset';         % 출력 폴더

% 슬라이싱 파라미터 (앞서 합의한 값)
WIN_GUARD = 20;      % 조각에서 nominal 앞쪽 여유 (샘플). PPM ±10 + 약간
WIN_LEN   = 3050;    % 조각 길이 (샘플) = 100us 템플릿 + 좌우 여유
TPL_USE   = 3000;    % 상관에 실제로 쓸 템플릿 길이 (P10_PULSE 앞부분)
SHIFT     = 10;      % PPM 1us = 10 샘플 (fs=10MHz)

% int16 스케일: 포락선(실수)을 정수로 옮길 때 곱하는 값.
% 신호 최대치를 int16 범위(32767) 근처로 올려 정밀도를 확보.
% 실제 스케일은 아래에서 데이터 최대값 기준으로 자동 결정한다.
INT16_MAX = 32767;

rng(993);   % ★재현성: F10에서 쓰던 시드와 동일하게 고정
            %   (같은 시드 → 같은 신호 → 언제 돌려도 동일 데이터셋)

if ~exist(out_dir, 'dir'); mkdir(out_dir); end

%% 템플릿 준비 (검증용)
% P10_PULSE 로 펄스 템플릿을 만들고, 상관에 쓸 앞 TPL_USE 샘플만 취함.
% (F03 내부와 동일한 방식: abs 포락선 사용)
ppm_cfg  = F01_PPMCFG_20260116();
tpl_full = abs(real(P10_PULSE_20251223(ppm_cfg.fs)));
tpl_full = tpl_full(:);
tpl_use  = tpl_full(1:TPL_USE);          % [TPL_USE x 1]

DATA_IDX = ppm_cfg.data_pulse_idx;       % = 3:8
N_DATA   = numel(DATA_IDX);              % = 6

fprintf('=== 신호 추출 시작 ===\n');
fprintf('SNR: %s | iter=%d | WIN_LEN=%d | TPL_USE=%d\n\n', ...
        mat2str(SNR_LIST), N_ITER, WIN_LEN, TPL_USE);

%% SNR 루프
for si = 1:numel(SNR_LIST)
    snr = SNR_LIST(si);

    % 이 SNR의 모든 조각을 담을 버퍼 (int16)
    % 크기: [WIN_LEN, N_DATA, N_ITER]  →  나중에 파일로 flatten
    sig_i16 = zeros(WIN_LEN, N_DATA, N_ITER, 'int16');

    % 정답/기준결과 버퍼
    tx_pulses_all  = zeros(N_ITER, N_DATA);   % 정답 펄스 (-1/0/+1)
    tx_bits_all    = zeros(N_ITER, 7);        % 정답 비트
    est_pulses_ml  = zeros(N_ITER, N_DATA);   % MATLAB F03 추정 펄스
    est_bits_ml    = zeros(N_ITER, 7);        % MATLAB F03 추정 비트
    state_ml       = zeros(N_ITER, 1);        % MATLAB F03 state
    est_pulses_sl  = zeros(N_ITER, N_DATA);   % 슬라이스 재상관 결과 (검증용)
    nominal_all    = zeros(N_ITER, N_DATA);   % 각 펄스 nominal (원신호 좌표, 참고용)
    scale_all      = zeros(N_ITER, 1);        % iter별 int16 스케일

    n_slice_mismatch = 0;   % 슬라이스 vs MATLAB 불일치 카운트

    for it = 1:N_ITER
        % (1) M10 실행: 신호/위치/정답/MATLAB결과 획득
        [tx_bits, est_bits, tx_pulses, est_pulses, ~, state, x_lp, fa] = ...
            M10_EXTRACT_20260404(snr);

        y_env   = abs(x_lp(:)).';            % 포락선 (실수, 행벡터)
        nom_pos = fa.master_pulse_idx;       % 10개 펄스 nominal (원신호 좌표)

        % (2) int16 스케일 결정 (이 iter의 조각 최대값 기준)
        % 먼저 이 iter에서 잘라낼 구간들의 최대값을 구해 스케일 산정
        seg_max = 0;
        for k = 1:N_DATA
            p = DATA_IDX(k);
            s0 = nom_pos(p) - WIN_GUARD + 1;         % 조각 시작 (1-based)
            s1 = s0 + WIN_LEN - 1;
            if s0 >= 1 && s1 <= numel(y_env)
                seg_max = max(seg_max, max(y_env(s0:s1)));
            end
        end
        if seg_max <= 0; seg_max = 1; end
        scale = INT16_MAX / seg_max;         % 실수→int16 변환계수
        scale_all(it) = scale;

        % (3) 6개 펄스 조각 잘라서 int16로 저장 + 슬라이스 재상관
        for k = 1:N_DATA
            p       = DATA_IDX(k);
            nominal = nom_pos(p);
            s0 = nominal - WIN_GUARD + 1;    % 조각 시작 (1-based)
            s1 = s0 + WIN_LEN - 1;

            if s0 >= 1 && s1 <= numel(y_env)
                seg = y_env(s0:s1);          % [1 x WIN_LEN] 실수 포락선
            else
                seg = zeros(1, WIN_LEN);     % 범위 벗어나면 0으로 (드묾)
            end

            % int16 변환하여 버퍼에 저장
            sig_i16(:, k, it) = int16(round(seg * scale));
            nominal_all(it,k) = nominal;

            % 슬라이스 재상관 (검증용)
            % 조각 안에서 후보 위치 [10,20,30]에 대해 상관 → argmax
            NOM_C  = WIN_GUARD;                       % 조각 내 nominal (1-based=20)
            cand_c = [NOM_C-SHIFT, NOM_C, NOM_C+SHIFT];
            cval   = zeros(1,3);
            for c = 1:3
                s = cand_c(c);
                if s >= 1 && (s + TPL_USE - 1) <= WIN_LEN
                    cval(c) = seg(s:s+TPL_USE-1) * tpl_use;
                end
            end
            [~, sel] = max(cval);
            est_pulses_sl(it,k) = sel - 2;   % 1→-1, 2→0, 3→+1
        end

        % (4) 정답/기준결과 누적
        tx_pulses_all(it,:) = tx_pulses(:).';
        tx_bits_all(it,:)   = tx_bits(:).';
        est_pulses_ml(it,:) = est_pulses(:).';
        est_bits_ml(it,:)   = est_bits(:).';
        state_ml(it)        = state;

        % (5) 슬라이스 결과가 MATLAB(F03 1차)와 같은지 체크
        % 주의: F03의 최종 est_pulses는 CDC/fallback 보정이 섞여 있을 수 있어
        %       1차 상관(hard)과 다를 수 있다. 여기서는 "슬라이스 상관"이
        %       "전체 상관"과 같은 판정을 주는지를 본다. (좌표계 검증 목적)
        if ~isequal(est_pulses_sl(it,:), est_pulses_ml(it,:))
            n_slice_mismatch = n_slice_mismatch + 1;
        end
    end

    %% 파일 저장
    % (a) 신호: int16 바이너리. 저장 순서 = [WIN_LEN, N_DATA, N_ITER] 열-우선(MATLAB 기본)
    %     → MCU에서는 iter → pulse → sample 순으로 읽으면 됨(아래 dataset에 순서 명시).
    bin_path = fullfile(out_dir, sprintf('signal_SNR%+03d.bin', snr));
    fid = fopen(bin_path, 'wb');
    fwrite(fid, sig_i16(:), 'int16');   % 열-우선 flatten
    fclose(fid);

    % (b) 데이터셋(.mat): 정답 + MATLAB결과 + 메타 + 스케일
    ds = struct();
    ds.snr            = snr;
    ds.n_iter         = N_ITER;
    ds.n_data         = N_DATA;         % 6
    ds.data_idx       = DATA_IDX;       % 3:8
    ds.win_len        = WIN_LEN;
    ds.win_guard      = WIN_GUARD;
    ds.tpl_use        = TPL_USE;
    ds.shift          = SHIFT;
    ds.nom_in_slice   = WIN_GUARD;      % 조각 내 nominal 위치(1-based)
    ds.int16_scale    = scale_all;      % iter별 스케일 (복원 시 나눗셈에 사용)
    ds.bin_layout     = 'int16, column-major of [WIN_LEN x N_DATA x N_ITER]';
    ds.tx_pulses      = tx_pulses_all;  % 정답
    ds.tx_bits        = tx_bits_all;
    ds.est_pulses_ml  = est_pulses_ml;  % MATLAB F03 결과 (기준선)
    ds.est_bits_ml    = est_bits_ml;
    ds.state_ml       = state_ml;
    ds.est_pulses_sl  = est_pulses_sl;  % 슬라이스 재상관 결과 (검증)
    ds.nominal        = nominal_all;    % 원신호 좌표(참고용)
    ds.tpl_use_vec    = tpl_use;        % 검증에 쓴 템플릿(참고용)

    mat_path = fullfile(out_dir, sprintf('dataset_SNR%+03d.mat', snr));
    save(mat_path, 'ds');

    %  출력
    % 슬라이스가 정답을 맞히는 비율 (1차 상관 기준)
    pulse_acc_sl = mean(est_pulses_sl(:) == tx_pulses_all(:)) * 100;
    pulse_acc_ml = mean(est_pulses_ml(:) == tx_pulses_all(:)) * 100;

    fprintf('SNR %+3d dB | 슬라이스 재상관 vs MATLAB 불일치: %d/%d\n', ...
            snr, n_slice_mismatch, N_ITER);
    fprintf('           | 펄스 정확도  슬라이스=%.1f%%  MATLAB(F03최종)=%.1f%%\n', ...
            pulse_acc_sl, pulse_acc_ml);
    fprintf('           | 저장: %s , %s\n\n', bin_path, mat_path);
end

fprintf('=== 완료. "%s" 폴더 확인 ===\n', out_dir);
