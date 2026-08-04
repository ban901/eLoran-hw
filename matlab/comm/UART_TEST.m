%% UART 회선 검증 (MCU 는 받은 프레임을 TYPE 만 0x86 으로 바꿔 반사)
%  프레임: [A5 C3][TYPE][PAYLOAD][CRC lo hi]   CRC-16/CCITT-FALSE, SOF 제외

% clc; clear;

PORT  = "COM7";
BAUD  = 460800;
BIN   = 'dataset/signal_SNR+00_D10.bin';
BYTES = 3660;                   % 305*6*2
N     = 30;

raw = fread(fopen(BIN,'r'), inf, 'uint8=>uint8').';   fclose('all');

s = serialport(PORT, BAUD);  s.Timeout = 2;  flush(s);
n_fail = 0;
t_ms = zeros(1, N);

for it = 1:N
    tic;
    tx = raw((it-1)*BYTES + (1:BYTES));

    body  = [uint8(6), tx];                                  % TYPE_ECHO
    c     = crc16(body);
    write(s, [165 195 body bitand(c,255) bitshift(c,-8)], "uint8");

    try
        r = read(s, BYTES+5, "uint8");
    catch
        fprintf('  iter %2d  timeout\n', it);  n_fail = n_fail+1;  continue;
    end

    t_ms(it) = toc * 1e3;

    r = uint8(r(:).');
    if r(1)~=165 || r(2)~=195       % SOF = 0xA5 0xC3
        fprintf('  iter %2d  SOF 불량\n', it);            n_fail = n_fail+1;
    elseif crc16(r(3:end-2)) ~= (uint16(r(end-1)) + bitshift(uint16(r(end)),8))
        fprintf('  iter %2d  CRC 불일치\n', it);          n_fail = n_fail+1;
    elseif ~isequal(r(4:end-2), tx)
        fprintf('  iter %2d  내용 %d B 불일치\n', it, sum(r(4:end-2)~=tx));
        n_fail = n_fail+1;
    end
end

fprintf('\n실패 %d / %d\n', n_fail, N);
fprintf('왕복 %.1f ms (평균) | %.1f ms (최대)\n', mean(t_ms), max(t_ms));
fprintf('이론값 %.1f ms (3665 B 왕복 @ 460800 bps)\n', 3665*2*10/460800*1e3);
clear s

%% ------------------------------------------------------------------
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
