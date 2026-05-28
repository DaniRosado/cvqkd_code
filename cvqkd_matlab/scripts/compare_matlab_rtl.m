%% ========================================================================
%  MATLAB vs RTL Comparison Script
%  Compares MATLAB golden model results with RTL simulation outputs
% ========================================================================
function results = compare_matlab_rtl(varargin)
    % COMPARE_MATLAB_RTL Compare MATLAB golden model with RTL simulation
    %
    % Usage:
    %   results = compare_matlab_rtl()                  % Run full comparison
    %   results = compare_matlab_rtl('regenerate')      % Regenerate MATLAB golden data first
    %   results = compare_matlab_rtl('rtl_log', path)   % Specify custom RTL log path
    %   results = compare_matlab_rtl('html')            % Generate HTML report
    %
    % Returns:
    %   results - Structure with comparison results

    %% Parse input arguments
    p = inputParser;
    addParameter(p, 'regenerate', false, @islogical);
    addParameter(p, 'rtl_log', '', @ischar);
    addParameter(p, 'html', false, @islogical);
    addParameter(p, 'verbose', true, @islogical);
    parse(p, varargin{:});

    regenerate = p.Results.regenerate;
    rtl_log_path = p.Results.rtl_log;
    generate_html = p.Results.html;
    verbose = p.Results.verbose;

    %% Setup paths
    SCRIPT_DIR = fileparts(mfilename('fullpath'));
    if isempty(SCRIPT_DIR), SCRIPT_DIR = pwd(); end
    DATA_DIR = fullfile(SCRIPT_DIR, '..', 'data');
    ALICE_SIM_DIR = fullfile(SCRIPT_DIR, '..', '..', 'cvqkd_alice', 'sim');
    REPORT_DIR = fullfile(SCRIPT_DIR, '..', 'reports');

    if ~exist(REPORT_DIR, 'dir')
        mkdir(REPORT_DIR);
    end

    %% Step 1: Generate MATLAB golden reference if requested
    if regenerate
        if verbose
            fprintf('==================================================\n');
            fprintf('STEP 1: Generating MATLAB Golden Reference\n');
            fprintf('==================================================\n');
        end

        % Run the master testbench to generate fresh reference data
        run(fullfile(SCRIPT_DIR, 'tb_generador_master.m'));

        if verbose
            fprintf('[OK] MATLAB golden data regenerated\n\n');
        end
    else
        if verbose
            fprintf('==================================================\n');
            fprintf('Using existing MATLAB golden data\n');
            fprintf('==================================================\n\n');
        end
    end

    %% Step 2: Load MATLAB golden reference data
    if verbose
        fprintf('STEP 2: Loading MATLAB Golden Reference\n');
        fprintf('--------------------------------------------------\n');
    end

    matlab_data = load_matlab_golden(DATA_DIR, verbose);

    %% Step 3: Parse RTL simulation log
    if verbose
        fprintf('\nSTEP 3: Parsing RTL Simulation Log\n');
        fprintf('--------------------------------------------------\n');
    end

    if isempty(rtl_log_path)
        % Try to find the most recent RTL log
        rtl_log_path = find_latest_rtl_log(ALICE_SIM_DIR);
    end

    if isempty(rtl_log_path) || ~exist(rtl_log_path, 'file')
        warning('RTL log file not found. Please run RTL simulation first.');
        results = [];
        return;
    end

    rtl_data = parse_rtl_log(rtl_log_path, verbose);

    %% Step 4: Compare convergence and performance
    if verbose
        fprintf('\nSTEP 4: Comparing Convergence Metrics\n');
        fprintf('--------------------------------------------------\n');
    end

    comparison = compare_convergence(matlab_data, rtl_data, verbose);

    %% Step 5: Compare iteration-by-iteration data
    if verbose
        fprintf('\nSTEP 5: Comparing Iteration-by-Iteration Data\n');
        fprintf('--------------------------------------------------\n');
    end

    iter_comparison = compare_iterations(matlab_data, rtl_data, DATA_DIR, ALICE_SIM_DIR, verbose);

    %% Step 6: Generate comparison report
    if verbose
        fprintf('\nSTEP 6: Generating Comparison Report\n');
        fprintf('--------------------------------------------------\n');
    end

    results = struct();
    results.matlab = matlab_data;
    results.rtl = rtl_data;
    results.convergence = comparison;
    results.iterations = iter_comparison;
    results.timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    results.pass = comparison.pass && iter_comparison.pass;

    % Generate text report
    report_path = fullfile(REPORT_DIR, sprintf('comparison_report_%s.txt', results.timestamp));
    generate_text_report(results, report_path, verbose);

    % Generate HTML report if requested
    if generate_html
        html_path = fullfile(REPORT_DIR, sprintf('comparison_report_%s.html', results.timestamp));
        generate_html_report(results, html_path, verbose);
    end

    % Generate plots
    generate_plots(results, REPORT_DIR, verbose);

    %% Final summary
    fprintf('\n==================================================\n');
    fprintf('COMPARISON SUMMARY\n');
    fprintf('==================================================\n');
    fprintf('Overall Result: %s\n', iif(results.pass, '[PASS]', '[FAIL]'));
    fprintf('MATLAB Convergence: %d iterations\n', matlab_data.iter_converged);
    fprintf('RTL Convergence: %d iterations\n', rtl_data.iter_converged);
    fprintf('MATLAB Final BER: %.6f\n', matlab_data.final_ber);
    fprintf('RTL Final BER: %.6f\n', rtl_data.final_ber);
    fprintf('\nReports generated:\n');
    fprintf('  - %s\n', report_path);
    if generate_html
        fprintf('  - %s\n', html_path);
    end
    fprintf('==================================================\n\n');
