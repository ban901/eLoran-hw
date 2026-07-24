%% ========================================================================
%  SWEEP_DECIM_20260724.m   (테스트 전용)
%
%  [목적]
%    데시메이션 배수 D 를 쓸어보며 "펄스 판정 정확도"가 유지되는
%    최대 D 를 찾는다. D 는 곧 통신량 1/D 를 의미하므로,
%    MCU↔FPGA 전송시간을 결정하는 핵심 파라미터다.
%
%  [입력]  EXTRACT_SIGNALS_20260404 이 만든 기존 산출물을 그대로 사용
%            signal_SNR{snr}.bin   : int16 [3050 x 6 x 30] column-major
%            dataset_SNR{snr}.mat  : tx_pulses / est_pulses_ml / tpl_use_vec
%          → fulltest_*.mat 재생성 불필요.
%            (조각 3050 이면 TPL 3000 스윕에 충분:
%             0-based 후보 최대 29 + 2999 = 3028 < 3050)
%
%  [왜 다운샘플링이 가능한가]
%    저장된 신호는 x_lp 의 포락선 abs(x_lp) 이다.
%    abs() 를 취한 시점에 100 kHz 반송파는 이미 제거되었고,
%    남은 것은 시정수 65 us 의 완만한 포락선뿐이다 (P10_PULSE 참조).
%    따라서 fs=10 MHz 는 심한 과샘플링이며 대역폭 관점의 여유가 크다.
%
%  [진짜 제약은 대역폭이 아니라 PPM 분해능] ★핵심★
%    후보 위치 간격 = SHIFT = 10 샘플 (= 1 us).
%    D 배 데시메이션 후에도 세 후보가 모두 격자 위에 있어야 하므로
%      D | SHIFT  →  D ∈ {1, 2, 5, 10}.  D=10 이 이론적 최대.
%
%  [위상(phase) 선택]
%    조각 0-based 후보 = [9, 19, 29].
%    stride D 로 남기는 인덱스가 r, r+D, r+2D, ... 이므로
%    세 후보를 모두 포함하려면 r = mod(9, D) 로 시작해야 한다.
%      D=2  -> r=1  : 1,3,...,9,...,19,...,29   OK
%      D=5  -> r=4  : 4,9,14,19,24,29           OK
%      D=10 -> r=9  : 9,19,29                   OK
%
%  [템플릿]
%    상관은 sum_n seg[cand+n]*tpl[n] 이고, seg 를 stride D 로 남기면
%    대응하는 tpl 인덱스는 0, D, 2D, ... 이므로
%    템플릿은 위상 0 에서 stride D 로 뽑는다: tpl(1:D:end).
%  ========================================================================

clear; 
clc;

%% ---------------- 사용자 설정 ----------------
SNR_TEST = [-12, -8, -4, 0, 4];   % 기존 bin 이 있는 SNR 전부
D_LIST   = [1, 2, 5, 10];         % 데시메이션 배수 (SHIFT=10 의 약수만 유효)
out_dir  = 'mcu_dataset';

USE_LPF   = false;                 % true : 안티에일리어싱 LPF 후 서브샘플
                                  % false: 단순 서브샘플 (비교용)
LPF_ORDER = 64;

%% ---------------- 좌표계 상수 (EXTRACT_SIGNALS 와 동일) ----------------
WIN_GUARD = 20;
WIN_LEN   = 3050;
TPL_USE   = 3000;
SHIFT     = 10;
N_DATA    = 6;
N_ITER    = 30;

CAND0 = [WIN_GUARD-SHIFT, WIN_GUARD, WIN_GUARD+SHIFT] - 1;   % 0-based [9 19 29]

nD = numel(D_LIST);
nS = numel(SNR_TEST);

acc_tx  = zeros(nS, nD);   % 정답(tx_pulses) 대비 정확도 [%]
agr_ml  = zeros(nS, nD);   % MATLAB 기준(est_pulses_ml) 일치율 [%]  ← 이식 동치성
bytes_d = zeros(1, nD);
segd_n  = zeros(1, nD);
tpld_n  = zeros(1, nD);

