function ppm_cfg = F01_PPMCFG_20260116()
% ------------------------------------------------------------------------
% PPM Mod/Demod 공통 파라미터 + Eurofix mapping 테이블 로드
%
% [최적화] persistent 캐싱: 최초 1회만 struct 생성 및 테이블 로드.
%          이후 호출은 캐시된 값을 즉시 반환 (M10에서 9000회 호출 대응)
% ------------------------------------------------------------------------

persistent cfg_cache

if ~isempty(cfg_cache)
    ppm_cfg = cfg_cache;
    return;
end

cfg = struct();

% ====== Sampling 파라미터 ======
cfg.fs           = 10e6;      % [Hz]
cfg.ppm_shift_us = 1;         % [us]
cfg.local_us     = 20;        % 복조 펄스 탐색 구간 [us]

% ====== Pulse 파라미터 ======
cfg.Npulses        = 8;
cfg.pulse_gap_us   = 1000;    % 1 ms
cfg.nom_starts_us  = (0:7) * 1000;   % [0..7000] us  (Npulses=8 고정)
cfg.data_pulse_idx = 3:8;

% ====== Mapping table (1회만 로드) ======
cfg.bits_table   = F06_BITMAP_20260115();   % [128 x 7]
cfg.pulses_table = F07_PULMAP_20260115();   % [128 x 6]

cfg_cache = cfg;
ppm_cfg   = cfg_cache;

end
