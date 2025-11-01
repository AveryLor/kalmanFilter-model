% =========================================================================
% Simple Extended Kalman Filter (EKF) for Battery Pack SOC Estimation
% =========================================================================
%
% This script implements an EKF to estimate State of Charge (SOC)
% for a battery pack using voltage and current measurements.
%
% Battery parameters from CoulombCounting.m (lines 13-20):
%   Ns = 4 cells in series
%   Np = 8 parallel strings
%   Q_Ah = 3.45 Ah (cell capacity)
%   R_ohm = 0.038 Ω (internal resistance)
%
% =========================================================================

% Try to load Michigan race data

data = readtable('mich_endurance_combined_data.csv');
time = table2array(data(:,1));      % Time (s)
V_pack = table2array(data(:,2));    % Pack Voltage (V)
I_pack = table2array(data(:,3));    % Pack Current (A)

fprintf('Loaded Michigan race data: %d points\n', length(time));

N = length(time);
dt_vec = [0; diff(time)];  % Time differences

%% Battery Parameters (from CoulombCounting.m)
Ns = 4;          % cells in series
Np = 8;          % parallel strings
Q_Ah = 3.45;    % cell capacity (Ah)
R_ohm = 0.038;  % internal resistance (Ω)
Q_C = Q_Ah * 3600;  % Capacity in Coulombs

% Convert to cell-level
V_cell = V_pack / Ns;
I_cell = I_pack / Np;

%% SOC-OCV Lookup Table
% From BatterySOCEstimationData.m
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];  % SOC (fraction)
OCV_vec = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];  % OCV (V)

% Create interpolation function
OCVf = @(soc) interp1(SOC_vec, OCV_vec, soc, 'linear', 'extrap');

% Inverse function: SOC from OCV (for initialization)
SOC_from_OCV = @(ocv) interp1(OCV_vec, SOC_vec, ocv, 'linear', 'extrap');

%% Initialize SOC from First Voltage Measurement
% Account for IR drop
OCV_initial = V_cell(1) + I_cell(1) * R_ohm;

% Check if OCV is reasonable (within lookup table range)
if OCV_initial < min(OCV_vec)
    SOC0 = 0;
    fprintf('Warning: OCV (%.3f V) below lookup table range, setting SOC0=0\n', OCV_initial);
elseif OCV_initial > max(OCV_vec)
    % If OCV is way too high, it's likely a pack configuration issue
    % Estimate SOC from voltage assuming it's at high SOC
    SOC0 = 0.8;  % Start with reasonable estimate
    fprintf('Warning: OCV (%.3f V) above lookup table range.\n', OCV_initial);
    fprintf('  V_cell = %.3f V suggests pack configuration mismatch.\n', V_cell(1));
    fprintf('  Setting initial SOC to 0.8 (80%%) as default.\n');
else
    SOC0 = SOC_from_OCV(OCV_initial);
end
SOC0 = max(0, min(1, SOC0));  % Clamp to [0, 1]

fprintf('\nInitial conditions:\n');
fprintf('  V_pack(1): %.3f V\n', V_pack(1));
fprintf('  V_cell(1): %.3f V (should be ~3.5-4.2V range)\n', V_cell(1));
fprintf('  I_pack(1): %.3f A\n', I_pack(1));
fprintf('  I_cell(1): %.3f A\n', I_cell(1));
fprintf('  OCV_initial: %.3f V\n', OCV_initial);
fprintf('  Initial SOC: %.3f (%.1f%%)\n', SOC0, SOC0*100);

% Warn if cell voltage seems wrong
if V_cell(1) > 10
    fprintf('\n⚠️  WARNING: Cell voltage (%.3f V) seems too high!\n', V_cell(1));
    fprintf('  This suggests Ns=%d might be incorrect for this data.\n', Ns);
    fprintf('  Michigan data may be for a larger pack.\n');
    fprintf('  EKF will still run, but results may be inaccurate.\n');
end

%% EKF Parameters
Q = 1e-5;        % Process noise covariance (SOC uncertainty)
R = 0.01;        % Measurement noise covariance (voltage uncertainty)
P = 0.01;        % Initial state covariance

% Initial state (SOC estimate)
x = SOC0;  % SOC (fraction)

%% Pre-allocate
SOC_ekf = zeros(N, 1);
SOC_ekf(1) = x;

fprintf('\nRunning EKF SOC estimation...\n');

