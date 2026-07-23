% F10_LDCMAIN_20260119
%
% BER / PER / RXR 통계 누적 메인 스크립트
%
% [SER 정의]
%   - 1000회 반복 중 30개씩 묶음 (마지막 나머지는 버림) → 33묶음
%   - 묶음당 7bit × 30회 = 210비트를 iteration 순서로 이어붙인 뒤
%     30비트씩 7개 Symbol로 분할
%   - Symbol 오류 정의
%       [일반 SER]     : 30비트 중 1비트라도 비트 오류 발생 시
%       [Baseline SER] : 30비트 중 1비트라도 비트 오류 발생 시
%                        OR 해당 Symbol에 기여한 iter 중 state~=0 존재 시
%   - 묶음 SER = (오류 Symbol 수) / 7
%   - 두 SER 모두 대상 iter : 전체 1~990

clear; close all;

%% 파라미터 설정
SNR_list = -7:2:1;
Num      = 1000;

nS = numel(SNR_list);

BER = zeros(1, nS);
PER = zeros(1, nS);
RXR = zeros(1, nS);

BER_P1_cnt = zeros(1, 8);
PER_P1_cnt = zeros(1, 7);
BER_P2_cnt = zeros(1, 8);
PER_P2_cnt = zeros(1, 7);

m0_cnt = zeros(1, nS);
m1_cnt = zeros(1, nS);
m2_cnt = zeros(1, nS);

P1_snr = -8;
P2_snr = -4;

GROUP_SIZE = 30;                        % 묶음 크기 (= Symbol 1개당 비트 수)
N_BITS     = 7;                         % tx_bits7 길이
n_grp      = floor(Num / GROUP_SIZE);   % 33묶음 (991~1000 버림)

% SER 결과 배열
SER_groups_all = zeros(nS, n_grp);
mean_SER_all   = zeros(1, nS);
std_SER_all    = zeros(1, nS);

SER_groups_s0  = zeros(nS, n_grp);
mean_SER_s0    = zeros(1, nS);
std_SER_s0     = zeros(1, nS);

rng(993);

