%% MCU 복조 검증
%  iteration 마다 CMD_LOAD -> CMD_DEMOD -> RSP_RESULT 를 주고받고
%  dataset_SNR{xx}_D10.mat 의 MATLAB 기준결과와 대조한다.
%
%  프레임: [A5 C3][TYPE][PAYLOAD][CRC lo hi]   CRC-16/CCITT-FALSE, SOF 제외
%  위치  : matlab/comm/DEMOD_TEST.m

% clc;
clear;

PORT = "COM7";
BAUD = 460800;
SNR  = '-08';                   % '-12' '-08' '-04' '+00' '+04'
N    = 30;

BIN  = sprintf('dataset/signal_SNR%s_D10.bin',  SNR);
MAT  = sprintf('dataset/dataset_SNR%s_D10.mat', SNR);

LOAD_LEN = 3660;                % 305*6*2
RES_LEN  = 31;                  % 결과 페이로드

%% 데이터 준비
raw = fread(fopen(BIN,'r'), inf, 'uint8=>uint8').';   fclose('all');
ds  = load(MAT).ds;

%% 포트 열기
s = serialport(PORT, BAUD);  s.Timeout = 3;  flush(s);

est_pulses = zeros(N, 6);
bits       = zeros(N, 7);
state      = zeros(N, 1);
status     = zeros(N, 1);
t_us       = zeros(N, 4);       % corr / decide / comm / total
n_fail     = 0;

%% 반복
for it = 1:N

    % --- CMD_LOAD : 신호 3660 B
    tx   = raw((it-1)*LOAD_LEN + (1:LOAD_LEN));
    body = [uint8(4), tx];
    write(s, [165 195 body crc_le(crc16(body))], "uint8");

    % --- CMD_DEMOD : 페이로드 없음
    body = uint8(5);
    write(s, [165 195 body crc_le(crc16(body))], "uint8");

    % --- RSP_RESULT : 36 B
    try
        r = uint8(read(s, RES_LEN + 5, "uint8"));
    catch
        fprintf('  iter %2d  타임아웃\n', it);   n_fail = n_fail + 1;   continue;
    end

    if r(1) ~= 165 || r(2) ~= 195 || r(3) ~= 133      % A5 C3 85
        fprintf('  iter %2d  헤더 불량\n', it);  n_fail = n_fail + 1;  continue;
    end
    if crc16(r(3:end-2)) ~= (uint16(r(end-1)) + bitshift(uint16(r(end)), 8))
        fprintf('  iter %2d  CRC 불일치\n', it); n_fail = n_fail + 1;  continue;
    end

    p = r(4:end-2);                                   % 페이로드 31 B

    est_pulses(it,:) = double(typecast(p(1:6), 'int8'));
    bits(it,:)       = double(p(7:13));
    state(it)        = double(p(14));
    status(it)       = double(p(15));
    t_us(it,:)       = double(typecast(p(16:31), 'uint32'));

    if status(it) ~= 0
        fprintf('  iter %2d  status=%d (신호 미로드)\n', it, status(it));
        n_fail = n_fail + 1;
    end
end

clear s

%% 대조
sl  = double(ds.est_pulses_sl);      % 1차 상관 기준값
bml = double(ds.est_bits_ml);        % MATLAB 최종 비트
stm = double(ds.state_ml(:));        % MATLAB state
txb = double(ds.tx_bits);            % 정답

ok_corr  = all(est_pulses == sl,  2);
ok_bits  = all(bits       == bml, 2);
ok_state = (state == stm);
ok_true  = all(bits       == txb, 2);

fprintf('\n========== 통신 ==========\n');
fprintf('실패 %d / %d\n', n_fail, N);

fprintf('\n========== 동치성 ==========\n');
fprintf('1차 상관  vs est_pulses_sl : %2d / %d\n', sum(ok_corr),  N);
fprintf('최종 비트 vs est_bits_ml   : %2d / %d\n', sum(ok_bits),  N);
fprintf('state     vs state_ml      : %2d / %d\n', sum(ok_state), N);
fprintf('절대 정답 vs tx_bits       : %2d / %d  (MATLAB %d / %d)\n', ...
        sum(ok_true), N, sum(all(bml == txb, 2)), N);

fprintf('\nstate 분포  MCU [%d %d %d] | MATLAB [%d %d %d]\n', ...
        sum(state==0), sum(state==1), sum(state==2), ...
        sum(stm==0),   sum(stm==1),   sum(stm==2));

if ~all(ok_corr)
    fprintf('\n>> 1차 상관이 틀렸다. 원인은 상관 연산 또는 신호 전송.\n');
elseif ~all(ok_bits)
    fprintf('\n>> 1차 상관은 맞고 최종이 틀렸다. 원인은 CDC/MDD 또는 임계값.\n');
end

fprintf('\n========== 처리시간 [us] ==========\n');
fprintf('               평균      최대\n');
fprintf('Correlation  %7.1f   %7.1f\n', mean(t_us(:,1)), max(t_us(:,1)));
fprintf('Decision     %7.1f   %7.1f\n', mean(t_us(:,2)), max(t_us(:,2)));
fprintf('Comm         %7.1f   %7.1f\n', mean(t_us(:,3)), max(t_us(:,3)));
fprintf('Total        %7.1f   %7.1f   (목표 9930)\n', ...
        mean(t_us(:,4)), max(t_us(:,4)));

fprintf('\n상관 불일치 iter : %s\n', mat2str(find(~ok_corr)'));
fprintf('MDD 발동 iter    : %s\n', mat2str(find(state==2)'));

% n_timeout = bitand(t_us(:,3), 255);
% n_crcerr  = bitand(bitshift(t_us(:,3), -8), 255);
% n_uarterr = bitand(bitshift(t_us(:,3), -16), 255);
% fprintf('누적 카운터  timeout=%d  crc_err=%d  uart_err=%d\n', ...
%         n_timeout(end), n_crcerr(end), n_uarterr(end));

%% ------------------------------------------------------------------
function b = crc_le(c)
    b = [bitand(c,255) bitshift(c,-8)];
end

function crc = crc16(d)
    d = uint8(d(:));  crc = uint16(65535);
    for i = 1:numel(d)
        crc = bitxor(crc, bitshift(uint16(d(i)), 8));
        for b = 1:8
            if bitand(crc, uint16(32768)) ~= 0
                crc = bitxor(bitshift(crc,1), uint16(4129));
            else
                crc = bitshift(crc,1);
            end
        end
    end
end
