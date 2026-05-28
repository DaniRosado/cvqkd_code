function cfg = get_default_config()
% GET_DEFAULT_CONFIG - Returns default configuration for CV-QKD simulation
%
% OUTPUTS:
%   cfg - Configuration structure with all simulation parameters
%
% STRUCTURE:
%   cfg.frame       - Frame and memory parameters
%   cfg.physical    - Physical channel parameters
%   cfg.adc         - ADC calibration parameters
%   cfg.ldpc        - LDPC decoder parameters
%   cfg.mdr         - Multidimensional reconciliation parameters
%   cfg.fixed_point - Fixed-point conversion constants
%   cfg.paths       - Project directory paths
%   cfg.export      - Export control flags

%% Frame and Memory Parameters
cfg.frame.L_trama = 16;           % Frame length (1 pilot + 15 data)
cfg.frame.N_BOB_DATA = 26112;     % Bob's RAM capacity (data symbols)
cfg.frame.N_SAMPLES = 13056;      % Sacrificed samples for estimation (N_BOB_DATA/2)

%% Physical Channel Parameters
cfg.physical.Ts = 1e-9;           % Symbol time (1 Gbaud)
cfg.physical.T_real = 0.8;        % Fiber transmittance
cfg.physical.xi_real = 0.01;      % Excess quantum noise (SNU)
cfg.physical.V_elec_snu = 0.1;    % Electronic noise (SNU)
cfg.physical.eta_detector = 0.6;  % Photodiode efficiency

% Alice's modulation variance (can be overridden by VA_SNU env variable)
cfg.physical.V_A_snu = 8.0;
env_va = getenv('VA_SNU');
if ~isempty(env_va)
    cfg.physical.V_A_snu = str2double(env_va);
end

%% Phase Noise Parameters
cfg.phase_noise.linewidth_hz = 100e3;     % Laser linewidth (100 kHz)
cfg.phase_noise.acoustic_freq_hz = 500;   % Acoustic vibration frequency
cfg.phase_noise.acoustic_amp = 0.5;       % Acoustic amplitude (rad)

%% ADC Calibration Parameters
cfg.adc.N0_var = 10000;           % Variance for 1 SNU (ADC units²)
cfg.adc.pilot_amp = 20000;        % Strong pilot amplitude (ADC units)

%% LDPC Parameters
cfg.ldpc.Z = 384;                 % Lifting factor
cfg.ldpc.N_rows = 46;             % Base graph rows (mb)
cfg.ldpc.N_cols = 68;             % Base graph columns (nb)
cfg.ldpc.max_iter = 200;          % Maximum decoder iterations
cfg.ldpc.alpha = 0.75;            % Scaled min-sum damping factor
cfg.ldpc.llr_scale = 1.0;         % LLR input scaling
cfg.ldpc.llr_8bit_scale = 48.0;   % 8-bit quantization scale (~3-sigma)

%% Multidimensional Reconciliation Parameters
cfg.mdr.N_dimensions = 8;         % MDR dimensionality
cfg.mdr.symbols_per_block = 4;    % Complex symbols per block (N_dim/2)

%% Fixed-Point Conversion Constants
cfg.fixed_point.Q15 = 2^15;       % Q0.15 format (32768)
cfg.fixed_point.Q16_16 = 2^16;    % Q16.16 format (65536)
cfg.fixed_point.Q31 = 2^31;       % Q0.31 format
cfg.fixed_point.INV_2N2_shift = 45;  % Shift for 1/(2N²) approximation

%% Project Paths (relative to scripts directory)
script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir), script_dir = pwd(); end
root_dir = fileparts(script_dir);  % cvqkd_matlab/
project_root = fileparts(root_dir); % TFG root

cfg.paths.script_dir = script_dir;
cfg.paths.data_dir = fullfile(root_dir, 'data');
cfg.paths.bob_dir = fullfile(project_root, 'cvqkd_bob');
cfg.paths.alice_data_dir = fullfile(project_root, 'cvqkd_alice', 'data');
cfg.paths.alice_sim_dir = fullfile(project_root, 'cvqkd_alice', 'sim');

%% Export Control
cfg.export.enable_vivado = true;   % Export Vivado testbench files
cfg.export.enable_plots = true;    % Generate diagnostic plots

end
