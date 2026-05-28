%% ========================================================================
%  TEST MODULAR CODE - Quick verification script
% ========================================================================
% This script tests that all modules load and basic functionality works
%
% USAGE:
%   >> test_modular_code

clear; clc;

fprintf('=================================================\n');
fprintf(' Testing Modular CV-QKD Code\n');
fprintf('=================================================\n\n');

%% Add library paths
script_dir = fileparts(mfilename('fullpath'));
lib_dir = fullfile(fileparts(script_dir), 'lib');
addpath(genpath(lib_dir));

%% Test 1: Configuration Loading
fprintf('[1/7] Testing configuration...\n');
try
    cfg = get_default_config();
    assert(cfg.ldpc.Z == 384, 'Config Z mismatch');
    assert(cfg.ldpc.N_rows == 46, 'Config rows mismatch');
    assert(cfg.ldpc.N_cols == 68, 'Config cols mismatch');
    fprintf('  [OK] Configuration loaded correctly\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 2: Phase Noise Generation
fprintf('[2/7] Testing phase noise generation...\n');
try
    N_test = 1000;
    [phase_total, phase_wiener, phase_acoustic] = ...
        generate_phase_noise(N_test, 1e-9, cfg.phase_noise);
    assert(length(phase_total) == N_test, 'Phase length mismatch');
    assert(length(phase_wiener) == N_test, 'Wiener length mismatch');
    assert(length(phase_acoustic) == N_test, 'Acoustic length mismatch');
    fprintf('  [OK] Phase noise generation works\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 3: Channel Model
fprintf('[3/7] Testing channel model...\n');
try
    N_test = 100;
    P_tx = randn(N_test, 1) * 1000;
    Q_tx = randn(N_test, 1) * 1000;
    phase = zeros(N_test, 1);
    [P_rx, Q_rx] = apply_channel_model(P_tx, Q_tx, phase, cfg);
    assert(length(P_rx) == N_test, 'P_rx length mismatch');
    assert(length(Q_rx) == N_test, 'Q_rx length mismatch');
    fprintf('  [OK] Channel model works\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 4: Phase Recovery
fprintf('[4/7] Testing phase recovery...\n');
try
    N_test = 100;
    idx_pilots = 1:10:N_test;
    P_rx = randn(N_test, 1) * 1000;
    Q_rx = randn(N_test, 1) * 1000;
    [phase_est, ~] = recover_phase_pilots(P_rx, Q_rx, idx_pilots, 1:N_test);
    assert(length(phase_est) == N_test, 'Phase estimate length mismatch');
    [P_comp, Q_comp] = compensate_phase(P_rx, Q_rx, phase_est);
    assert(length(P_comp) == N_test, 'Compensated P length mismatch');
    fprintf('  [OK] Phase recovery works\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 5: Parameter Estimation
fprintf('[5/7] Testing parameter estimation...\n');
try
    N_test = 1000;
    P_A = int16(randn(N_test, 1) * 1000);
    Q_A = int16(randn(N_test, 1) * 1000);
    P_B = int16(randn(N_test, 1) * 1000);
    Q_B = int16(randn(N_test, 1) * 1000);
    VarA = 10000;

    params_float = estimate_parameters_float(P_A, Q_A, P_B, Q_B, VarA);
    assert(isfield(params_float, 'var_B'), 'Missing var_B');
    assert(isfield(params_float, 'sigma'), 'Missing sigma');

    params_fixed = estimate_parameters_fixed(P_A, Q_A, P_B, Q_B, VarA, N_test, cfg);
    assert(isfield(params_fixed, 'var_B_fp'), 'Missing var_B_fp');

    fprintf('  [OK] Parameter estimation works\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 6: MDR 8D
fprintf('[6/7] Testing MDR 8D...\n');
try
    N_test = 400;  % Must be multiple of 4 for 8D blocks
    P_A = randn(N_test, 1) * 1000;
    Q_A = randn(N_test, 1) * 1000;
    P_B = randn(N_test, 1) * 1000;
    Q_B = randn(N_test, 1) * 1000;
    sigma = 100.0;

    [LLR_all, bits_bob_all] = compute_mdr_8d(P_A, Q_A, P_B, Q_B, sigma, cfg);
    assert(size(LLR_all, 1) == 8, 'LLR dimension mismatch');
    assert(size(bits_bob_all, 1) == 8, 'Bits dimension mismatch');

    fprintf('  [OK] MDR 8D works\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Test 7: Utility Functions
fprintf('[7/7] Testing utility functions...\n');
try
    test_vals = randn(100, 1) * 40000;
    quantized = quantize_to_int16(test_vals);
    assert(all(quantized >= -32768 & quantized <= 32767), 'Quantization out of range');

    test_llr = randn(100, 1) * 10;
    [llr_8bit, scale] = quantize_llr_to_8bit(test_llr, 48);
    assert(all(llr_8bit >= -127 & llr_8bit <= 127), '8-bit LLR out of range');

    fprintf('  [OK] Utility functions work\n');
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    return;
end

%% Summary
fprintf('\n=================================================\n');
fprintf(' ALL TESTS PASSED!\n');
fprintf('=================================================\n');
fprintf('The modular code is working correctly.\n');
fprintf('You can now run: main_cv_qkd_simulation\n');
fprintf('=================================================\n');
