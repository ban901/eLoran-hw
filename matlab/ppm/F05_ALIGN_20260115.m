function frame_align = F05_ALIGN_20260115(coarse_start, fs_raw)
% ------------------------------------------------------------
% Frame Alignment using Coarse TOA (Master 기준)
% ------------------------------------------------------------

pulse_interval_samp = round(1000e-6 * fs_raw);   % 1ms → samples

frame_align.t0               = coarse_start;
frame_align.master_pulse_idx = coarse_start + (0:9) * pulse_interval_samp;

end