%% EKF Main Loop
for k = 2:N
    dt_k = dt_vec(k);
    
    % ========== PREDICT STEP ==========
    % Process model: SOC(k+1) = SOC(k) - (I*dt) / Q_C
    % This is the state transition function f(x, u)
    % Note: Positive current = discharging (decreases SOC)
    %       Negative current = charging (increases SOC)
    
    % Predict SOC using current integration
    % Use average current over interval for better accuracy
    if k > 1
        I_avg = (I_cell(k-1) + I_cell(k)) / 2;
    else
        I_avg = I_cell(k);
    end
    
    % SOC change: discharge (positive I) decreases SOC, charge (negative I) increases SOC
    delta_SOC = -(I_avg * dt_k) / Q_C;
    x_pred = x + delta_SOC;
    x_pred = max(0, min(1, x_pred));  % Clamp to valid range
    
    % Debug for first few iterations
    if k <= 5
        fprintf('  k=%d: I_cell=%.3f A, dt=%.4f s, delta_SOC=%.6f, x=%.4f -> x_pred=%.4f\n', ...
            k, I_avg, dt_k, delta_SOC, x, x_pred);
    end
    
    % State transition Jacobian: F = df/dx = 1 (SOC is directly integrated)
    F = 1;
    
    % Predict covariance
    P_pred = F * P * F' + Q;
    
    % ========== UPDATE STEP ==========
    % Measurement model: V = OCV(SOC) - I*R
    % This is the measurement function h(x, u)
    
    % Predicted measurement (voltage)
    OCV_pred = OCVf(x_pred);
    V_pred = OCV_pred - I_cell(k) * R_ohm;
    
    % Actual measurement
    V_measured = V_cell(k);
    
    % Measurement residual
    residual = V_measured - V_pred;
    
    % Measurement Jacobian: H = dh/dx = dOCV/dSOC
    % Compute numerically
    eps = 1e-6;
    soc_test = max(0, min(1, x_pred + eps));
    OCV_plus = OCVf(soc_test);
    H = (OCV_plus - OCV_pred) / eps;  % dOCV/dSOC
    
    % Ensure H is positive and reasonable
    if H <= 0 || isnan(H) || isinf(H)
        H = 0.5;  % Default reasonable value
    end
    
    % Innovation covariance
    S = H * P_pred * H' + R;
    
    % Avoid division by zero
    if S < 1e-10
        S = 1e-10;
    end
    
    % Kalman gain
    K = P_pred * H' / S;
    
    % Clamp gain to prevent instability
    K = max(0, min(2, K));
    
    % Update state estimate
    % Only apply correction if residual is reasonable (not huge voltage mismatch)
    if abs(residual) < 5  % Reasonable voltage residual threshold
        x = x_pred + K * residual;
    else
        % If residual is huge, likely voltage measurement/model mismatch
        % Trust the prediction (current integration) more
        x = x_pred;
        if k <= 10
            fprintf('  k=%d: Large residual (%.3f V), using prediction only\n', k, residual);
        end
    end
    x = max(0, min(1, x));  % Clamp to valid range
    
    % Debug for first few iterations
    if k <= 5
        fprintf('  k=%d: V_pred=%.3f, V_meas=%.3f, residual=%.3f, K=%.4f, x=%.4f\n', ...
            k, V_pred, V_measured, residual, K, x);
    end
    
    % Update covariance
    P = (1 - K * H) * P_pred;
    
    % Ensure P stays positive
    P = max(1e-6, P);
    
    % Store result
    SOC_ekf(k) = x;
    
    % Progress indicator
    if mod(k, 10000) == 0
        fprintf('  Progress: %d/%d (%.1f%%)\n', k, N, 100*k/N);
    end
end

fprintf('EKF estimation completed!\n');

%% Compute Statistics
SOC_mean = mean(SOC_ekf);
SOC_min = min(SOC_ekf);
SOC_max = max(SOC_ekf);
SOC_final = SOC_ekf(end);

fprintf('\n========== EKF RESULTS ==========\n');
fprintf('Initial SOC:  %.3f (%.1f%%)\n', SOC0, SOC0*100);
fprintf('Final SOC:    %.3f (%.1f%%)\n', SOC_final, SOC_final*100);
fprintf('Mean SOC:     %.3f (%.1f%%)\n', SOC_mean, SOC_mean*100);
fprintf('SOC Range:    %.3f - %.3f (%.1f%% - %.1f%%)\n', ...
    SOC_min, SOC_max, SOC_min*100, SOC_max*100);
fprintf('===============================\n\n');

%% Plot 1: SOC vs Time
figure('Position', [100, 100, 1200, 600]);

subplot(1, 2, 1);
plot(time/3600, SOC_ekf*100, 'b-', 'LineWidth', 2);
grid on;
xlabel('Time (hours)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('State of Charge (SOC) [%]', 'FontSize', 12, 'FontWeight', 'bold');
title('EKF Predicted SOC vs Time', 'FontSize', 14, 'FontWeight', 'bold');
ylim([0 100]);
xlim([0 max(time)/3600]);