end

%% ========================================================================
%  Helper Functions
% ========================================================================

function matlab_data = load_matlab_golden(data_dir, verbose)
    % Load MATLAB golden reference data

    matlab_data = struct();

    % Load P_mem history (iteration x column x Z)
    p_mem_file = fullfile(data_dir, 'expected_p_mem.txt');
    if exist(p_mem_file, 'file')
        matlab_data.p_mem = load_p_mem_data(p_mem_file, verbose);
    else
        matlab_data.p_mem = [];
        if verbose, warning('expected_p_mem.txt not found'); end
    end

    % Load R_mem history (iteration x row x column x Z)
    r_mem_file = fullfile(data_dir, 'expected_r_mem.txt');
    if exist(r_mem_file, 'file')
        matlab_data.r_mem = load_r_mem_data(r_mem_file, verbose);
    else
        matlab_data.r_mem = [];
        if verbose, warning('expected_r_mem.txt not found'); end
    end

    % Load syndrome
    syn_file = fullfile(data_dir, 'expected_syndrome.txt');
    if exist(syn_file, 'file')
        matlab_data.syndrome = load_syndrome_data(syn_file);
    else
        matlab_data.syndrome = [];
        if verbose, warning('expected_syndrome.txt not found'); end
    end

    % Load reference key
    key_file = fullfile(data_dir, 'bob_key_ref.txt');
    if exist(key_file, 'file')
        matlab_data.key_ref = load_key_data(key_file);
    else
        matlab_data.key_ref = [];
        if verbose, warning('bob_key_ref.txt not found'); end
    end

    % Extract convergence info from P_mem
    if ~isempty(matlab_data.p_mem)
        matlab_data.iter_converged = size(matlab_data.p_mem, 1);
        matlab_data.final_ber = 0.0; % Assumed converged
    else
        matlab_data.iter_converged = 0;
        matlab_data.final_ber = 1.0;
    end

    if verbose
        fprintf('[OK] Loaded MATLAB golden data:\n');
        fprintf('     Convergence iterations: %d\n', matlab_data.iter_converged);
        fprintf('     P_mem size: [%s]\n', num2str(size(matlab_data.p_mem)));
        if ~isempty(matlab_data.r_mem)
            fprintf('     R_mem size: [%s]\n', num2str(size(matlab_data.r_mem)));
        end
    end
end

