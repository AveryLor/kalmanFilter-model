% =========================================================================
% Kalman-Filter-Only State-of-Charge (SOC) Estimator
% =========================================================================
%
% This script implements a Kalman filter for SOC estimation using the
% Michigan race dataset. It can operate in two modes:
%   - Normal mode: Uses configured Q and R parameters
%   - Match mode: Automatically tunes Q and R to match Coulomb counting
%
% REQUIRED INPUTS:
%   mich_endurance_combined_data.csv : [Time(s), Pack Voltage(V), Pack Current(A)]
%
% ASSUMPTIONS:
%   - Battery pack consists of cells in series (pack voltage / cell voltage)
%   - SOC-OCV relationship is provided or inferred from initial conditions
%   - Temperature effects are captured in the OCV lookup table if available
%   - Current sensor provides pack-level measurements
%   - Sample time is uniform (or data is resampled)
%
% =========================================================================

%% ----- USER-SET PARAMETERS ---------------------------------------------
% Match CoulombCounting.m style parameter block

% Battery configuration (inferred from pack voltage ~513V, adjust as needed)
% Note: Ns may need adjustment based on actual pack configuration
Ns        = 144;        % cells in series (513V / 3.56V nominal ≈ 144, verify)
Np        = 1;          % parallel strings (assumed 1 for pack-level data)
Q_Ah      = 27;         % cell capacity (Ah) - from BatterySOCEstimationData.m
R_ohm     = 0.011;      % internal resistance (Ω) - typical value from data file
V0_pack   = 593;        % initial pack voltage (V) from first data point
Vmin_cell = 2.5;        % Minimum allowed cell voltage (V)

% Kalman Filter Parameters
Ts        = 0.01;       % Sample time (s) - from CSV sampling rate
Q         = 1e-4;              % Process noise covariance (scalar for SOC-only)
R         = 0.7;               % Measurement noise covariance (voltage)
P0        = 1e-5;              % Initial state error covariance (scalar for SOC-only)
SOC0      = 0.8;               % Initial SOC estimate (fraction)

% Match mode and tuning options
matchMode       = true;        % If true, tune Q/R to match Coulomb counting
relyOnVoltage   = true;        % If true, fuse voltage measurements; if false, process model only
rmseTolerance   = 0.005;       % Target RMSE tolerance for match mode (SOC units)

% SOC-OCV Lookup Table (from BatterySOCEstimationData.m, converted to cell-level)
% Using data from V0_mat at T=293K (middle temperature)
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];  % SOC fractions
OCV_vec = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];  % OCV at T=293K (V)
soc_ocv_lut = [SOC_vec' * 100, OCV_vec'];  % [SOC%, OCV] format

% Random seed for reproducibility
rng(42);

%% ----- DATA LOADING & PREPROCESSING -------------------------------------
fprintf('Loading Michigan race dataset...\n');

% Load CSV data
if ~exist('mich_endurance_combined_data.csv', 'file')
    error('mich_endurance_combined_data.csv not found in current directory.');
end

% Load CSV data (assumes header row: Time (s), Pack Voltage (V), Pack Current (A))
data = readtable('mich_endurance_combined_data.csv');
time_raw     = data{:,1};      % Time (s)
V_pack_raw   = data{:,2};      % Pack Voltage (V)
I_pack_raw   = data{:,3};      % Pack Current (A)

% Convert to numeric arrays if readtable returns table
if istable(data)
    time_raw = table2array(data(:,1));
    V_pack_raw = table2array(data(:,2));
    I_pack_raw = table2array(data(:,3));
end

% Handle missing data (NaNs)
valid_idx = ~(isnan(time_raw) | isnan(V_pack_raw) | isnan(I_pack_raw));
time_raw = time_raw(valid_idx);
V_pack_raw = V_pack_raw(valid_idx);
I_pack_raw = I_pack_raw(valid_idx);

