function export_vivado_testbenches(cfg, P_A_int, Q_A_int, P_B_int, Q_B_int, ...
    P_A_sac, Q_A_sac, punteros, params_fixed, phase_est, idx_datos, ...
    llr_8bit, scale_8bit, key_bits_tx, syndrome_target, mem_history, ...
    LLR_all, bits_bob_all, bg_matrix)
% EXPORT_VIVADO_TESTBENCHES - Exports all testbench files for Vivado simulation
%
% This function generates all .txt files needed for RTL verification

%% File Paths
data_dir = cfg.paths.data_dir;
alice_data = cfg.paths.alice_data_dir;
alice_sim = cfg.paths.alice_sim_dir;

%% 1. Phase Estimation Data
fprintf('  Exporting phase estimation data...\n');
fase_estimada_datos = phase_est(idx_datos);
fase_est_q15 = int32(round(fase_estimada_datos * cfg.fixed_point.Q15));
export_hex_file(fullfile(data_dir, 'fase_estimada_datos.txt'), fase_est_q15);

%% 2. Pilot Phases
fase_pilotos_raw = phase_est(1:cfg.frame.L_trama:end);
fases_q15 = int32(round(fase_pilotos_raw * cfg.fixed_point.Q15));
export_hex_file(fullfile(data_dir, 'fase_pilotos_raw.txt'), fases_q15);

%% 3. Pointer RAM and Mask
export_hex_file(fullfile(data_dir, 'ptr_ram.txt'), punteros, '%04X');

mascara_sacrificio = zeros(cfg.frame.N_BOB_DATA, 1);
mascara_sacrificio(punteros + 1) = 1;
export_text_file(fullfile(data_dir, 'mask_bit.txt'), mascara_sacrificio, '%d');

%% 4. Bob and Alice RAM Data
fprintf('  Exporting RAM data...\n');
export_complex_ram(fullfile(data_dir, 'bob_ram.txt'), P_B_int, Q_B_int);
export_complex_ram(fullfile(data_dir, 'alice_ram.txt'), P_A_sac, Q_A_sac);
export_complex_ram(fullfile(data_dir, 'alice_full_data.txt'), P_A_int, Q_A_int);

%% 5. Expected LLR Math Results
export_hex_file(fullfile(data_dir, 'expected_llr_math.txt'), [
    int32(params_fixed.T_eta_fp);
    int32(params_fixed.sqrt_T_eta_fp);
    int32(params_fixed.var_B_fp);
    int32(params_fixed.sigma_fp)
]);

%% 6. Bob Random Bits for MDR
bits_flat = bits_bob_all(:);
export_text_file(fullfile(data_dir, 'bob_random_bits.txt'), bits_flat, '%d');

%% 7. Expected M Messages (MDR TX)
fprintf('  Exporting MDR test vectors...\n');
export_mdr_messages(fullfile(data_dir, 'expected_m_messages.txt'), ...
    LLR_all, bits_bob_all, cfg);

%% 8. Expected LLR Results (MDR RX)
export_llr_results(fullfile(data_dir, 'expected_llr_results.txt'), LLR_all, cfg);

%% 9. LDPC Test Vectors
fprintf('  Exporting LDPC test vectors...\n');
export_u_bits(fullfile(data_dir, 'u_bits.txt'), llr_8bit, cfg, alice_data, alice_sim);
export_bob_key_ref(fullfile(data_dir, 'bob_key_ref.txt'), key_bits_tx, cfg, alice_data, alice_sim);
export_expected_syndrome(fullfile(data_dir, 'expected_syndrome.txt'), syndrome_target, cfg, alice_data, alice_sim);

%% 10. P_mem and R_mem History
fprintf('  Exporting P_mem and R_mem history...\n');
export_ldpc_memory_history(fullfile(data_dir, 'expected_p_mem.txt'), ...
    fullfile(data_dir, 'expected_r_mem.txt'), ...
    mem_history, scale_8bit, cfg, alice_sim);

%% 11. CNU Debug Files
fprintf('  Exporting CNU debug vectors...\n');
export_cnu_debug_files(data_dir, alice_sim, llr_8bit, syndrome_target, bg_matrix, scale_8bit, cfg);

fprintf('  All export files generated successfully\n');

end

%% Helper Functions

function export_hex_file(filename, data, format)
if nargin < 3, format = '%08X'; end
fid = fopen(filename, 'w');
if fid == -1, error('Cannot open: %s', filename); end
for i = 1:length(data)
    fprintf(fid, [format '\n'], typecast(data(i), 'uint32'));
end
fclose(fid);
end

function export_text_file(filename, data, format)
fid = fopen(filename, 'w');
if fid == -1, error('Cannot open: %s', filename); end
for i = 1:length(data)
    fprintf(fid, [format '\n'], data(i));
end
fclose(fid);
end

function export_complex_ram(filename, P, Q)
fid = fopen(filename, 'w');
if fid == -1, error('Cannot open: %s', filename); end
for i = 1:length(P)
    fprintf(fid, '%04X%04X\n', typecast(Q(i), 'uint16'), typecast(P(i), 'uint16'));
end
fclose(fid);
end

function export_mdr_messages(filename, LLR_all, bits_bob_all, cfg)
% Reconstruct M messages from Bob's side
fid = fopen(filename, 'w');
N_blocks = size(LLR_all, 2);
for blk = 1:N_blocks
    % This would need actual Y values - simplified for now
    for dim = 1:cfg.mdr.N_dimensions
        m_q31 = int32(0);  % Placeholder
        fprintf(fid, '%08X\n', typecast(m_q31, 'uint32'));
    end