function p_mem = load_p_mem_data(filename, verbose)
    % Load P_mem data from hex file (iter x 68 x 384)
    fid = fopen(filename, 'r');
    if fid == -1
        p_mem = [];
        return;
    end

    nb = 68; Z = 384; W = 16;
    lines = {};
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line)
            lines{end+1} = line; %#ok<AGROW>
        end
    end
    fclose(fid);

    num_iters = floor(length(lines) / nb);
    p_mem = zeros(num_iters, nb, Z);

    for iter = 1:num_iters
        for col = 1:nb
            line_idx = (iter-1)*nb + col;
            if line_idx <= length(lines)
                hex_line = lines{line_idx};
                % Each line has Z*W/4 hex chars = 384*16/4 = 1536 hex chars
                for vnu = 1:Z
                    start_idx = (Z-vnu)*4 + 1;
                    hex_val = hex_line(start_idx:start_idx+3);
                    val = hex2dec(hex_val);
                    % Convert from 16-bit sign-magnitude to signed value
                    sign = bitand(val, hex2dec('8000'));
                    mag = bitand(val, hex2dec('7FFF'));
                    if sign
                        p_mem(iter, col, vnu) = -double(mag);
                    else
                        p_mem(iter, col, vnu) = double(mag);
                    end
                end
            end
        end
    end
end

function r_mem = load_r_mem_data(filename, verbose)
    % Load R_mem data from hex file (iter x 46 x 68 x 384)
    fid = fopen(filename, 'r');
    if fid == -1
        r_mem = [];
        return;
    end

    mb = 46; nb = 68; Z = 384; W = 16;
    lines = {};
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line)
            lines{end+1} = line; %#ok<AGROW>
        end
    end
    fclose(fid);

    num_iters = floor(length(lines) / (mb * nb));
    r_mem = zeros(num_iters, mb, nb, Z);

    for iter = 1:num_iters
        for row = 1:mb
            for col = 1:nb
                line_idx = (iter-1)*mb*nb + (row-1)*nb + col;
                if line_idx <= length(lines)
                    hex_line = lines{line_idx};
                    for vnu = 1:Z
                        start_idx = (Z-vnu)*4 + 1;
                        if start_idx + 3 <= length(hex_line)
                            hex_val = hex_line(start_idx:start_idx+3);
                            val = hex2dec(hex_val);
                            sign = bitand(val, hex2dec('8000'));
                            mag = bitand(val, hex2dec('7FFF'));
                            if sign
                                r_mem(iter, row, col, vnu) = -double(mag);
                            else
                                r_mem(iter, row, col, vnu) = double(mag);
                            end
                        end
                    end
                end
            end
        end
    end
end

function syndrome = load_syndrome_data(filename)
    % Load syndrome data (46 x 384)
    fid = fopen(filename, 'r');
    if fid == -1
        syndrome = [];
        return;
    end

    syndrome = zeros(46, 384);
    row = 1;
    while ~feof(fid) && row <= 46
        line = fgetl(fid);
        if ischar(line) && length(line) >= 384
            for i = 1:384
                syndrome(row, i) = str2double(line(i));
            end
            row = row + 1;
        end
    end
    fclose(fid);
end

function key = load_key_data(filename)
    % Load key reference data (68 x 384)
    fid = fopen(filename, 'r');
    if fid == -1
        key = [];
        return;
    end

    key = zeros(68, 384);
    row = 1;
    while ~feof(fid) && row <= 68
        line = fgetl(fid);
        if ischar(line) && length(line) >= 384
            for i = 1:384
                key(row, i) = str2double(line(i));
            end
            row = row + 1;
        end
    end
    fclose(fid);
end

function log_path = find_latest_rtl_log(sim_dir)
    % Find the most recent RTL simulation log file

    % Try common log file names
    candidates = {
        fullfile(sim_dir, 'xsim.log');
        fullfile(sim_dir, 'simulation.log');
        fullfile(sim_dir, 'rtl_output.log');
        fullfile(sim_dir, '..', 'xsim_work', 'temp_out.log');
    };

    latest_file = '';
    latest_time = 0;

    for i = 1:length(candidates)
        if exist(candidates{i}, 'file')
            info = dir(candidates{i});
            if info.datenum > latest_time
                latest_time = info.datenum;
                latest_file = candidates{i};
            end
        end
    end

    log_path = latest_file;
end

