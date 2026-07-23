function [tx_mod, pulses6] = F02_PPMMOD_20260115(tx_in, bits7)
% ------------------------------------------------------------------------
% PPM Modulation(변조):
%
% Bits(7-bit) to Pulses(변조 코드, 3~8번째 펄스 = 6-pulse) 매핑 후
% 데이터 펄스(3~8번째)에 대해 PPM shift(+/-1us or 0us) 적용
%
% Input:
%   tx_in  : 변조 대상 신호
%   bits7  : 데이터 비트열 (7-bit)
%
% Output:
%   tx_mod  : PPM shift 적용된 신호
%   pulses6 : 데이터 비트열에 해당하는 PPM 변조 패턴(6-pulses)
%
% [최적화]
%   - F01_PPMCFG는 persistent 캐시에서 즉시 반환됨
%   - F08_BITIDX는 O(1) 직접 인덱스 계산
%   - nom_starts_samp / shift_samp / pulse_len_samp 를 1회 계산
% ------------------------------------------------------------------------

ppm_cfg = F01_PPMCFG_20260116();

tx_mod = tx_in(:).';

% (1) bits7 -> idx (O(1))
idx = F08_BITIDX_20260115(bits7);

% (2) idx -> pulses6
pulses6 = ppm_cfg.pulses_table(idx, :);

% (3) 단위 변환 (us -> samples)
nom_starts_samp = round(ppm_cfg.nom_starts_us * 1e-6 * ppm_cfg.fs) + 1;
shift_samp      = round(ppm_cfg.ppm_shift_us  * 1e-6 * ppm_cfg.fs);
pulse_len_samp  = nom_starts_samp(2) - nom_starts_samp(1);
N               = numel(tx_mod);

% (4) 데이터 펄스(3~8번째)만 shift 적용
tx_in_row = tx_in(:).';

for k = 1:numel(ppm_cfg.data_pulse_idx)

    p   = ppm_cfg.data_pulse_idx(k);
    s0  = nom_starts_samp(p);
    s1  = s0 + pulse_len_samp - 1;

    if s0 < 1 || s1 > N
        continue;
    end

    delta = pulses6(k) * shift_samp;

    s0n = s0 + delta;
    s1n = s1 + delta;

    if s0n < 1 || s1n > N
        continue;
    end

    tx_mod(s0:s1)   = 0;
    tx_mod(s0n:s1n) = tx_in_row(s0:s1);

end

end
