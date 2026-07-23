function [tx_bits, est_bits, tx_pulses, est_pulses, rx_pulses, state, ...
          x_lp, frame_align] = M10_EXTRACT_20260404(snr)
% ------------------------------------------------------------------------
%  M10_EXTRACT_20260404  [PUBLIC STUB - 본문 비공개]
%
%   본 저장소에는 이 함수의 구현부가 포함되어 있지 않습니다.
%   이 함수는 연구실 자산인 전처리/Coarse TOA 추정 체인
%   (M10_COARSETOA_20251223)을 기반으로 하며, 반환값만 확장한 버전입니다.
%   IP 보호를 위해 인터페이스(호출 규약)만 공개합니다.
%
%  [역할]
%    합성 수신신호 생성 → BPF → analytic signal(포락선) → xcorr 기반
%    Coarse TOA 추정 → 프레임 정렬 → PPM 복조(F03) 까지 수행하고,
%    그 중간 산출물인 x_lp / frame_align 을 함수 밖으로 반환한다.
%
%  [Input]
%    snr          : 수신 SNR [dB]
%
%  [Output]
%    tx_bits      : [1x7]  송신 정답 비트 (Eurofix 7-bit)
%    est_bits     : [1x7]  F03 복조 결과 비트
%    tx_pulses    : [1x6]  송신 정답 펄스 패턴 (-1/0/+1)
%    est_pulses   : [1x6]  F03 추정 펄스 패턴
%    rx_pulses    : [1x6]  테이블 매칭된 펄스 패턴
%    state        : 복조 경로 (0=hard, 1=CDC, 2=fallback)
%    x_lp         : [N x 1] 전처리 완료된 analytic 수신신호
%                           (abs(x_lp) 가 복조에 쓰이는 포락선)
%    frame_align  : struct. F05_ALIGN 결과
%                     .t0               coarse TOA
%                     .master_pulse_idx [1x10] 각 펄스 nominal 위치 (원신호 좌표)
%
%  [의존 함수 - 본 저장소 제외분]
%    G10_TXMAIN_20251223, G13_PULSE_20251223, G14_PHASE_20251223
%    (상세는 matlab/external/README.md 참고)
%
%  [의존 함수 - 본 저장소 포함분]
%    F05_ALIGN_20260115, F03_PPMDEM_20260305
% ------------------------------------------------------------------------

error(['M10_EXTRACT_20260404: 구현부는 연구실 IP에 해당하여 본 저장소에서 ', ...
       '제외되었습니다. 상단 주석의 인터페이스 명세를 참고하십시오.']);

end