% Resample to uniform sampling at Ts if needed
dt_actual = [diff(time_raw); mean(diff(time_raw))];
if std(dt_actual) / mean(dt_actual) > 0.01  % Check if non-uniform
    fprintf('Resampling data to uniform Ts = %.3f s...\n', Ts);
    time = (time_raw(1):Ts:time_raw(end))';
    V_pack = interp1(time_raw, V_pack_raw, time, 'linear', 'extrap');
    I_pack = interp1(time_raw, I_pack_raw, time, 'linear', 'extrap');
else
    time = time_raw;
    V_pack = V_pack_raw;
    I_pack = I_pack_raw;
    Ts = mean(dt_actual);  % Use actual sampling rate
end

N = length(time);

% Convert to cell-level quantities
V_cell = V_pack / Ns;
I_cell = I_pack / Np;

% Initialize based on first measurement
if V0_pack == 0 || isnan(V0_pack)
    V0_cell = V_cell(1);
    V0_pack = V_pack(1);
else
    V0_cell = V0_pack / Ns;
end

fprintf('Data loaded: %d samples, duration: %.1f s\n', N, time(end));
fprintf('Initial pack voltage: %.2f V, cell voltage: %.3f V\n', V0_pack, V0_cell);

%% ----- SOC-OCV LOOKUP TABLE SETUP --------------------------------------
SOC_LUT = soc_ocv_lut(:,1) / 100;  % Convert % → fraction
OCV_LUT = soc_ocv_lut(:,2);

% Create interpolation function
OCVf = @(soc) interp1(SOC_LUT, OCV_LUT, soc, 'linear', 'extrap');

% Invert for SOC from OCV (for initialization)
% Use inverse lookup with linear interpolation
SOC_from_OCV = @(ocv) interp1(OCV_LUT, SOC_LUT, ocv, 'linear', 'extrap');

% Estimate initial SOC from initial voltage
[~, idx0] = min(abs(OCV_LUT - V0_cell));
initialSOC = SOC_LUT(idx0);
fprintf('Initial SOC estimate from OCV: %.3f\n', initialSOC);

%% ----- COULOMB COUNTING REFERENCE (for comparison) ---------------------
fprintf('\nComputing Coulomb counting reference SOC...\n');

% Pre-allocate
SOC_coulomb = zeros(N, 1);
V_cell_coulomb = zeros(N, 1);
Q_C = Q_Ah * 3600;  % Capacity in Coulombs

SOC_coulomb(1) = initialSOC;
V_cell_coulomb(1) = V0_cell;
dt_vec = [0; diff(time)];

% Main Coulomb counting loop (matching CoulombCounting.m style)
for k = 2:N
    % Coulomb counting update
    SOC_coulomb(k) = SOC_coulomb(k-1) - (I_cell(k) * dt_vec(k)) / Q_C;
    SOC_coulomb(k) = max(0, min(1, SOC_coulomb(k)));  % Clamp 0-1
    
    % Voltage model (for reference, not used in coulomb counting)
    OCV_k = OCVf(SOC_coulomb(k));
    V_cell_coulomb(k) = OCV_k - I_cell(k) * R_ohm;
end

fprintf('Coulomb counting completed.\n');

%% ----- KALMAN FILTER SETUP ---------------------------------------------
fprintf('\nSetting up Kalman filter...\n');

% State vector: [SOC; V_polarization]
% Extended state to account for RC dynamics if needed
% For simplicity, start with SOC-only, then extend if needed
use_polarization = false;  % Set to true if using RC model

if use_polarization
    n_states = 2;
    x0 = [SOC0; 0];  % [SOC; V_polarization]
    % Convert to matrix form if needed
    if isscalar(Q)
        Q = [Q 0; 0 1e-4];  % Expand to 2x2 matrix
    end
    if isscalar(P0)
        P0_full = [P0 0; 0 1];  % Expand to 2x2 matrix
    else
        P0_full = P0;
    end
