% =========================================================================
% Helper Script to Run CoulombCounting.m
% This script sets up the required inputs and then runs CoulombCounting.m
% =========================================================================

%% Option 1: Use Michigan Race Data (convert to power profile)
% Load Michigan race data
fprintf('Loading Michigan race data...\n');
data = readtable('mich_endurance_combined_data.csv');
time_raw = table2array(data(:,1));      % Time (s)
V_pack_raw = table2array(data(:,2));    % Pack Voltage (V)
I_pack_raw = table2array(data(:,3));    % Pack Current (A)

% Remove NaN values
valid = ~(isnan(time_raw) | isnan(V_pack_raw) | isnan(I_pack_raw));
time_raw = time_raw(valid);
V_pack_raw = V_pack_raw(valid);
I_pack_raw = I_pack_raw(valid);

% Battery configuration (from CoulombCounting.m)
Ns = 4;          % cells in series
Np = 8;          % parallel strings

% Convert to cell-level
V_cell_raw = V_pack_raw / Ns;
I_cell_raw = I_pack_raw / Np;

% Calculate pack power from voltage and current
% Power = Voltage × Current
P_pack = V_pack_raw .* I_pack_raw;

% Create power_vs_time matrix [time, power]
power_vs_time = [time_raw, P_pack];

% Subsample if data is too large (optional - for faster execution)
% Uncomment the next 2 lines if you want to use only every Nth point
% subsample = 100;  % Use every 100th point
% power_vs_time = power_vs_time(1:subsample:end, :);

fprintf('Created power_vs_time: %d data points\n', length(power_vs_time));

%% Option 2: Create Custom SOC-OCV Lookup Table
% Using the same lookup table from BatterySOCEstimationData.m
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];  % SOC fractions
OCV_vec = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];  % OCV (V)

% Create SOC-OCV lookup table [SOC%, OCV]
soc_ocv_lut = [SOC_vec' * 100, OCV_vec'];

fprintf('Created soc_ocv_lut: %d data points\n', length(soc_ocv_lut));

%% Verify inputs
fprintf('\nVerifying inputs for CoulombCounting.m...\n');
fprintf('  power_vs_time size: %d x %d\n', size(power_vs_time, 1), size(power_vs_time, 2));
fprintf('  soc_ocv_lut size: %d x %d\n', size(soc_ocv_lut, 1), size(soc_ocv_lut, 2));
fprintf('  Time range: %.2f to %.2f seconds\n', min(power_vs_time(:,1)), max(power_vs_time(:,1)));
fprintf('  Power range: %.2f to %.2f W\n', min(power_vs_time(:,2)), max(power_vs_time(:,2)));

%% Run CoulombCounting.m
fprintf('\nRunning CoulombCounting.m...\n');
fprintf('========================================================\n');
CoulombCounting

fprintf('\n========================================================\n');
fprintf('CoulombCounting.m completed!\n');
fprintf('Check the generated plots and workspace variables:\n');
fprintf('  - lvbatt_voltage_vs_time\n');
fprintf('  - lvbatt_current_vs_time\n');
fprintf('  - SOC_vs_time\n');

