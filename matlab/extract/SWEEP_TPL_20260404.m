%% ========================================================================
%  SWEEP_TPL_20260404.m   (테스트 전용)
%
%  [목적]
%    EXTRACT_FULL 로 뽑은 긴 조각을 이용해, 템플릿 길이(TPL_USE)를
%    500 ~ 10000 까지 쓸어보며 "펄스 판정 정확도"를 측정.
%    → 정확도가 충분히 오르는 최소 TPL_USE 를 찾는 것이 목표.
%      (그 길이가 최종 조각 크기 / MCU 연산량 / 통신량을 결정)
%
%  [원리]
%    각 조각(포락선)에서 후보 위치 [20-10, 20, 20+10] = [10,20,30] 에 대해
%    TPL_USE 길이만큼 상관 → argmax → -1/0/+1.
%    이를 정답(tx_pulses)과 비교.
%
%  [주의]
%    F03과 동일하게 "abs 포락선 × abs 템플릿" 상관을 쓴다.
%    조각은 double 원값이므로 스케일/정규화 영향 없음(정확도 판정엔 무관).
%  ========================================================================

clear; clc;

SNR_TEST = [-4, 0, 4];                       % 볼 SNR
TPL_LIST = [500 1000 1500 2000 3000 4000 ... % 쓸어볼 템플릿 길이
            5000 6000 8000 10000];
out_dir  = 'mcu_dataset';

figure; hold on; grid on;
colors = lines(numel(SNR_TEST));

for si = 1:numel(SNR_TEST)
    snr = SNR_TEST(si);
    S = load(fullfile(out_dir, sprintf('fulltest_SNR%+03d.mat', snr)));
    T = S.T;

    SEG_LEN  = T.seg_len;
    N_DATA   = T.n_data;
    N_ITER   = T.n_iter;
    NOM      = T.nom_in_seg;                  % 20
    SHIFT    = T.shift;                       % 10
    tpl_full = T.tpl_full;                    % 10000
    cand     = [NOM-SHIFT, NOM, NOM+SHIFT];   % [10,20,30]

    acc_curve = zeros(1, numel(TPL_LIST));

    for ti = 1:numel(TPL_LIST)
        TPL = TPL_LIST(ti);
        if TPL > length(tpl_full); TPL = length(tpl_full); end
        tpl = tpl_full(1:TPL);

        acc = 0; tot = 0;
        for it = 1:N_ITER
            for k = 1:N_DATA
                seg = T.seg(:,k,it).';
                cval = zeros(1,3);
                ok = true;
                for c = 1:3
                    s = cand(c);
                    if s >= 1 && (s+TPL-1) <= SEG_LEN
                        cval(c) = seg(s:s+TPL-1) * tpl;
                    else
                        ok = false;
                    end
                end
                if ~ok; continue; end
                [~, sel] = max(cval);
                acc = acc + (sel-2 == T.tx_pulses(it,k));
                tot = tot + 1;
            end
        end
        acc_curve(ti) = acc/tot*100;
        fprintf('SNR %+3d | TPL_USE=%5d : 정확도 %.1f%%\n', snr, TPL, acc_curve(ti));
    end
    fprintf('\n');

    plot(TPL_LIST, acc_curve, '-o', 'Color', colors(si,:), ...
         'LineWidth', 1.5, 'DisplayName', sprintf('SNR %+d dB', snr));
end

xlabel('TPL\_USE (템플릿 길이, 샘플)');
ylabel('펄스 판정 정확도 (%)');
title('템플릿 길이 vs 정확도  (최소 필요 길이 찾기)');
legend('Location','southeast');
ylim([0 105]);
yline(33.3, 'k--', '랜덤(33%)');
yline(100,  'k:');