else
    n_states = 1;
    x0 = SOC0;
    P0_full = P0;  % Already scalar
end

% Measurement: terminal voltage (V_terminal = OCV(SOC) - I*R - V_polarization)
% Measurement model: h(x) = OCV(SOC) - I*R (or with polarization if used)

%% ----- KALMAN FILTER IMPLEMENTATION ------------------------------------
fprintf('Running Kalman filter SOC estimation...\n');

% Pre-allocate
SOC_kalman = zeros(N, 1);
P_kalman = zeros(n_states, n_states, N);
x_k = x0;
P_k = P0_full;

SOC_kalman(1) = x0(1);

% Main Kalman filter loop
for k = 2:N
    % === PREDICT STEP ===
    % Process model: SOC(k+1) = SOC(k) - (I*dt) / Q_C
    % This is the same dynamics as Coulomb counting
    if n_states == 1
        % SOC-only model
        F = 1;  % State transition matrix (linear)
        G = -Ts / Q_C;  % Input matrix for current
        
        % Predict state
        x_pred = F * x_k + G * I_cell(k);
        x_pred = max(0, min(1, x_pred));  % Clamp SOC
        
        % Predict covariance
        P_pred = F * P_k * F' + Q;
        
        % Measurement model: V_terminal = OCV(SOC) - I*R
        % Jacobian: dV/dSOC = dOCV/dSOC
        OCV_pred = OCVf(x_pred);
        h_x = OCV_pred - I_cell(k) * R_ohm;
        
        % Compute measurement Jacobian (dOCV/dSOC)
        % Numerical derivative for robustness
        eps = 1e-6;
        OCV_plus = OCVf(x_pred + eps);
        dOCV_dSOC = (OCV_plus - OCV_pred) / eps;
        H = dOCV_dSOC;
        
    else
        % Extended model with polarization
        % TODO: Implement if needed
        error('Polarization model not yet implemented');
    end
    
    % === UPDATE STEP ===
    if relyOnVoltage
        % Measurement: terminal voltage
        z_k = V_cell(k);  % Measured cell voltage
        
        % Measurement residual
        y_k = z_k - h_x;
        
        % Measurement covariance
        S_k = H * P_pred * H' + R;
        
        % Kalman gain
        K_k = P_pred * H' / S_k;
        
        % Update state
        x_k = x_pred + K_k * y_k;
        if n_states == 1
            x_k = max(0, min(1, x_k));  % Clamp SOC
        end
        
        % Update covariance
        P_k = (eye(n_states) - K_k * H) * P_pred;
    else
        % Process model only (like Coulomb counting)
        x_k = x_pred;
        P_k = P_pred;
    end
    
    % Store results
    SOC_kalman(k) = x_k(1);
    P_kalman(:,:,k) = P_k;
end

fprintf('Kalman filter completed.\n');

%% ----- COMPUTE ERRORS & METRICS ----------------------------------------
fprintf('\nComputing comparison metrics...\n');

% Compute RMSE
rmse = sqrt(mean((SOC_kalman - SOC_coulomb).^2));
max_error = max(abs(SOC_kalman - SOC_coulomb));
mean_error = mean(SOC_kalman - SOC_coulomb);

fprintf('Initial RMSE: %.6f\n', rmse);
fprintf('Max error: %.6f\n', max_error);
fprintf('Mean error: %.6f\n', mean_error);

