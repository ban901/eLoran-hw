function [est_bits, est_pulses, rx_pulses, state, tpl] = F03_PPMDEM_20260305(y, frame_align)
% ------------------------------------------------------------------------
% PPM Demodulation (복조):
%
% 수신 신호에서 데이터 펄스(3~8번째)의 PPM shift를 추정하여
% 6-pulses -> est_bits (7-bit) 복조
%
% Input:
%   y           : 전처리까지 완료된 수신 신호
%   frame_align : F05_ALIGN_20260115 결과(t0, master_pulse_idx)
%
% Output:
%   est_bits    : [1x7] 추정된 Eurofix 7bit
%   est_pulses  : [1x6] 추정된 pulses6 (-1/0/+1)
%   rx_pulses   : [1x6] 테이블 매칭된 pulses6
%   state       : 복조 방법 (0=hard, 1=CDC, 2=fallback)
%   tpl         : 사용된 펄스 템플릿
%
% [최적화]
%   - persistent: ppm_cfg, bits_map, tpl(펄스 템플릿) 재생성 방지
%     → P10_PULSE_20251223 (비용 큰 호출) 최초 1회로 제한
% ------------------------------------------------------------------------

persistent ppm_cfg bits_map tpl_env_p Ltpl_p shift_samp_p tpl_p

if isempty(ppm_cfg)
    ppm_cfg      = F01_PPMCFG_20260116();
    bits_map     = F06_BITMAP_20260115();
    tpl_p        = real(P10_PULSE_20251223(ppm_cfg.fs));
    tpl_p        = tpl_p(:);
    tpl_env_p    = abs(tpl_p);
    Ltpl_p       = length(tpl_p);
    shift_samp_p = round(ppm_cfg.ppm_shift_us * 1e-6 * ppm_cfg.fs);
end

tpl = tpl_p;

y     = y(:).';
y_env = abs(y);

% ----------------------------------------------------------
% (0) 기본 파라미터 (캐시에서 직접 참조)
% ----------------------------------------------------------
data_idx   = ppm_cfg.data_pulse_idx;
shift_samp = shift_samp_p;
tpl_env    = tpl_env_p;
Ltpl       = Ltpl_p;

% ----------------------------------------------------------
% (1) frame_align -> nominal 위치
% ----------------------------------------------------------
nom_pos  = frame_align.master_pulse_idx;
data_idx = data_idx(data_idx <= numel(nom_pos));

% ----------------------------------------------------------
% (2) 3~8번째 펄스에서 PPM shift 추정
% ----------------------------------------------------------
n_data     = numel(data_idx);
est_pulses = zeros(1, n_data);
corr_diff  = inf(1, n_data);
alt_shift  = cell(1, n_data);
crr        = zeros(n_data, 3);

for k = 1:n_data

    p       = data_idx(k);
    nominal = nom_pos(p);

    cand = [nominal - shift_samp, nominal, nominal + shift_samp];

    if cand(1) < 1 || (cand(3) + Ltpl - 1) > length(y_env)
        est_pulses(k) = 0;
        continue;
    end

    % 3후보 상관값 일괄 계산
    cval = [y_env(cand(1):cand(1)+Ltpl-1) * tpl_env, ...
            y_env(cand(2):cand(2)+Ltpl-1) * tpl_env, ...
            y_env(cand(3):cand(3)+Ltpl-1) * tpl_env];

    [~, sel] = max(cval);

    if sel == 1
        est_pulses(k) = -1;
        corr_diff(k)  = cval(1) - cval(2);
        alt_shift{k}  = 1;
    elseif sel == 2
        est_pulses(k) = 0;
        corr_diff(k)  = min(cval(2)-cval(1), cval(2)-cval(3));
        alt_shift{k}  = [-1, 1];
    else
        est_pulses(k) = +1;
        corr_diff(k)  = cval(3) - cval(2);
        alt_shift{k}  = -1;
    end

    crr(k,:) = cval;

end

% ----------------------------------------------------------
% (3) pulses6 -> idx (O(1) 해시)
% ----------------------------------------------------------
[idx, rx_pulses, none] = F09_PULIDX_20260115(est_pulses, 0);

% ----------------------------------------------------------
% (4) 1차 - hard decision
% ----------------------------------------------------------
if none == 0
    est_bits = bits_map(idx, :);
    state    = 0;
    return;
end

% ----------------------------------------------------------
% (5) 2차 - corr 기반 재탐색 (CDC)
% ----------------------------------------------------------
th       = 1e-3;
cand_idx = find(corr_diff < th);

if ~isempty(cand_idx)
    [~, ord]  = sort(corr_diff(cand_idx), 'ascend');
    cand_idx  = cand_idx(ord);
    max_comb  = min(3, numel(cand_idx));

    for n = 1:max_comb

        comb = nchoosek(cand_idx, n);

        for c = 1:size(comb, 1)

            pos        = comb(c, :);
            shift_sets = alt_shift(pos);

            grids = cell(1, n);
            [grids{:}] = ndgrid(shift_sets{:});

            num_case = numel(grids{1});

            for case_i = 1:num_case

                test_pulses = est_pulses;
                for i = 1:n
                    test_pulses(pos(i)) = test_pulses(pos(i)) + grids{i}(case_i);
                end

                [idx, rx_pulses, none] = F09_PULIDX_20260115(test_pulses, 0);

                if none == 0
                    est_bits = bits_map(idx, :);
                    state    = 1;
                    return;
                end

            end

        end

    end
end

% ----------------------------------------------------------
% (6) 3차 - 최후 fallback
% ----------------------------------------------------------
[idx, rx_pulses, ~] = F09_PULIDX_20260115(est_pulses, 1);
est_bits = bits_map(idx, :);
state    = 2;

end