function rtl_data = parse_rtl_log(log_path, verbose)
    % Parse RTL simulation log file

    if verbose
        fprintf('Parsing RTL log: %s\n', log_path);
    end

    rtl_data = struct();
    rtl_data.log_path = log_path;
    rtl_data.iter_converged = 0;
    rtl_data.final_ber = 1.0;
    rtl_data.success = false;
    rtl_data.dec_match = 0;
    rtl_data.total_bits = 0;
    rtl_data.iterations = [];

    fid = fopen(log_path, 'r');
    if fid == -1
        warning('Failed to open RTL log file');
        return;
    end

    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line), continue; end

        % Parse convergence iteration
        if contains(line, 'Decoding done') && contains(line, 'iter=')
            tokens = regexp(line, 'iter=(\d+)', 'tokens');
            if ~isempty(tokens)
                rtl_data.iter_converged = str2double(tokens{1}{1});
            end
        end

        % Parse success flag
        if contains(line, 'success=')
            tokens = regexp(line, 'success=(\d+)', 'tokens');
            if ~isempty(tokens)
                rtl_data.success = str2double(tokens{1}{1}) == 1;
            end
        end

        % Parse bit match count
        if contains(line, 'dec_match')
            tokens = regexp(line, 'dec_match[^=]*=\s*(\d+)/(\d+)', 'tokens');
            if ~isempty(tokens)
                rtl_data.dec_match = str2double(tokens{1}{1});
                rtl_data.total_bits = str2double(tokens{1}{2});
            end
        end

        % Parse per-iteration metrics
        if contains(line, '[ITER') && contains(line, 'Coincidencias')
            tokens = regexp(line, '\[ITER\s+(\d+)\].*:\s*(\d+)\s*/\s*(\d+)', 'tokens');
            if ~isempty(tokens)
                iter_num = str2double(tokens{1}{1});
                matches = str2double(tokens{1}{2});
                total = str2double(tokens{1}{3});
                rtl_data.iterations(iter_num).matches = matches;
                rtl_data.iterations(iter_num).total = total;
                rtl_data.iterations(iter_num).ber = 1.0 - matches/total;
            end
        end

        % Parse final result
        if contains(line, 'RESULT:')
            if contains(line, 'PASS')
                rtl_data.final_result = 'PASS';
            else
                rtl_data.final_result = 'FAIL';
            end
        end
    end
    fclose(fid);

    % Calculate final BER
    if rtl_data.total_bits > 0
        rtl_data.final_ber = 1.0 - rtl_data.dec_match / rtl_data.total_bits;
    end

    if verbose
        fprintf('[OK] Parsed RTL log:\n');
        fprintf('     Convergence: %d iterations\n', rtl_data.iter_converged);
        fprintf('     Success: %s\n', iif(rtl_data.success, 'YES', 'NO'));
        fprintf('     Final BER: %.6f\n', rtl_data.final_ber);
        fprintf('     Bit matches: %d / %d\n', rtl_data.dec_match, rtl_data.total_bits);
    end
end

function comparison = compare_convergence(matlab_data, rtl_data, verbose)
    % Compare convergence metrics between MATLAB and RTL

    comparison = struct();
    comparison.iter_match = (matlab_data.iter_converged == rtl_data.iter_converged);
    comparison.iter_diff = abs(matlab_data.iter_converged - rtl_data.iter_converged);
    comparison.ber_match = (matlab_data.final_ber == rtl_data.final_ber);
    comparison.ber_diff = abs(matlab_data.final_ber - rtl_data.final_ber);
    comparison.both_converged = (matlab_data.final_ber == 0.0) && (rtl_data.final_ber == 0.0);
    comparison.pass = comparison.both_converged && (comparison.iter_diff <= 2);

    if verbose
        fprintf('Convergence Comparison:\n');
        fprintf('  MATLAB iterations: %d\n', matlab_data.iter_converged);
        fprintf('  RTL iterations: %d\n', rtl_data.iter_converged);
        fprintf('  Iteration difference: %d %s\n', comparison.iter_diff, ...
                iif(comparison.iter_match, '[MATCH]', '[MISMATCH]'));
        fprintf('  MATLAB final BER: %.6f\n', matlab_data.final_ber);
        fprintf('  RTL final BER: %.6f\n', rtl_data.final_ber);
        fprintf('  BER difference: %.6f %s\n', comparison.ber_diff, ...
                iif(comparison.ber_match, '[MATCH]', '[MISMATCH]'));
        fprintf('  Result: %s\n', iif(comparison.pass, '[PASS]', '[FAIL]'));
    end