%% ----- MATCH MODE: TUNE Q AND R ----------------------------------------
if matchMode
    fprintf('\n=== MATCH MODE: Tuning Q and R to match Coulomb counting ===\n');
    
    % Use helper function for tuning
    % Check if tune_QR function is available
    tune_QR_exists = exist('tune_QR.m', 'file');
    
    if ~tune_QR_exists
        % Inline tuning if helper not available
        fprintf('Using inline tuning (kalman_utils.m not found)...\n');
        
        % Grid search for Q and R
        % Extract scalar Q if it's a matrix
        if isscalar(Q)
            Q_base = Q;
        else
            Q_base = Q(1,1);
        end
        
        Q_candidates = logspace(log10(Q_base) - 2, log10(Q_base) + 2, 10);
        R_candidates = logspace(log10(R) - 1, log10(R) + 1, 10);
        
        best_rmse = inf;
        best_Q = Q_base;
        best_R = R;
        
        fprintf('Grid search over %d Q x %d R combinations...\n', ...
            length(Q_candidates), length(R_candidates));
        
        for i = 1:length(Q_candidates)
            for j = 1:length(R_candidates)
                Q_test = Q_candidates(i);
                R_test = R_candidates(j);
                
                % Run Kalman filter with test parameters
                [SOC_test, ~] = run_kalman_filter(...
                    time, I_cell, V_cell, OCVf, Q_test, R_test, ...
                    P0_full, x0, Q_C, R_ohm, Ts, relyOnVoltage);
                
                rmse_test = sqrt(mean((SOC_test - SOC_coulomb).^2));
                
                if rmse_test < best_rmse
                    best_rmse = rmse_test;
                    best_Q = Q_test;
                    best_R = R_test;
                end
            end
            
            if mod(i, 2) == 0
                fprintf('  Progress: %d/%d, Best RMSE: %.6f\n', ...
                    i, length(Q_candidates), best_rmse);
            end
        end
        
        Q = best_Q;
        R = best_R;
        
        % Re-run with best parameters
        fprintf('Re-running Kalman filter with tuned parameters...\n');
        [SOC_kalman, P_kalman] = run_kalman_filter(...
            time, I_cell, V_cell, OCVf, Q, R, ...
            P0_full, x0, Q_C, R_ohm, Ts, relyOnVoltage);
        
    else
        % Use helper function
        % Extract scalar Q and R for tuning
        if isscalar(Q)
            Q0_tune = Q;
        else
            Q0_tune = Q(1,1);  % Use first element if matrix
        end
        R0_tune = R;
        
        [Q_tuned, R_tuned, SOC_kalman, P_kalman] = tune_QR(...
            time, I_cell, V_cell, SOC_coulomb, OCVf, ...
            Q0_tune, R0_tune, P0_full, x0, Q_C, R_ohm, Ts, relyOnVoltage, rmseTolerance);
        
        % Update Q and R with tuned values
        Q = Q_tuned;  % Q_tuned is scalar for SOC-only model
        R = R_tuned;
    end
    
    % Recompute metrics
    rmse = sqrt(mean((SOC_kalman - SOC_coulomb).^2));
    max_error = max(abs(SOC_kalman - SOC_coulomb));
    
    fprintf('\nTuning complete:\n');
    fprintf('  Best Q: %.6e\n', Q);
    fprintf('  Best R: %.6e\n', R);
    fprintf('  Final RMSE: %.6f\n', rmse);
    fprintf('  Target tolerance: %.6f\n', rmseTolerance);
    
    if rmse <= rmseTolerance
        fprintf('  ✓ PASS: RMSE within tolerance\n');
        match_result = 'PASS';
    else
        fprintf('  ✗ FAIL: RMSE exceeds tolerance (achieved: %.6f, target: %.6f)\n', ...
            rmse, rmseTolerance);
        match_result = 'FAIL';
    end
else
    match_result = 'N/A';
end

%% ----- PLOTS -----------------------------------------------------------
fprintf('\nGenerating plots...\n');

% Figure 1: SOC Comparison
figure('Name', 'SOC Estimation Comparison', 'Position', [100, 100, 1200, 800]);

subplot(4,1,1);
plot(time, SOC_coulomb * 100, '--', 'LineWidth', 1.8, 'DisplayName', 'Coulomb Counting');
hold on;
plot(time, SOC_kalman * 100, '-', 'LineWidth', 1.8, 'DisplayName', 'Kalman Filter');
hold off;
grid on;
ylabel('SOC (%)');
title('State-of-Charge Estimation Comparison');
legend('Location', 'Best');
xlabel('Time (s)');

