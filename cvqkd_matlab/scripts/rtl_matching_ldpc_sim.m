% rtl_matching_ldpc_sim.m - MATLAB simulation matching RTL exactly
% This implements the exact same algorithm as the RTL:
% - Layered min-sum with Z=384, W=16, alpha=0.75
% - Same barrel shifter convention
% - Same CNU sign accumulation
% - Same VNU processing

clear; clc;

%% Parameters
Z = 384;
W = 16;
N_ROWS = 46;
N_COLS = 68;
MAX_ITER = 1;
ALPHA = 0.75;

%% Load BG_ROM from RTL package
bg_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_alice\rtl\bg_rom_pkg.sv';
bg_content = fileread(bg_file);
bg_lines = regexp(bg_content, "'\{([^\}]+)\}", 'tokens');
BG_ROM = zeros(N_ROWS, N_COLS, 'int16');
for r = 1:N_ROWS
    % Extract numbers using regexp to handle commas and spaces
    nums = regexp(bg_lines{r}{1}, '-?\d+', 'match');
    for c = 1:min(length(nums), N_COLS)
        BG_ROM(r, c) = int16(str2double(nums{c}));
    end
end
fprintf('Loaded BG_ROM: %d x %d\n', N_ROWS, N_COLS);

%% Load test vectors (u_bits.txt)
u_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\u_bits.txt';
fid = fopen(u_file, 'r');
llr_input = zeros(N_COLS, Z, 'int16');
for col = 0:N_COLS-1
    line = fgetl(fid);
    for v = 0:Z-1
        % 8-bit sign-magnitude: bit 0 = sign, bits 1-7 = magnitude
        sm_sign = line(v*8 + 1) - '0';
        sm_mag = 0;
        for b = 1:7
            sm_mag = sm_mag * 2 + (line(v*8 + 1 + b) - '0');
        end
        % Convert to 16-bit sign-magnitude (same as RTL)
        if sm_sign
            llr_input(col+1, v+1) = int16(-sm_mag);
        else
            llr_input(col+1, v+1) = int16(sm_mag);
        end
    end
end
fclose(fid);
fprintf('Loaded LLR input: %d x %d\n', N_COLS, Z);

%% Load syndrome
syn_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\expected_syndrome.txt';
syndrome = zeros(N_ROWS, Z, 'int8');
fid = fopen(syn_file, 'r');
for r = 0:N_ROWS-1
    line = fgetl(fid);
    for v = 0:Z-1
        syndrome(r+1, v+1) = int8(line(v+1) - '0');
    end
end
fclose(fid);
fprintf('Loaded syndrome: %d x %d\n', N_ROWS, Z);

%% Initialize memories (same as RTL)
% P_mem: initialized with LLR input (column-major)
P_mem = zeros(Z, N_COLS, 'int16');
for col = 1:N_COLS
    for v = 1:Z
        P_mem(v, col) = llr_input(col, v);
    end
end

% R_mem: initialized to zeros (same as RTL BRAM default)
R_mem = zeros(Z, N_ROWS, N_COLS, 'int16');

%% Helper functions matching RTL exactly

% Barrel shifter: data_out[i] = data_in[(i + shift) % Z]
function out = barrel_shift(in_data, shift_val, Z)
    out = zeros(size(in_data));
    for i = 0:Z-1
        src_idx = mod(i + shift_val, Z) + 1;
        out(i+1) = in_data(src_idx);
    end
end

% VNU processor: Q = P - R_old, P_new = Q + R_new
function [q, p_new] = vnu_process(p, r_old, r_new)
    q = p - r_old;
    p_new = q + r_new;
end

% CNU cell: scaled min-sum with sign accumulation
function [r_new, min1, min2, min1_idx, total_sign] = cnu_process(...
        q_bus, col_idx, syndrome_bit, prev_min1, prev_min2, prev_min1_idx, prev_total_sign, Z, ALPHA)
    
    % Initialize on first column
    if col_idx == 0
        min1 = 32767;  % MAX_MAG for W=16
        min2 = 32767;
        min1_idx = 0;
        total_sign = syndrome_bit;
    else
        min1 = prev_min1;
        min2 = prev_min2;
        min1_idx = prev_min1_idx;
        total_sign = prev_total_sign;
    end
    
    % Process each VNU position
    for i = 0:Z-1
        q_val = q_bus(i+1);
        q_sign = double(q_val < 0);
        q_mag = abs(q_val);
        
        % Update sign accumulation
        total_sign = mod(total_sign + q_sign, 2);
        
        % Update min1/min2
        if q_mag < min1
            min2 = min1;
            min1 = q_mag;
            min1_idx = i;
        elseif q_mag < min2
            min2 = q_mag;
        end
    end
    
    % Compute R_new for each VNU position
    r_new = zeros(Z, 1, 'int16');
    for i = 0:Z-1
        % Select min1 or min2 based on column index
        if col_idx == min1_idx
            raw_mag = min2;
        else
            raw_mag = min1;
        end
        
        % Scaled min-sum: alpha=0.75
        norm_mag = raw_mag - bitshift(raw_mag, -2);
        
        % Sign: total_sign ^ q_sign (extrinsic)
        q_sign = double(q_bus(i+1) < 0);
        r_sign = mod(total_sign + q_sign, 2);
        
        if r_sign
            r_new(i+1) = -int16(norm_mag);
        else
            r_new(i+1) = int16(norm_mag);
        end
    end