fprintf('=== 데시메이션 스윕 ===\n');
fprintf('입력: 기존 signal_SNR*.bin (int16, 양자화 포함)\n');
fprintf('TPL_USE(full-rate)=%d | LPF=%d (order %d)\n\n', ...
        TPL_USE, USE_LPF, LPF_ORDER);

%% ---------------- SNR 루프 ----------------
for si = 1:nS

    snr = SNR_TEST(si);

    % ---- 신호(.bin) 로드 ----
    bin_path = fullfile(out_dir, sprintf('signal_SNR%+03d.bin', snr));
    fid = fopen(bin_path, 'r');
    if fid < 0
        error('파일 없음: %s', bin_path);
    end
    raw = fread(fid, inf, 'int16=>double');
    fclose(fid);

    expect = WIN_LEN * N_DATA * N_ITER;
    if numel(raw) ~= expect
        error('크기 불일치: %s (%d != %d)', bin_path, numel(raw), expect);
    end
    sig = reshape(raw, [WIN_LEN, N_DATA, N_ITER]);   % column-major 복원

    % ---- 정답 / 기준결과 / 템플릿(.mat) 로드 ----
    S  = load(fullfile(out_dir, sprintf('dataset_SNR%+03d.mat', snr)));
    ds = S.ds;

    tx_pulses = ds.tx_pulses;          % [30 x 6]
    est_ml    = ds.est_pulses_ml;      % [30 x 6]
    tpl_use   = ds.tpl_use_vec(:);     % [3000 x 1]

    if numel(tpl_use) ~= TPL_USE
        error('템플릿 길이 불일치: %d != %d', numel(tpl_use), TPL_USE);
    end

    for di = 1:nD

        D = D_LIST(di);

        % ---- (1) D 유효성 ----
        if mod(SHIFT, D) ~= 0
            error('D=%d 는 SHIFT=%d 의 약수가 아님 (후보가 격자를 벗어남)', D, SHIFT);
        end

        % ---- (2) 위상 결정 + 데시메이션 좌표 ----
        r        = mod(CAND0(1), D);
        cand_d   = (CAND0 - r) / D + 1;          % 1-based
        idx_keep = (r : D : WIN_LEN-1) + 1;
        Nd       = numel(idx_keep);

        % ---- (3) 안티에일리어싱 필터 ----
        if USE_LPF && D > 1
            h = fir1(LPF_ORDER, 1/D);
        else
            h = [];
        end

        % ---- (4) 템플릿 데시메이션 (위상 0) ----
        if isempty(h)
            tpl_d = tpl_use(1:D:end);
        else
            tpl_d = filtfilt(h, 1, tpl_use);     % 영위상 → 봉우리 위치 보존
            tpl_d = tpl_d(1:D:end);
        end
        tpl_d  = tpl_d(:);
        Ltpl_d = numel(tpl_d);

        need = cand_d(3) + Ltpl_d - 1;
        if need > Nd
            error('조각 부족: D=%d, 필요 %d > 보유 %d', D, need, Nd);
        end

        % ---- (5) 상관 → argmax ----
        n_ok = 0; n_tot = 0; n_agr = 0;

        for it = 1:N_ITER
            for k = 1:N_DATA

                seg = sig(:, k, it);             % [3050 x 1] int16 원값(double)

                if isempty(h)
                    seg_d = seg(idx_keep);
                else
                    segf  = filtfilt(h, 1, seg);
                    seg_d = segf(idx_keep);
                end

                cval = zeros(1, 3);
                for c = 1:3
                    s = cand_d(c);
                    cval(c) = seg_d(s : s+Ltpl_d-1).' * tpl_d;
                end

                [~, sel] = max(cval);
                est = sel - 2;                   % 1→-1, 2→0, 3→+1

                n_tot = n_tot + 1;
                n_ok  = n_ok  + (est == tx_pulses(it, k));
                n_agr = n_agr + (est == est_ml(it, k));
            end
        end

        acc_tx(si, di) = n_ok  / n_tot * 100;
        agr_ml(si, di) = n_agr / n_tot * 100;
        bytes_d(di)    = Nd * N_DATA * 2;
        segd_n(di)     = Nd;
        tpld_n(di)     = Ltpl_d;

        fprintf(['SNR %+3d | D=%2d | 조각 %4d | 템플릿 %4d | ', ...
                 '정확도 %5.1f%% | ML일치 %5.1f%% | %6d B/iter\n'], ...
                snr, D, Nd, Ltpl_d, acc_tx(si,di), agr_ml(si,di), bytes_d(di));
    end
    fprintf('\n');
