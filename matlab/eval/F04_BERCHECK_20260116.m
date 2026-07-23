function [bit_err, bit_tot] = F04_BERCHECK_20260116(tx_bits7, rx_bits7)
% 비트 에러 수 및 총 비트 수 반환
bit_tot = numel(tx_bits7);
bit_err = sum(tx_bits7(:).' ~= rx_bits7(:).');
end