% Error plot
subplot(4,1,2);
error_soc = (SOC_kalman - SOC_coulomb) * 100;  % Convert to percentage
plot(time, error_soc, 'r-', 'LineWidth', 1.5);
grid on;
ylabel('SOC Error (%)');
title(sprintf('SOC Error (RMSE: %.4f%%)', rmse * 100));
xlabel('Time (s)');
yline(0, 'k--', 'LineWidth', 1);

% Voltage comparison
subplot(4,1,3);
plot(time, V_cell, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Measured');
hold on;
plot(time, V_cell_coulomb, 'g--', 'LineWidth', 1.5, 'DisplayName', 'Coulomb Model');
hold off;
grid on;
ylabel('Cell Voltage (V)');
title('Cell Voltage');
legend('Location', 'Best');
xlabel('Time (s)');

% Current
subplot(4,1,4);
plot(time, I_cell, 'LineWidth', 1.8);
grid on;
ylabel('Cell Current (A)');
title('Cell Current');
xlabel('Time (s)');

% Figure 2: Detailed SOC comparison (zoomed if needed)
figure('Name', 'SOC Detailed View', 'Position', [150, 150, 1200, 600]);

% Show first 10% of data for detail
n_detail = min(floor(0.1 * N), 5000);
idx_detail = 1:n_detail;

subplot(2,1,1);
plot(time(idx_detail), SOC_coulomb(idx_detail) * 100, '--', ...
    'LineWidth', 2, 'DisplayName', 'Coulomb Counting');
hold on;
plot(time(idx_detail), SOC_kalman(idx_detail) * 100, '-', ...
    'LineWidth', 2, 'DisplayName', 'Kalman Filter');
hold off;
grid on;
ylabel('SOC (%)');
title('SOC Estimation (First 10% of Data)');
legend('Location', 'Best');
xlabel('Time (s)');

subplot(2,1,2);
plot(time(idx_detail), error_soc(idx_detail), 'r-', 'LineWidth', 1.5);
grid on;
ylabel('SOC Error (%)');
title('SOC Error (First 10% of Data)');
xlabel('Time (s)');
yline(0, 'k--', 'LineWidth', 1);

%% ----- SAVE OUTPUTS ----------------------------------------------------
fprintf('\nSaving output files...\n');

% Save SOC results
SOC_kalman_data = [time, SOC_kalman * 100];  % Convert to percentage
save('SOC_kalman.mat', 'SOC_kalman_data', 'time', 'SOC_kalman', 'SOC_coulomb');

% Save Kalman parameters
kalman_params = struct();
kalman_params.Q = Q;
kalman_params.R = R;
kalman_params.P0 = P0_full;
kalman_params.SOC0 = SOC0;
kalman_params.matchMode = matchMode;
kalman_params.relyOnVoltage = relyOnVoltage;
kalman_params.rmse = rmse;
kalman_params.max_error = max_error;
kalman_params.mean_error = mean_error;
kalman_params.match_result = match_result;
save('kalman_params.mat', 'kalman_params');

% Create match report
fid = fopen('match_report.txt', 'w');
fprintf(fid, 'Kalman Filter SOC Estimation Match Report\n');
fprintf(fid, '==========================================\n\n');
fprintf(fid, 'Dataset: mich_endurance_combined_data.csv\n');
fprintf(fid, 'Number of samples: %d\n', N);
fprintf(fid, 'Duration: %.2f s\n', time(end));
fprintf(fid, 'Sample time: %.4f s\n\n', Ts);
fprintf(fid, 'Kalman Filter Parameters:\n');
fprintf(fid, '  Q (process noise): %.6e\n', Q);
fprintf(fid, '  R (measurement noise): %.6e\n', R);
fprintf(fid, '  P0 (initial covariance): [see .mat file]\n');
fprintf(fid, '  Initial SOC estimate: %.4f\n\n', SOC0);
fprintf(fid, 'Match Mode: %s\n', string(matchMode));
fprintf(fid, 'Relies on Voltage: %s\n\n', string(relyOnVoltage));
fprintf(fid, 'Results:\n');
fprintf(fid, '  RMSE (SOC units): %.6f\n', rmse);
fprintf(fid, '  RMSE (%%): %.4f\n', rmse * 100);
fprintf(fid, '  Max Error: %.6f\n', max_error);
fprintf(fid, '  Mean Error: %.6f\n', mean_error);
fprintf(fid, '  Target Tolerance: %.6f\n', rmseTolerance);
fprintf(fid, '  Match Result: %s\n\n', match_result);
fprintf(fid, 'Battery Parameters:\n');
fprintf(fid, '  Cell Capacity: %.2f Ah\n', Q_Ah);
fprintf(fid, '  Internal Resistance: %.4f Ω\n', R_ohm);
fprintf(fid, '  Cells in Series: %d\n', Ns);
fprintf(fid, '  Parallel Strings: %d\n', Np);
fclose(fid);

fprintf('  ✓ SOC_kalman.mat saved\n');
fprintf('  ✓ kalman_params.mat saved\n');
fprintf('  ✓ match_report.txt saved\n');

%% ----- SUMMARY DISPLAY -------------------------------------------------
fprintf('\n========== KALMAN FILTER SOC ESTIMATION SUMMARY ==========\n');
fprintf('Initial SOC (from OCV):       %.3f\n', initialSOC);
fprintf('Initial SOC (Kalman estimate): %.3f\n', SOC0);
fprintf('Final SOC (Coulomb):          %.3f\n', SOC_coulomb(end));
fprintf('Final SOC (Kalman):           %.3f\n', SOC_kalman(end));
fprintf('RMSE:                         %.6f (%.4f%%)\n', rmse, rmse * 100);
fprintf('Max Error:                     %.6f\n', max_error);
if matchMode
    fprintf('Match Mode Result:             %s\n', match_result);
end
fprintf('===========================================================\n\n');

%% ----- HELPER FUNCTION: RUN KALMAN FILTER ------------------------------
function [SOC_out, P_out] = run_kalman_filter(...
    time, I_cell, V_cell, OCVf, Q, R, P0, x0, Q_C, R_ohm, Ts, relyOnVoltage)

    N = length(time);
    n_states = length(x0);
    
    SOC_out = zeros(N, 1);
    P_out = zeros(n_states, n_states, N);
    
    x_k = x0;
    P_k = P0;
    SOC_out(1) = x0(1);
    P_out(:,:,1) = P_k;
    
    for k = 2:N
        % Predict step
        F = 1;
        G = -Ts / Q_C;
        x_pred = F * x_k + G * I_cell(k);
        x_pred = max(0, min(1, x_pred));
        
        % Predict covariance (Q can be scalar or matrix)
        P_pred = F * P_k * F' + Q;
        
        if relyOnVoltage
            % Update step
            OCV_pred = OCVf(x_pred);
            h_x = OCV_pred - I_cell(k) * R_ohm;
            
            eps = 1e-6;
            OCV_plus = OCVf(x_pred + eps);
            dOCV_dSOC = (OCV_plus - OCV_pred) / eps;
            H = dOCV_dSOC;
            
            z_k = V_cell(k);
            y_k = z_k - h_x;
            S_k = H * P_pred * H' + R;
            K_k = P_pred * H' / S_k;
            
            x_k = x_pred + K_k * y_k;
            x_k = max(0, min(1, x_k));
            P_k = (eye(n_states) - K_k * H) * P_pred;
        else
            x_k = x_pred;
            P_k = P_pred;
        end
        
        SOC_out(k) = x_k(1);
        P_out(:,:,k) = P_k;
    end
end

