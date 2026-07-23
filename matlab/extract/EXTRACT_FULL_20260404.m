%% ========================================================================
%  EXTRACT_FULL_20260404.m   (테스트 전용)
%
%  [목적]
%    TPL_USE 를 최대 10000까지 쓸어보려면, 각 펄스 nominal 에서
%    최소 10000+ 샘플이 있어야 한다. 조각을 미리 짧게 자르면 갇히므로,
%    여기서는 "각 데이터펄스 nominal 부터 넉넉한 길이"를 통째로 저장한다.
%
%    → 이 파일은 "최적 TPL_USE 탐색용" 임시 데이터. 통신량은 신경 안 씀.
%      최적 길이를 찾은 뒤, 그 길이에 맞춰 최종 조각을 다시 뽑을 것.
%
%  [저장]
%    fulltest_SNR{snr}.mat 하나에 전부 담음:
%      seg  : [SEG_LEN x N_DATA x N_ITER] double 포락선 (원본 실수값, 스케일 안 함)
%             → 테스트 단계라 정밀도 위해 double 원값 그대로 저장
%      tx_pulses, est_pulses_ml, state_ml : 정답/기준결과
%      nom_in_seg : 조각 내 nominal 위치(1-based) = WIN_GUARD
%      tpl_full   : P10_PULSE 전체 템플릿 (abs, 10000샘플)
%  ========================================================================

clear; clc;

SNR_LIST  = [-4, 0, 4];    % 테스트는 잘 되는 SNR 위주로 (곡선만 보면 됨)
N_ITER    = 30;
out_dir   = 'mcu_dataset';

WIN_GUARD = 20;            % nominal 앞 여유 (조각 내 nominal = 20, 1-based)
SEG_LEN   = 10200;         % 조각 길이: WIN_GUARD + shift + 10000 여유 포함
                          %  → TPL_USE 최대 ~10000까지 테스트 가능
SHIFT     = 10;

rng(993);
if ~exist(out_dir,'dir'); mkdir(out_dir); end

ppm_cfg  = F01_PPMCFG_20260116();
tpl_full = abs(real(P10_PULSE_20251223(ppm_cfg.fs)));  % 10000
tpl_full = tpl_full(:);
DATA_IDX = ppm_cfg.data_pulse_idx;   % 3:8
N_DATA   = numel(DATA_IDX);

fprintf('=== FULL 추출 (TPL_USE 탐색용) ===\n');
fprintf('SEG_LEN=%d (TPL_USE 최대 ~10000 테스트 가능)\n\n', SEG_LEN);

for si = 1:numel(SNR_LIST)
    snr = SNR_LIST(si);

    seg_all       = zeros(SEG_LEN, N_DATA, N_ITER);  % double 원값
    tx_pulses_all = zeros(N_ITER, N_DATA);
    est_pulses_ml = zeros(N_ITER, N_DATA);
    state_ml      = zeros(N_ITER, 1);
    n_skip = 0;

    for it = 1:N_ITER
        [tx_bits, est_bits, tx_pulses, est_pulses, ~, state, x_lp, fa] = ...
            M10_EXTRACT_20260404(snr);

        y_env   = abs(x_lp(:)).';
        nom_pos = fa.master_pulse_idx;

        for k = 1:N_DATA
            p  = DATA_IDX(k);
            s0 = nom_pos(p) - WIN_GUARD + 1;
            s1 = s0 + SEG_LEN - 1;
            if s0 >= 1 && s1 <= numel(y_env)
                seg_all(:,k,it) = y_env(s0:s1).';
            else
                n_skip = n_skip + 1;   % 신호 끝에서 넘치면 0으로 남김
            end
        end

        tx_pulses_all(it,:) = tx_pulses(:).';
        est_pulses_ml(it,:) = est_pulses(:).';
        state_ml(it)        = state;
    end

    T = struct();
    T.snr           = snr;
    T.n_iter        = N_ITER;
    T.n_data        = N_DATA;
    T.data_idx      = DATA_IDX;
    T.seg_len       = SEG_LEN;
    T.win_guard     = WIN_GUARD;
    T.nom_in_seg    = WIN_GUARD;      % 조각 내 nominal (1-based)
    T.shift         = SHIFT;
    T.seg           = seg_all;        % double 원값 포락선
    T.tx_pulses     = tx_pulses_all;
    T.est_pulses_ml = est_pulses_ml;
    T.state_ml      = state_ml;
    T.tpl_full      = tpl_full;       % 10000 템플릿

    save(fullfile(out_dir, sprintf('fulltest_SNR%+03d.mat', snr)), 'T', '-v7.3');
    fprintf('SNR %+3d dB 저장 완료 (skip=%d)\n', snr, n_skip);
end

fprintf('\n=== 완료. 이제 SWEEP_TPL 스크립트 실행 ===\n');
