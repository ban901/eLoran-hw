function [idx, pulses, none] = F09_PULIDX_20260115(pulses6, fin)
% ------------------------------------------------------------------------
% pulses6 → pulses_table 행 번호 변환
%
% [최적화] ismember(pulses_table, pulses6, 'rows') 제거.
%   각 원소가 {-1, 0, +1}인 6개 값을 3진수 key로 인코딩하여
%   사전 계산된 해시 배열(pulses_map)로 O(1) 직접 검색.
%
%   인코딩: (-1,0,+1) → (0,1,2), 가중치 = 3.^[5:-1:0]
%   key = (pulses6+1) * [243;81;27;9;3;1] + 1   (1~729 범위)
%   pulses_map(key) = 해당 row index (없으면 0)
%
%   Fallback (fin==1): 기존 L1 거리 기반 최근접 탐색 유지
% ------------------------------------------------------------------------

persistent pulses_table pulses_map W3

if isempty(pulses_table)
    pulses_table = F07_PULMAP_20260115();               % [128 x 6]
    W3           = [243; 81; 27; 9; 3; 1];              % 3진수 가중치 (double)
    pulses_map   = zeros(3^6, 1);                       % 729-entry 해시 배열
    for i = 1:size(pulses_table, 1)
        key = (pulses_table(i,:) + 1) * W3 + 1;        % 1-based key (스칼라 결과)
        pulses_map(key) = i;
    end
end

none = 0;
idx  = 0;

% ----------------------------------------------------------
% (1) O(1) 정확 매칭
% ----------------------------------------------------------
key = (double(pulses6) + 1) * W3 + 1;

if key >= 1 && key <= 729
    tmp = pulses_map(key);
    if tmp > 0
        idx    = double(tmp);
        pulses = pulses_table(idx, :);
        return;
    end
end

% ----------------------------------------------------------
% (2) No exact match
% ----------------------------------------------------------
if fin == 0
    none   = 1;
    idx    = [];
    pulses = [];
    return;
end

% ----------------------------------------------------------
% (3) Fallback: L1 최근접 탐색
% ----------------------------------------------------------
subt      = sum(abs(pulses_table - pulses6), 2);
[~, idx]  = min(subt);
pulses    = pulses_table(idx, :);
none      = 0;

end