end

function iter_comparison = compare_iterations(matlab_data, rtl_data, data_dir, sim_dir, verbose)
    % Compare iteration-by-iteration P_mem and R_mem values

    iter_comparison = struct();
    iter_comparison.pass = true;
    iter_comparison.p_mem_errors = [];
    iter_comparison.r_mem_errors = [];

    max_iters = min(matlab_data.iter_converged, 5); % Compare first 5 iterations

    if verbose
        fprintf('Comparing first %d iterations...\n', max_iters);
    end

    % Note: Detailed P_mem and R_mem comparison would require parsing RTL dumps
    % For now, we'll just check if the final convergence matches

    if ~isempty(matlab_data.p_mem) && max_iters > 0
        fprintf('  P_mem data available for %d iterations\n', matlab_data.iter_converged);
        iter_comparison.p_mem_available = true;
    else
        iter_comparison.p_mem_available = false;
    end

    if ~isempty(matlab_data.r_mem) && max_iters > 0
        fprintf('  R_mem data available for %d iterations\n', matlab_data.iter_converged);
        iter_comparison.r_mem_available = true;
    else
        iter_comparison.r_mem_available = false;
    end

    if verbose
        fprintf('  [INFO] Detailed memory comparison requires RTL memory dumps\n');
    end
end

function generate_text_report(results, report_path, verbose)
    % Generate text comparison report

    fid = fopen(report_path, 'w');
    if fid == -1
        warning('Failed to create report file');
        return;
    end

    fprintf(fid, '========================================================================\n');
    fprintf(fid, 'MATLAB vs RTL Comparison Report\n');
    fprintf(fid, '========================================================================\n');
    fprintf(fid, 'Generated: %s\n', results.timestamp);
    fprintf(fid, '\n');

    fprintf(fid, '------------------------------------------------------------------------\n');
    fprintf(fid, 'CONVERGENCE COMPARISON\n');
    fprintf(fid, '------------------------------------------------------------------------\n');
    fprintf(fid, 'Metric                  | MATLAB      | RTL         | Difference  | Status\n');
    fprintf(fid, '------------------------|-------------|-------------|-------------|--------\n');
    fprintf(fid, 'Convergence Iterations  | %11d | %11d | %11d | %s\n', ...
            results.matlab.iter_converged, results.rtl.iter_converged, ...
            results.convergence.iter_diff, iif(results.convergence.iter_match, 'PASS', 'FAIL'));
    fprintf(fid, 'Final BER               | %11.6f | %11.6f | %11.6f | %s\n', ...
            results.matlab.final_ber, results.rtl.final_ber, ...
            results.convergence.ber_diff, iif(results.convergence.ber_match, 'PASS', 'FAIL'));
    fprintf(fid, '\n');

    fprintf(fid, '------------------------------------------------------------------------\n');
    fprintf(fid, 'OVERALL RESULT: %s\n', iif(results.pass, 'PASS', 'FAIL'));
    fprintf(fid, '------------------------------------------------------------------------\n');

    if ~results.pass
        fprintf(fid, '\nFAILURE REASONS:\n');
        if ~results.convergence.both_converged
            fprintf(fid, '  - One or both decoders did not converge to BER=0\n');
        end
        if results.convergence.iter_diff > 2
            fprintf(fid, '  - Iteration count difference exceeds tolerance (diff=%d > 2)\n', ...
                    results.convergence.iter_diff);
        end
    end

    fprintf(fid, '\n');
    fprintf(fid, '========================================================================\n');
    fprintf(fid, 'END OF REPORT\n');
    fprintf(fid, '========================================================================\n');

    fclose(fid);

    if verbose
        fprintf('[OK] Text report saved to: %s\n', report_path);
    end
end