%% SNR 루프
for iS = 1:nS

    snrdb = SNR_list(iS);
    fprintf('SNR = %d dB\n', snrdb);

    % 누적 변수 초기화
    bit_err_sum = 0;  bit_tot_sum = 0;
    pul_err_sum = 0;  pul_tot_sum = 0;

    BER_k = zeros(Num, 1);
    PER_k = zeros(Num, 1);

    bit_err_sum_s0 = 0;  bit_tot_sum_s0 = 0;
    pul_err_sum_s0 = 0;  pul_tot_sum_s0 = 0;

    bit_err_sys_s0 = 0;  bit_tot_sys_s0 = 0;
    pul_err_sys_s0 = 0;  pul_tot_sys_s0 = 0;

    rx_success_cnt = 0;
    mis_cnt        = 0;

    % SER 계산용 버퍼 (전체 iter)
    tx_bits_all  = zeros(N_BITS, Num);
    est_bits_all = zeros(N_BITS, Num);
    state_all    = zeros(1, Num);   % state 저장 (Baseline SER 오류 판정용)

    %% 반복 루프
    for k = 1:Num

        % M10: 송신 + 수신 + 복조
        [tx_bits7, est_bits7, tx_pulses, est_pulses, rx_pulses, state] = ...
            M10_COARSETOA_20251223(snrdb);

        % SER용 비트·상태 저장
        tx_bits_all(:, k)  = tx_bits7(:);
        est_bits_all(:, k) = est_bits7(:);
        state_all(k)       = state;

        % 비트 에러
        [bit_err, bit_tot] = F04_BERCHECK_20260116(tx_bits7, est_bits7);
        bit_err_sum = bit_err_sum + bit_err;
        bit_tot_sum = bit_tot_sum + bit_tot;

        % 펄스 에러
        [pul_err, pul_tot] = F04_BERCHECK_20260116(tx_pulses, rx_pulses);
        pul_err_sum = pul_err_sum + pul_err;
        pul_tot_sum = pul_tot_sum + pul_tot;

        BER_k(k) = bit_err / bit_tot;
        PER_k(k) = pul_err / pul_tot;

        % baseline (state == 0)
        if state == 0
            bit_err_sum_s0 = bit_err_sum_s0 + bit_err;
            bit_tot_sum_s0 = bit_tot_sum_s0 + bit_tot;
            pul_err_sum_s0 = pul_err_sum_s0 + pul_err;
            pul_tot_sum_s0 = pul_tot_sum_s0 + pul_tot;
        else
            rx_success_cnt = rx_success_cnt + 1;
        end

        % baseline system (state0만 decode)
        if state == 0
            bit_err_sys_s0 = bit_err_sys_s0 + bit_err;
            bit_tot_sys_s0 = bit_tot_sys_s0 + bit_tot;
            pul_err_sys_s0 = pul_err_sys_s0 + pul_err;
            pul_tot_sys_s0 = pul_tot_sys_s0 + pul_tot;
        else
            bit_err_sys_s0 = bit_err_sys_s0 + bit_tot;
            bit_tot_sys_s0 = bit_tot_sys_s0 + bit_tot;
            pul_err_sys_s0 = pul_err_sys_s0 + pul_tot;
            pul_tot_sys_s0 = pul_tot_sys_s0 + pul_tot;
        end

        % 방법 통계
        switch state
            case 0, m0_cnt(iS) = m0_cnt(iS) + 1;
            case 1, m1_cnt(iS) = m1_cnt(iS) + 1;
            case 2, m2_cnt(iS) = m2_cnt(iS) + 1;
            otherwise
                fprintf('error: none of them (run = %d)\n', k);
        end

        % SNR point 히스토그램
        if snrdb == P1_snr
            BER_P1_cnt(bit_err + 1) = BER_P1_cnt(bit_err + 1) + 1;
            PER_P1_cnt(pul_err + 1) = PER_P1_cnt(pul_err + 1) + 1;
        end
        if snrdb == P2_snr
            BER_P2_cnt(bit_err + 1) = BER_P2_cnt(bit_err + 1) + 1;
            PER_P2_cnt(pul_err + 1) = PER_P2_cnt(pul_err + 1) + 1;
        end

        if any(tx_bits7 ~= est_bits7)
            mis_cnt = mis_cnt + 1;
        end

    end

    % SNR별 지표 계산
    BER(iS) = bit_err_sum / bit_tot_sum;
    PER(iS) = pul_err_sum / pul_tot_sum;
    S_BER(iS) = std(BER_k);
    S_PER(iS) = std(PER_k);

    BER_s0(iS) = bit_err_sum_s0 / bit_tot_sum_s0;
    PER_s0(iS) = pul_err_sum_s0 / pul_tot_sum_s0;

    RXR(iS) = rx_success_cnt / Num;

    BER_sys_s0(iS) = bit_err_sys_s0 / bit_tot_sys_s0;
    PER_sys_s0(iS) = pul_err_sys_s0 / pul_tot_sys_s0;

    fprintf('  BER = %.6g  (std %.6g)\n', BER(iS), S_BER(iS));
    fprintf('  PER = %.6g  (std %.6g)\n', PER(iS), S_PER(iS));
    fprintf('  [S0] BER = %.6g | PER = %.6g\n', BER_s0(iS), PER_s0(iS));
    fprintf('  Success Rate = %.4f\n', RXR(iS));
    fprintf('  [Baseline] BER = %.6g | PER = %.6g\n', BER_sys_s0(iS), PER_sys_s0(iS));

    %% SER 계산 -------------------------------------------------------
    % iter 1~990 (n_grp=33 묶음) 사용
    %
    % [Flatten 구조]
    %   tx_g  : N_BITS × GROUP_SIZE  (7×30)
    %   tx_g.' : 30×7  (iteration이 행 순으로 배열)
    %   reshape(., 1, []) → 1×210  (iter-major: iter1의 7비트, iter2의 7비트, ...)
    %   reshape(., GROUP_SIZE, N_BITS) = reshape(., 30, 7)
    %     → 열 k = k번째 Symbol (연속된 30비트)
    %
    % [일반 SER]
    %   sym_err_all = any(e_sym, 1)               % 비트 오류만
    %
    % [Baseline SER]
    %   state를 동일한 flatten 구조로 확장:
    %     repelem(st_g, N_BITS) → 1×210  (각 iter state를 N_BITS번 반복)
    %     reshape(., GROUP_SIZE, N_BITS) → 30×7  ← e_sym과 동일 구조
    %   sym_err_s0 = any(e_sym, 1) | any(s_sym ~= 0, 1)
    %     → 비트 오류 OR 해당 Symbol에 기여한 iter 중 state~=0 존재
    % -----------------------------------------------------------------

    M_use    = n_grp * GROUP_SIZE;               % 990
    tx_use   = tx_bits_all(:, 1:M_use);
    es_use   = est_bits_all(:, 1:M_use);
    st_use   = state_all(1:M_use);               % 1×990

    for g = 1:n_grp
        idx  = (g-1)*GROUP_SIZE + 1 : g*GROUP_SIZE;

        tx_g = tx_use(:, idx);                   % N_BITS × GROUP_SIZE
        es_g = es_use(:, idx);
        st_g = st_use(idx);                      % 1 × GROUP_SIZE

        % iteration-major flatten → 30×7 Symbol 행렬
        e_flat = reshape((tx_g ~= es_g).', 1, []); % 1×210
        e_sym  = reshape(e_flat, GROUP_SIZE, N_BITS);% 30×7

        % state를 동일한 flatten 구조로 확장
        s_flat = repelem(st_g, N_BITS);            % 1×210 (iter state × N_BITS)
        s_sym  = reshape(s_flat, GROUP_SIZE, N_BITS);% 30×7

        % 일반 SER : 비트 오류만
        sym_err_all = any(e_sym, 1);               % 1×7
        SER_groups_all(iS, g) = sum(sym_err_all) / N_BITS;

        % Baseline SER : 비트 오류 OR state~=0
        sym_err_s0 = any(e_sym, 1) | any(s_sym ~= 0, 1); % 1×7
        SER_groups_s0(iS, g) = sum(sym_err_s0) / N_BITS;
    end

    mean_SER_all(iS) = mean(SER_groups_all(iS, :));
    std_SER_all(iS)  = std(SER_groups_all(iS, :));

    mean_SER_s0(iS)  = mean(SER_groups_s0(iS, :));
    std_SER_s0(iS)   = std(SER_groups_s0(iS, :));

    fprintf('  SER(all)      mean=%.6g  std=%.6g  [%d groups]\n', ...
        mean_SER_all(iS), std_SER_all(iS), n_grp);
    fprintf('  SER(baseline) mean=%.6g  std=%.6g  [%d groups]\n\n', ...
        mean_SER_s0(iS), std_SER_s0(iS), n_grp);

end

%% 결과 저장
result.snr = SNR_list;

result.BER   = BER;
result.PER   = PER;
result.S_BER = S_BER;
result.S_PER = S_PER;

result.p1     = P1_snr;
result.p2     = P2_snr;
result.p1_ber = BER_P1_cnt;
result.p1_per = PER_P1_cnt;
result.p2_ber = BER_P2_cnt;
result.p2_per = PER_P2_cnt;

result.cnt_fail    = m0_cnt;
result.cnt_success = m1_cnt + m2_cnt;
result.cnt_suc_CDC = m1_cnt;
result.cnt_suc_MDC = m2_cnt;

result.RXR        = RXR;
result.BER_sys_s0 = BER_sys_s0;
result.PER_sys_s0 = PER_sys_s0;

% SER 결과
result.SER_group_size = GROUP_SIZE;          % 30
result.SER_n_groups   = n_grp;               % 33

result.SER_groups_all = SER_groups_all;      % nS × 33  (일반)
result.mean_SER_all   = mean_SER_all;        % 1  × nS
result.std_SER_all    = std_SER_all;

result.SER_groups_s0  = SER_groups_s0;       % nS × 33  (baseline)
result.mean_SER_s0    = mean_SER_s0;         % 1  × nS
result.std_SER_s0     = std_SER_s0;

save(sprintf('result-%s.mat', datestr(datetime('now'), 'yymmdd-HHMM')), 'result');

clearvars -except result