end

%% Run RTL-matching simulation
fprintf('\n=== Running RTL-matching simulation ===\n');

for iter = 1:MAX_ITER
    fprintf('Iteration %d\n', iter-1);
    
    for row = 0:N_ROWS-1
        % Get shift value for this row
        % In RTL, shift value is constant for all columns in a row
        shift_val = 0;
        for col = 0:N_COLS-1
            if BG_ROM(row+1, col+1) ~= -1
                shift_val = BG_ROM(row+1, col+1);
                break;
            end
        end
        
        % Forward shift P_mem and R_mem
        P_shifted = barrel_shift(P_mem(:, row+1), shift_val, Z);
        R_shifted = zeros(Z, 1, 'int16');
        for col = 0:N_COLS-1
            if BG_ROM(row+1, col+1) ~= -1
                R_col = barrel_shift(R_mem(:, row+1, col+1), shift_val, Z);
                for v = 1:Z
                    R_shifted(v) = R_shifted(v) + R_col(v);
                end
            end
        end
        
        % Process each column
        for col = 0:N_COLS-1
            if BG_ROM(row+1, col+1) == -1
                continue;
            end
            
            % VNU: Q = P_shifted - R_shifted
            Q_bus = zeros(Z, 1, 'int16');
            for v = 1:Z
                Q_bus(v) = P_shifted(v) - R_shifted(v);
            end
            
            % CNU: scaled min-sum
            [R_new, min1, min2, min1_idx, total_sign] = cnu_process(...
                Q_bus, col, syndrome(row+1, 1), 0, 0, 0, 0, Z, ALPHA);
            
            % VNU: P_new = Q + R_new
            P_new = zeros(Z, 1, 'int16');
            for v = 1:Z
                P_new(v) = Q_bus(v) + R_new(v);
            end
            
            % Inverse shift and write back
            inv_shift = mod(Z - shift_val, Z);
            P_mem(:, row+1) = barrel_shift(P_new, inv_shift, Z);
            R_mem(:, row+1, col+1) = barrel_shift(R_new, inv_shift, Z);
            
            % Trace Row 0, Col 0
            if row == 0 && col == 0
                fprintf('  Col %d: shift=%d, P_shifted[0]=%d, R_shifted[0]=%d, Q[0]=%d, R_new[0]=%d\n', ...
                    col, shift_val, P_shifted(1), R_shifted(1), Q_bus(1), R_new(1));
            end
        end
    end
end

%% Compare with RTL R_mem dump
fprintf('\n=== Comparing with RTL R_mem dump ===\n');
rtl_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_alice\sim\rtl_r_mem_dump.txt';
fid_rtl = fopen(rtl_file, 'r');
rtl_lines = textscan(fid_rtl, '%s');
fclose(fid_rtl);
rtl_lines = rtl_lines{1};

% Parse RTL R_mem
rtl_r = zeros(Z, N_ROWS, N_COLS, 'int16');
idx = 1;
for r = 0:N_ROWS-1
    for c = 0:N_COLS-1
        if BG_ROM(r+1, c+1) == -1
            continue;
        end
        for v = Z-1:-1:0
            if idx > length(rtl_lines)
                break;
            end
            hex_val = hex2dec(rtl_lines{idx});
            if hex_val >= 32768
                rtl_r(v+1, r+1, c+1) = int16(hex_val - 65536);
            else
                rtl_r(v+1, r+1, c+1) = int16(hex_val);
            end
            idx = idx + 1;
        end
    end
end

% Compare
total = 0;
match = 0;
sign_match = 0;
for r = 0:N_ROWS-1
    for c = 0:N_COLS-1
        if BG_ROM(r+1, c+1) == -1
            continue;
        end
        for v = 0:Z-1
            total = total + 1;
            if R_mem(v+1, r+1, c+1) == rtl_r(v+1, r+1, c+1)
                match = match + 1;
            end
            if sign(R_mem(v+1, r+1, c+1)) == sign(rtl_r(v+1, r+1, c+1))
                sign_match = sign_match + 1;
            end
        end
    end
end

fprintf('Total entries: %d\n', total);
fprintf('Exact match: %d (%.2f%%)\n', match, 100*match/total);
fprintf('Sign match: %d (%.2f%%)\n', sign_match, 100*sign_match/total);