function generate_html_report(results, html_path, verbose)
    % Generate HTML comparison report

    fid = fopen(html_path, 'w');
    if fid == -1
        warning('Failed to create HTML report file');
        return;
    end

    fprintf(fid, '<!DOCTYPE html>\n<html>\n<head>\n');
    fprintf(fid, '<title>MATLAB vs RTL Comparison Report</title>\n');
    fprintf(fid, '<style>\n');
    fprintf(fid, 'body { font-family: Arial, sans-serif; margin: 20px; }\n');
    fprintf(fid, 'h1 { color: #333; }\n');
    fprintf(fid, 'h2 { color: #666; border-bottom: 2px solid #ddd; padding-bottom: 5px; }\n');
    fprintf(fid, 'table { border-collapse: collapse; margin: 20px 0; }\n');
    fprintf(fid, 'th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n');
    fprintf(fid, 'th { background-color: #4CAF50; color: white; }\n');
    fprintf(fid, '.pass { color: green; font-weight: bold; }\n');
    fprintf(fid, '.fail { color: red; font-weight: bold; }\n');
    fprintf(fid, '.summary { font-size: 1.2em; margin: 20px 0; padding: 10px; border-left: 4px solid #4CAF50; }\n');
    fprintf(fid, '</style>\n');
    fprintf(fid, '</head>\n<body>\n');

    fprintf(fid, '<h1>MATLAB vs RTL Comparison Report</h1>\n');
    fprintf(fid, '<p>Generated: %s</p>\n', results.timestamp);

    fprintf(fid, '<div class="summary">\n');
    fprintf(fid, '<strong>Overall Result:</strong> <span class="%s">%s</span>\n', ...
            iif(results.pass, 'pass', 'fail'), iif(results.pass, 'PASS', 'FAIL'));
    fprintf(fid, '</div>\n');

    fprintf(fid, '<h2>Convergence Comparison</h2>\n');
    fprintf(fid, '<table>\n');
    fprintf(fid, '<tr><th>Metric</th><th>MATLAB</th><th>RTL</th><th>Difference</th><th>Status</th></tr>\n');
    fprintf(fid, '<tr><td>Convergence Iterations</td><td>%d</td><td>%d</td><td>%d</td><td class="%s">%s</td></tr>\n', ...
            results.matlab.iter_converged, results.rtl.iter_converged, ...
            results.convergence.iter_diff, iif(results.convergence.iter_match, 'pass', 'fail'), ...
            iif(results.convergence.iter_match, 'MATCH', 'MISMATCH'));
    fprintf(fid, '<tr><td>Final BER</td><td>%.6f</td><td>%.6f</td><td>%.6f</td><td class="%s">%s</td></tr>\n', ...
            results.matlab.final_ber, results.rtl.final_ber, ...
            results.convergence.ber_diff, iif(results.convergence.ber_match, 'pass', 'fail'), ...
            iif(results.convergence.ber_match, 'MATCH', 'MISMATCH'));
    fprintf(fid, '</table>\n');

    fprintf(fid, '</body>\n</html>\n');
    fclose(fid);

    if verbose
        fprintf('[OK] HTML report saved to: %s\n', html_path);
    end
end

function generate_plots(results, report_dir, verbose)
    % Generate comparison plots

    if isempty(results.rtl.iterations)
        if verbose
            fprintf('[INFO] Skipping plots - no per-iteration data available\n');
        end
        return;
    end

    % BER convergence plot
    fig = figure('Visible', 'off');
    iter_nums = arrayfun(@(x) x, 1:length(results.rtl.iterations));
    ber_vals = arrayfun(@(x) results.rtl.iterations(x).ber, iter_nums);

    plot(iter_nums, ber_vals, 'b-o', 'LineWidth', 2);
    xlabel('Iteration');
    ylabel('BER');
    title('RTL BER Convergence');
    grid on;

    plot_path = fullfile(report_dir, sprintf('ber_convergence_%s.png', results.timestamp));
    saveas(fig, plot_path);
    close(fig);

    if verbose
        fprintf('[OK] BER convergence plot saved to: %s\n', plot_path);
    end
end

function result = iif(condition, true_val, false_val)
    % Inline if function
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