end
fclose(fid);
end

function export_llr_results(filename, LLR_all, cfg)
fid = fopen(filename, 'w');
for blk = 1:size(LLR_all, 2)
    for dim = 1:cfg.mdr.N_dimensions
        llr_fp = int32(round(LLR_all(dim, blk) * cfg.fixed_point.Q31));
        fprintf(fid, '%08X\n', typecast(llr_fp, 'uint32'));
    end
end
fclose(fid);
end

function export_u_bits(filename, llr_8bit, cfg, alice_data, alice_sim)
Z = cfg.ldpc.Z;
fid = fopen(filename, 'w');
for col = 0:67
    for vnu = Z-1:-1:0
        idx = col * Z + vnu + 1;
        llr_s8 = llr_8bit(idx);
        sm_val = abs(llr_s8);
        if llr_s8 < 0
            sm_val = bitset(sm_val, 8);
        end
        fprintf(fid, '%s', dec2bin(sm_val, 8));
    end
    fprintf(fid, '\n');
end
fclose(fid);
copyfile(filename, fullfile(alice_data, 'u_bits.txt'));
copyfile(filename, fullfile(alice_sim, 'u_bits.txt'));
end

function export_bob_key_ref(filename, key_bits_tx, cfg, alice_data, alice_sim)
Z = cfg.ldpc.Z;
fid = fopen(filename, 'w');
for blk = 0:67
    for bit = 1:Z
        fprintf(fid, '%d', key_bits_tx(blk*Z + bit));
    end
    fprintf(fid, '\n');
end
fclose(fid);
copyfile(filename, fullfile(alice_data, 'bob_key_ref.txt'));
copyfile(filename, fullfile(alice_sim, 'bob_key_ref.txt'));
end

function export_expected_syndrome(filename, syndrome, cfg, alice_data, alice_sim)
Z = cfg.ldpc.Z;
mb = cfg.ldpc.N_rows;
fid = fopen(filename, 'w');
for row = 0:mb-1
    row_bits = syndrome(row*Z+1 : row*Z+Z);
    for bit = 1:Z
        fprintf(fid, '%d', row_bits(bit));
    end
    fprintf(fid, '\n');
end
fclose(fid);
copyfile(filename, fullfile(alice_data, 'expected_syndrome.txt'));
copyfile(filename, fullfile(alice_sim, 'expected_syndrome.txt'));
end

function export_ldpc_memory_history(p_file, r_file, mem_hist, scale, cfg, alice_sim)
Z = cfg.ldpc.Z;
fid_p = fopen(p_file, 'w');
fid_r = fopen(r_file, 'w');
iter_max = size(mem_hist.p_mem, 1);

for it = 1:iter_max
    for c = 1:cfg.ldpc.N_cols
        for vnu = Z:-1:1
            val_fp = mem_hist.p_mem(it, c, vnu);
            val_s8 = max(-127, min(127, round(val_fp * scale)));
            sm_mag = abs(val_s8);
            sm_sign = uint16(val_s8 < 0);
            val_16 = bitshift(sm_sign, 15) + uint16(sm_mag);
            fprintf(fid_p, '%04X', val_16);
        end
        fprintf(fid_p, '\n');
    end
    for r = 1:cfg.ldpc.N_rows
        for c = 1:cfg.ldpc.N_cols
            for vnu = Z:-1:1
                val_fp = mem_hist.r_mem(it, r, c, vnu);
                val_s8 = max(-127, min(127, round(val_fp * scale)));
                sm_mag = abs(val_s8);
                sm_sign = uint16(val_s8 < 0);
                val_16 = bitshift(sm_sign, 15) + uint16(sm_mag);
                fprintf(fid_r, '%04X', val_16);
            end
            fprintf(fid_r, '\n');
        end
    end
end
fclose(fid_p);
fclose(fid_r);
copyfile(p_file, fullfile(alice_sim, 'expected_p_mem.txt'));
copyfile(r_file, fullfile(alice_sim, 'expected_r_mem.txt'));
end

function export_cnu_debug_files(data_dir, alice_sim, llr_8bit, syndrome, bg_matrix, scale, cfg)
% Export Q, P, R for CNU testbench (row 0, iteration 1)
% This is a simplified version - full implementation needs actual Min-Sum execution
fid_q = fopen(fullfile(data_dir, 'cnu_tb_q_in.txt'), 'w');
fid_p = fopen(fullfile(data_dir, 'cnu_tb_p_in.txt'), 'w');
fid_r = fopen(fullfile(data_dir, 'cnu_tb_r_out.txt'), 'w');

% Placeholder: write zeros for now (actual implementation needs min-sum)
for col = 1:cfg.ldpc.N_cols
    for z = cfg.ldpc.Z:-1:1
        fprintf(fid_q, '%s', dec2bin(0, 16));
        fprintf(fid_p, '%s', dec2bin(0, 16));
        fprintf(fid_r, '%s', dec2bin(0, 16));
    end
    fprintf(fid_q, '\n');
    fprintf(fid_p, '\n');
    fprintf(fid_r, '\n');
end

fclose(fid_q);
fclose(fid_p);
fclose(fid_r);

copyfile(fullfile(data_dir, 'cnu_tb_q_in.txt'), fullfile(alice_sim, 'cnu_tb_q_in.txt'));
copyfile(fullfile(data_dir, 'cnu_tb_p_in.txt'), fullfile(alice_sim, 'cnu_tb_p_in.txt'));
copyfile(fullfile(data_dir, 'cnu_tb_r_out.txt'), fullfile(alice_sim, 'cnu_tb_r_out.txt'));
end
