% compare_rmem.m - Compare RTL R_mem dump with MATLAB expected values
clear; clc;

Z = 384;
N_ROWS = 46;
N_COLS = 68;
W = 16;

% Load 5G BG1 matrix to know which entries are valid
bg_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\BG1.txt';
BG = load(bg_file);

% Load expected R_mem from MATLAB
expected_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_matlab\data\expected_r_mem.txt';
fid = fopen(expected_file, 'r');
expected_lines = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
expected_lines = expected_lines{1};

% Parse expected R_mem (each line is one row, concatenated 4-digit hex values)
expected_r = zeros(N_ROWS, N_COLS, Z, 'int16');
for r = 1:N_ROWS
    line = expected_lines{r};
    % Each entry is 4 hex chars
    for c = 1:N_COLS
        if BG(r, c) == -1
            continue;
        end
        for v = 1:Z
            start_idx = (c-1)*4*Z + (Z-v)*4 + 1;  % Reverse order: Z-1 first
            hex_str = line(start_idx:start_idx+3);
            val = int16(hex2dec(hex_str));
            % Convert from sign-magnitude hex to signed int16
            sign_bit = bitget(uint16(val), 16);
            mag = bitand(uint16(val), 32767);
            if sign_bit
                expected_r(r, c, v) = -int16(mag);
            else
                expected_r(r, c, v) = int16(mag);
            end
        end
    end
end

% Load RTL R_mem dump
rtl_file = 'C:\Users\usser\TFG\cvqkd_code\cvqkd_alice\sim\rtl_r_mem_dump.txt';
fid = fopen(rtl_file, 'r');
rtl_lines = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
rtl_lines = rtl_lines{1};

% Parse RTL R_mem (one 4-digit hex value per line, same order as expected)
rtl_r = zeros(N_ROWS, N_COLS, Z, 'int16');
idx = 1;
for r = 1:N_ROWS
    for c = 1:N_COLS
        if BG(r, c) == -1
            continue;
        end
        for v = Z:-1:1  % RTL dumps in reverse order (Z-1 first)
            if idx > length(rtl_lines)
                break;
            end
            hex_str = rtl_lines{idx};
            val = int16(hex2dec(hex_str));
            sign_bit = bitget(uint16(val), 16);
            mag = bitand(uint16(val), 32767);
            if sign_bit
                rtl_r(r, c, v) = -int16(mag);
            else
                rtl_r(r, c, v) = int16(mag);
            end
            idx = idx + 1;
        end
    end
end

% Compare
total_entries = 0;
sign_match = 0;
mag_match = 0;
both_match = 0;
sign_mismatch = 0;
mag_mismatch = 0;

for r = 1:N_ROWS
    for c = 1:N_COLS
        if BG(r, c) == -1
            continue;
        end
        for v = 1:Z
            total_entries = total_entries + 1;
            exp_val = expected_r(r, c, v);
            rtl_val = rtl_r(r, c, v);
            
            exp_sign = sign(exp_val);
            rtl_sign = sign(rtl_val);
            exp_mag = abs(exp_val);
            rtl_mag = abs(rtl_val);
            
            if exp_sign == rtl_sign
                sign_match = sign_match + 1;
            else
                sign_mismatch = sign_mismatch + 1;
            end
            
            if exp_mag == rtl_mag
                mag_match = mag_match + 1;
            else
                mag_mismatch = mag_mismatch + 1;
            end
            
            if exp_val == rtl_val
                both_match = both_match + 1;
            end
        end
    end
end

fprintf('\n=== R_mem Comparison Results ===\n');
fprintf('Total entries: %d\n', total_entries);
fprintf('Sign match: %d (%.2f%%)\n', sign_match, 100*sign_match/total_entries);
fprintf('Sign mismatch: %d (%.2f%%)\n', sign_mismatch, 100*sign_mismatch/total_entries);
fprintf('Magnitude match: %d (%.2f%%)\n', mag_match, 100*mag_match/total_entries);
fprintf('Magnitude mismatch: %d (%.2f%%)\n', mag_mismatch, 100*mag_mismatch/total_entries);
fprintf('Exact match: %d (%.2f%%)\n', both_match, 100*both_match/total_entries);

% Show first few mismatches
fprintf('\n=== First 20 Mismatches ===\n');
mismatch_count = 0;
for r = 1:N_ROWS
    for c = 1:N_COLS
        if BG(r, c) == -1
            continue;
        end
        for v = 1:Z
            exp_val = expected_r(r, c, v);
            rtl_val = rtl_r(r, c, v);
            
            if exp_val ~= rtl_val
                mismatch_count = mismatch_count + 1;
                fprintf('r=%d, c=%d, v=%d: exp=%d (0x%04X), rtl=%d (0x%04X)\n', ...
                    r, c, v, exp_val, uint16(exp_val), rtl_val, uint16(rtl_val));
                if mismatch_count >= 20
                    break;
                end
            end
        end
        if mismatch_count >= 20
            break;
        end
    end
    if mismatch_count >= 20
        break;
    end
end
