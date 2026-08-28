%% DEMOD_TEST_FPGA.m  ─ 재설계 구조(FPGA 오프로딩) 검증
%cl
%  PC --UART--> FPGA(상관)  및  PC <-USART2-> MCU(복조) 두 포트를 함께 쓴다.
%  iteration 마다:
%    1) FPGA 로 신호 프레임(CMD_LOAD) 전송  -> FPGA 가 seg 적재
%    2) MCU 로 CMD_DEMOD 전송               -> MCU 가 START->DONE->SPI 읽기->복조
%    3) MCU 로부터 RSP_RESULT(36 B) 수신    -> MATLAB 기준결과와 대조
%
%  프레임: [A5 C3][TYPE][PAYLOAD][CRC lo hi]  CRC-16/CCITT-FALSE, SOF 제외, LE
%  위치  : matlab/comm/DEMOD_TEST_FPGA.m

clear;

PORT_FPGA = "COM11";
PORT_MCU  = "COM7";     % <-- NUCLEO ST-Link VCP (USART2)
BAUD      = 460800;
SNR       = '+00';      % '-12' '-08' '-04' '+00' '+04'
N         = 30;

BIN = sprintf('dataset/signal_SNR%s_D10.bin',  SNR);
MAT = sprintf('dataset/dataset_SNR%s_D10.mat', SNR);

LOAD_LEN = 3660;        % 305*6*2
RES_LEN  = 31;

%% 데이터
raw = fread(fopen(BIN,'r'), inf, 'uint8=>uint8').';  fclose('all');
ds  = load(MAT).ds;

%% 포트 2개
sf = serialport(PORT_FPGA, BAUD);  sf.Timeout = 3;  flush(sf);
sm = serialport(PORT_MCU,  BAUD);  sm.Timeout = 3;  flush(sm);

est_pulses = zeros(N,6); bits = zeros(N,7);
state = zeros(N,1); status = zeros(N,1); t_us = zeros(N,4);
n_fail = 0;

% 워밍업: 포트 오픈 직후 첫 프레임은 버린다 (실제 수신기엔 없는 시험용) %%%%%%%%%%%%%%%%%%%%%%%%%%
body = [uint8(4), raw(1:LOAD_LEN)];
write(sf, [165 195 body crc_le(crc16(body))], "uint8");  pause(0.5);

for it = 1:N

    % 1) 신호 -> FPGA (CMD_LOAD)
    tx   = raw((it-1)*LOAD_LEN + (1:LOAD_LEN));
    body = [uint8(4), tx];
    write(sf, [165 195 body crc_le(crc16(body))], "uint8");
    
    % UART 전송(~80 ms) + FPGA 적재가 끝나도록 대기 (실제 수신기엔 없는 시험용 지연)
    pause(0.1);

    % 2) 복조 시작 -> MCU (CMD_DEMOD, 페이로드 없음)
    body = uint8(5);
    write(sm, [165 195 body crc_le(crc16(body))], "uint8");

    % 3) 결과 <- MCU (36 B)
    try
        r = uint8(read(sm, RES_LEN + 5, "uint8"));
    catch
        fprintf('  iter %2d  타임아웃\n', it);  n_fail = n_fail+1;  continue;
    end
    if r(1)~=165 || r(2)~=195 || r(3)~=133
        fprintf('  iter %2d  헤더 불량\n', it);  n_fail = n_fail+1;  continue;
    end
    if crc16(r(3:end-2)) ~= (uint16(r(end-1)) + bitshift(uint16(r(end)),8))
        fprintf('  iter %2d  CRC 불일치\n', it); n_fail = n_fail+1;  continue;
    end

    p = r(4:end-2);
    est_pulses(it,:) = double(typecast(p(1:6),'int8'));
    bits(it,:)       = double(p(7:13));
    state(it)        = double(p(14));
    status(it)       = double(p(15));
    t_us(it,:)       = double(typecast(p(16:31),'uint32'));

    if status(it)~=0
        fprintf('  iter %2d  status=%d (FPGA 응답 없음/타임아웃)\n', it, status(it));
        n_fail = n_fail+1;
    end
end
clear sf sm

%% 대조 (기존 DEMOD_TEST.m 과 동일)
sl  = double(ds.est_pulses_sl);
bml = double(ds.est_bits_ml);
stm = double(ds.state_ml(:));
txb = double(ds.tx_bits);

ok_corr  = all(est_pulses == sl,  2);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if ~all(ok_corr), fprintf('불일치 iteration: %s\n', mat2str(find(~ok_corr).')); end
bad = find(~ok_corr).';
for b = bad
    fprintf('\nit %d 받음   : %s\n', b, mat2str(est_pulses(b,:)));
    fprintf('   정답      : %s\n', mat2str(sl(b,:)));
    for c = [b-1 b+1 30 1]
        if c>=1 && c<=30 && c~=b
            m = sum(est_pulses(b,:) == sl(c,:));
            fprintf('   sl(%2d) 과 %d/6 일치%s\n', c, m, repmat(' <<<',1,m>=5));
        end
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ok_bits  = all(bits       == bml, 2);
ok_state = (state == stm);
ok_true  = all(bits       == txb, 2);

fprintf('\n========== 통신 ==========\n실패 %d / %d\n', n_fail, N);
fprintf('\n========== 동치성 ==========\n');
fprintf('1차 상관  vs est_pulses_sl : %2d / %d\n', sum(ok_corr),  N);
fprintf('최종 비트 vs est_bits_ml   : %2d / %d\n', sum(ok_bits),  N);
fprintf('state     vs state_ml      : %2d / %d\n', sum(ok_state), N);
fprintf('절대 정답 vs tx_bits       : %2d / %d  (MATLAB %d / %d)\n', ...
        sum(ok_true), N, sum(all(bml==txb,2)), N);

if ~all(ok_corr)
    fprintf('\n>> 1차 상관 불일치. 원인은 FPGA 상관 or 신호 전송(FPGA UART).\n');
elseif ~all(ok_bits)
    fprintf('\n>> 상관은 맞고 최종이 틀림. CDC/MDD 또는 임계값.\n');
end

fprintf('\n========== 처리시간 [us] (FPGA 상관+SPI 포함) ==========\n');
fprintf('               평균      최대\n');
fprintf('Correlation  %7.1f   %7.1f\n', mean(t_us(:,1)), max(t_us(:,1)));
fprintf('Decision     %7.1f   %7.1f\n', mean(t_us(:,2)), max(t_us(:,2)));
fprintf('Total        %7.1f   %7.1f   (목표 9930)\n', mean(t_us(:,4)), max(t_us(:,4)));

%% ---- helpers ----
function b = crc_le(c)
    b = [bitand(c,255) bitshift(c,-8)];   % LE: lo, hi
end
function crc = crc16(d)
    d = uint8(d(:));  crc = uint16(65535);
    for i = 1:numel(d)
        crc = bitxor(crc, bitshift(uint16(d(i)),8));
        for b = 1:8
            if bitand(crc, uint16(32768)) ~= 0
                crc = bitxor(bitshift(crc,1), uint16(4129));
            else
                crc = bitshift(crc,1);
            end
        end
        crc = bitand(crc, uint16(65535));
    end
end