end

%% ---------------- 전송시간 환산 ----------------
fprintf('=== iteration 당 전송시간 환산 ===\n');
fprintf(' D  | 조각 | 템플릿 |   Bytes | UART 460800 | SPI 10.5MHz | SPI 21MHz\n');
fprintf('----+------+--------+---------+-------------+-------------+----------\n');
for di = 1:nD
    B = bytes_d(di);
    t_uart = B * 10 / 460800 * 1e3;
    t_spi1 = B *  8 / 10.5e6 * 1e3;
    t_spi2 = B *  8 / 21.0e6 * 1e3;
    fprintf('%3d | %4d | %6d | %7d | %8.2f ms | %8.2f ms | %6.2f ms\n', ...
            D_LIST(di), segd_n(di), tpld_n(di), B, t_uart, t_spi1, t_spi2);
end
fprintf('\n목표: GRI 99300 us 의 10%% = 9.93 ms\n\n');

%% ---------------- 그래프 ----------------
figure('Name', 'Decimation sweep', 'Position', [100 100 1100 400]);

subplot(1,3,1); hold on; grid on;
colors = lines(nS);
for si = 1:nS
    plot(D_LIST, acc_tx(si,:), '-o', 'Color', colors(si,:), ...
         'LineWidth', 1.5, 'DisplayName', sprintf('SNR %+d dB', SNR_TEST(si)));
end
xlabel('데시메이션 배수 D'); ylabel('펄스 판정 정확도 (%)');
title('D vs 정확도 (정답 대비)');
legend('Location','southwest'); ylim([0 105]); xticks(D_LIST);
yline(33.3, 'k--', '랜덤(33%)');

subplot(1,3,2); hold on; grid on;
for si = 1:nS
    plot(D_LIST, agr_ml(si,:), '-s', 'Color', colors(si,:), ...
         'LineWidth', 1.5, 'DisplayName', sprintf('SNR %+d dB', SNR_TEST(si)));
end
xlabel('데시메이션 배수 D'); ylabel('MATLAB 결과 일치율 (%)');
title('D vs 이식 동치성');
legend('Location','southwest'); ylim([0 105]); xticks(D_LIST);

subplot(1,3,3); hold on; grid on;
bar(1:nD, bytes_d * 8 / 10.5e6 * 1e3);
xticks(1:nD); xticklabels(string(D_LIST));
xlabel('데시메이션 배수 D'); ylabel('SPI 10.5MHz 전송시간 (ms)');
title('D vs 전송시간');
yline(9.93, 'r--', '목표 9.93 ms', 'LineWidth', 1.5);

%% ---------------- 판정 ----------------
fprintf('=== 판정 (D=1 대비 최악 SNR 기준) ===\n');
for di = 2:nD
    drop_acc = max(acc_tx(:,1) - acc_tx(:,di));
    drop_agr = max(agr_ml(:,1) - agr_ml(:,di));
    if drop_acc <= 1.0
        v = '사용 가능';
    elseif drop_acc <= 3.0
        v = '경계 — 저SNR 재확인';
    else
        v = '부적합';
    end
    fprintf('D=%2d : 정확도 -%.1f%%p, 동치성 -%.1f%%p → %s\n', ...
            D_LIST(di), drop_acc, drop_agr, v);
end
