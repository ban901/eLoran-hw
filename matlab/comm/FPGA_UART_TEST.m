%% FPGA_UART_TEST.m
%  PC -> FPGA (Basys3) UART 단독 확인용 최소 스크립트.
%  MCU / SPI 없이, FPGA가 신호 프레임을 받아 seg에 적재하는지만 본다.
%  성공 판정: 보드의 LD0(loaded), LD1(crc_ok)이 둘 다 켜지면 OK.
%
%  프레임: [A5 C3][TYPE=04][PAYLOAD 3660B][CRC hi lo]
%  CRC-16/CCITT-FALSE, 커버리지 = TYPE+PAYLOAD, 전송순서 = hi 먼저
%  (FPGA frame_rx.v 규약과 일치. 다르면 여기 or frame_rx.v를 맞출 것)

clear;

PORT = "COM11";
BAUD = 460800;
BIN  = 'dataset/signal_SNR+00_D10.bin';   % 경로 맞출 것
LOAD_LEN = 3660;        % 305*6*2
IT   = 1;               % 보낼 iteration 번호 (1부터)

%% 신호 한 iteration 읽기
f = fopen(BIN,'r');  raw = fread(f, inf, 'uint8=>uint8').';  fclose(f);
payload = raw((IT-1)*LOAD_LEN + (1:LOAD_LEN));
assert(numel(payload)==LOAD_LEN, '신호 길이 오류');

%% 프레임 조립
TYPE  = uint8(4);
body  = [TYPE payload];                 % CRC 대상 = TYPE + PAYLOAD
c     = crc16(body);
frame = uint8([165 195, body, bitand(c,255), bitshift(c,-8)]);  % A5 C3 ... CRClo CRChi (LE)
fprintf('frame %d bytes, CRC=0x%04X\n', numel(frame), c);

%% 전송
s = serialport(PORT, BAUD);  s.Timeout = 3;  flush(s);
write(s, frame, "uint8");
pause(0.2);
clear s
fprintf('전송 완료. 보드에서 LD0(loaded), LD1(crc_ok) 확인.\n');
fprintf('  둘 다 ON  -> PC->FPGA UART + 파싱 OK\n');
fprintf('  LD0만 ON  -> 데이터는 받았으나 CRC 불일치 (규약 확인)\n');
fprintf('  둘 다 OFF -> COM 포트/보드레이트/배선 확인\n');

%% CRC-16/CCITT-FALSE
function crc = crc16(d)
    d = uint8(d(:));  crc = uint16(65535);
    for i = 1:numel(d)
        crc = bitxor(crc, bitshift(uint16(d(i)), 8));
        for b = 1:8
            if bitand(crc, uint16(32768)) ~= 0
                crc = bitxor(bitshift(crc,1), uint16(4129));   % 0x1021
            else
                crc = bitshift(crc,1);
            end
        end
        crc = bitand(crc, uint16(65535));
    end
end
