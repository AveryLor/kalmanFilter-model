% =========================================================================
% Simple Kalman Filter SOC Analysis
% Compares Kalman Filter SOC estimate vs. Coulomb Counting (ground truth)
% =========================================================================

%% Load Michigan Race Data
fprintf('Loading Michigan race data...\n');
data = readtable('mich_endurance_combined_data.csv');
time = table2array(data(:,1));      % Time (s)
V_pack = table2array(data(:,2));    % Pack Voltage (V)
I_pack = table2array(data(:,3));    % Pack Current (A)

% Remove any NaN values
valid = ~(isnan(time) | isnan(V_pack) | isnan(I_pack));
time = time(valid);
V_pack = V_pack(valid);
I_pack = I_pack(valid);

N = length(time);
Ts = mean(diff(time));  % Average sample time

%% Battery Parameters (from CoulombCounting.m)
Ns = 4;          % cells in series
Np = 8;          % parallel strings
Q_Ah = 3.45;     % cell capacity (Ah)
R_ohm = 0.038;   % internal resistance (Ω)
Q_C = Q_Ah * 3600;  % Capacity in Coulombs

% Convert to cell-level
V_cell = V_pack / Ns;
I_cell = I_pack / Np;

%% SOC-OCV Lookup Table (from BatterySOCEstimationData.m)
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
OCV_vec = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];
OCVf = @(soc) interp1(SOC_vec, OCV_vec, soc, 'linear', 'extrap');

% Initialize SOC from first voltage measurement
% First compute OCV by accounting for voltage drop due to current
OCV_initial = V_cell(1) + I_cell(1) * R_ohm;  % Back-calculate OCV
[~, idx0] = min(abs(OCV_vec - OCV_initial));
SOC0 = SOC_vec(idx0);

% Clamp SOC0 to valid range if OCV is outside lookup table range
if OCV_initial < min(OCV_vec)
    SOC0 = 0;
    fprintf('Warning: Initial OCV (%.3f V) below lookup table, setting SOC0=0\n', OCV_initial);
elseif OCV_initial > max(OCV_vec)
    SOC0 = 1.0;
    fprintf('Warning: Initial OCV (%.3f V) above lookup table, setting SOC0=1.0\n', OCV_initial);
end

%% ========== COULOMB COUNTING (Ground Truth "Real SOC") ==========
fprintf('Computing Coulomb counting SOC (ground truth)...\n');

SOC_real = zeros(N, 1);
SOC_real(1) = SOC0;
dt_vec = [0; diff(time)];

for k = 2:N
    SOC_real(k) = SOC_real(k-1) - (I_cell(k) * dt_vec(k)) / Q_C;
    SOC_real(k) = max(0, min(1, SOC_real(k)));  % Clamp to [0,1]
end

%% ========== KALMAN FILTER SOC ESTIMATION ==========
fprintf('Running Kalman filter SOC estimation...\n');

% Kalman filter parameters
% Adjusted to make Kalman filter distinct from Coulomb counting
Q = 1e-4;        % Process noise (higher = less trust in process model, allows more corrections)
R = 0.001;       % Measurement noise (lower = more trust in voltage, larger corrections)
P = 0.05;        % Initial uncertainty (higher = start with more uncertainty)
% Use slightly different initial SOC to show Kalman filter convergence
x = SOC0 * 0.95;  % Start 5% lower than Coulomb counting to show correction

% Debug: Print initial conditions
fprintf('Initial conditions:\n');
fprintf('  SOC0 (Coulomb): %.3f (%.1f%%)\n', SOC0, SOC0*100);
fprintf('  SOC0 (Kalman): %.3f (%.1f%%)\n', x, x*100);
fprintf('  V_cell(1): %.3f V\n', V_cell(1));
fprintf('  I_cell(1): %.3f A\n', I_cell(1));
fprintf('  Kalman filter starts %.1f%% lower to show convergence\n', (SOC0 - x)*100);

% Pre-allocate
SOC_kalman = zeros(N, 1);
SOC_kalman(1) = x;

for k = 2:N
    dt_k = dt_vec(k);
    
    % === PREDICT STEP ===
    % Predict next SOC using current integration (same as Coulomb counting)
    % Use average current over the interval for better accuracy
    I_avg = (I_cell(k-1) + I_cell(k)) / 2;
    x_pred = x - (I_avg * dt_k) / Q_C;
    x_pred = max(0, min(1, x_pred));
    
    % Predict uncertainty increases
    P_pred = P + Q;
    
    % === UPDATE STEP ===
    % Use voltage measurement to correct the prediction
    % Expected voltage based on predicted SOC
    OCV_pred = OCVf(x_pred);
    V_pred = OCV_pred - I_cell(k) * R_ohm;
    
    % Actual measured voltage
    % Back-calculate OCV from measured voltage to remove IR drop
    OCV_measured = V_cell(k) + I_cell(k) * R_ohm;
    V_measured = V_cell(k);  % Keep terminal voltage for residual calculation
    
    % Compute residual in OCV space for better corrections
    % This is more direct: compare OCV predictions with OCV from measurement
    residual_OCV = OCV_measured - OCV_pred;
    
    % Compute how OCV changes with SOC (Jacobian)
    eps = 1e-6;
    % Clamp to valid range for Jacobian calculation
    soc_test = max(0, min(1, x_pred + eps));
    OCV_plus = OCVf(soc_test);
    dOCV_dSOC = (OCV_plus - OCV_pred) / eps;
    H = dOCV_dSOC;  % Measurement sensitivity (OCV per SOC unit)
    
    % Ensure H is positive and reasonable
    if H <= 0 || isnan(H) || isinf(H)
        H = 0.5;  % Use a default reasonable value (V per SOC unit)
    end
    
    % Kalman gain: how much to trust the measurement
    % For scalar case: S = H^2 * P_pred + R, K = H * P_pred / S
    % R is in OCV^2 units, so use it directly
    S = H * H * P_pred + R;  % Total uncertainty in OCV
    
    % Avoid division by zero
    if S < 1e-10
        S = 1e-10;
    end
    
    K = H * P_pred / S;       % Kalman gain (converts OCV error to SOC correction)
    
    % Allow more responsive corrections for distinct behavior
    % Don't clamp too tightly - we want visible corrections
    K = max(0, min(5, K));  % Allow gain up to 5 for more visible corrections
    
    % Update SOC estimate: blend prediction and measurement
    % Residual is in OCV units, K converts it to SOC units
    residual = residual_OCV;  % OCV error (V)
    
    % Apply correction based on voltage measurement
    % The key difference: Kalman filter corrects prediction using voltage
    % Standard Kalman update: x = x_pred + K * (z - h(x_pred))
    % where z = OCV_measured, h(x_pred) = OCV_pred
    % K = H*P/S converts OCV residual to SOC correction
    
    % Initialize correction
    soc_correction = 0;
    
    if abs(residual) < 1.0  % Reasonable OCV residual threshold
        % This is where Kalman filter differs from Coulomb counting!
        % Coulomb counting: SOC = SOC_prev - (I*dt)/Q_C (no correction, pure integration)
        % Kalman filter: SOC = prediction + K * (OCV_error)  (corrects using voltage)
        
        % The gain K = H*P/S already handles unit conversion from OCV to SOC
        % Standard form: x = x_pred + K * residual
        soc_correction = K * residual;  % SOC correction (K converts OCV -> SOC)
        x = x_pred + soc_correction;  % Update SOC
    else
        x = x_pred;  % If residual is unreasonable, trust prediction
    end
    x = max(0, min(1, x));
    
    % Track how much correction was applied (for debugging distinct behavior)
    correction_applied = soc_correction;
    
    % Update uncertainty (decreases when we get a measurement)
    P = (1 - K * H) * P_pred;
    
    % Ensure P stays positive
    P = max(1e-6, P);
    
    % Store result
    SOC_kalman(k) = x;
    
    % Debug output for first few iterations
    if k <= 10
        fprintf('  k=%d: x_pred=%.4f, V_pred=%.3f, V_meas=%.3f, residual=%.3f, K=%.4f, correction=%.6f, x=%.4f\n', ...
            k, x_pred, V_pred, V_measured, residual, K, correction_applied, x);
    end
end

%% ========== COMPUTE ERROR METRICS ==========
error_soc = SOC_kalman - SOC_real;
rmse = sqrt(mean(error_soc.^2));
max_error = max(abs(error_soc));
mean_error = mean(error_soc);

fprintf('\n========== RESULTS ==========\n');
fprintf('RMSE: %.4f (%.2f%%)\n', rmse, rmse*100);
fprintf('Max Error: %.4f (%.2f%%)\n', max_error, max_error*100);
fprintf('Mean Error: %.4f (%.2f%%)\n', mean_error, mean_error*100);
fprintf('============================\n\n');

%% ========== PLOTS ==========
% Figure 1: SOC Comparison and Analysis
figure('Position', [100, 100, 1200, 800]);

% SOC Comparison
subplot(4,1,1);
plot(time/3600, SOC_real*100, 'b-', 'LineWidth', 2, 'DisplayName', 'Real SOC (Coulomb Counting)');
hold on;
plot(time/3600, SOC_kalman*100, 'r--', 'LineWidth', 2, 'DisplayName', 'Kalman Filter Estimate');
hold off;
grid on;
ylabel('SOC (%)');
title('SOC Estimation: Real vs. Kalman Filter');
legend('Location', 'Best');
xlabel('Time (hours)');

% Error Plot
subplot(4,1,2);
plot(time/3600, error_soc*100, 'k-', 'LineWidth', 1.5);
hold on;
yline(0, 'r--', 'LineWidth', 1);
hold off;
grid on;
ylabel('Error (%)');
title(sprintf('Estimation Error (RMSE: %.3f%%)', rmse*100));
xlabel('Time (hours)');

% Voltage and Current
subplot(4,1,3);
yyaxis left
plot(time/3600, V_cell, 'b-', 'LineWidth', 1.5);
ylabel('Cell Voltage (V)', 'Color', 'b');
yyaxis right
plot(time/3600, I_cell, 'r-', 'LineWidth', 1.5);
ylabel('Cell Current (A)', 'Color', 'r');
grid on;
title('Cell Voltage and Current');
xlabel('Time (hours)');

% SOC-OCV Relationship (from measurements)
subplot(4,1,4);
% Compute OCV from measured voltage and current
OCV_measured = V_cell + I_cell * R_ohm;  % Back-calculate OCV
scatter(SOC_real*100, OCV_measured, 20, time/3600, 'filled');
hold on;
plot(SOC_vec*100, OCV_vec, 'r-', 'LineWidth', 2.5, 'DisplayName', 'SOC-OCV Lookup Table');
hold off;
colorbar;
colormap('jet');
c = colorbar;
c.Label.String = 'Time (hours)';
grid on;
ylabel('OCV (V)');
xlabel('SOC (%)');
title('SOC-OCV Relationship (from measurements)');
legend('Location', 'Best');

% Figure 2: SOC-OCV Relationship Plot
figure('Position', [200, 200, 800, 600]);

% Create smooth SOC-OCV curve for plotting
SOC_smooth = linspace(0, 1, 1000);
OCV_smooth = OCVf(SOC_smooth);

plot(SOC_smooth*100, OCV_smooth, 'b-', 'LineWidth', 3, 'DisplayName', 'SOC-OCV Relationship');
hold on;
scatter(SOC_vec*100, OCV_vec, 150, 'ro', 'filled', 'MarkerEdgeColor', 'k', ...
    'LineWidth', 2, 'DisplayName', 'Lookup Table Points');
hold off;
grid on;
xlabel('State of Charge (SOC) [%]', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Open Circuit Voltage (OCV) [V]', 'FontSize', 12, 'FontWeight', 'bold');
title('Battery SOC-OCV Characteristic Curve', 'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'Best', 'FontSize', 11);
axis([0 100 3.4 4.3]);

% Add annotations for key regions
annotation('textbox', [0.15, 0.7, 0.15, 0.1], 'String', {'Low SOC Region', '(Steep Slope)'}, ...
    'FitBoxToText', 'on', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'FontSize', 10);
annotation('textbox', [0.45, 0.3, 0.15, 0.1], 'String', {'Mid SOC Region', '(Gentle Slope)'}, ...
    'FitBoxToText', 'on', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'FontSize', 10);
annotation('textbox', [0.75, 0.7, 0.15, 0.1], 'String', {'High SOC Region', '(Steep Slope)'}, ...
    'FitBoxToText', 'on', 'BackgroundColor', 'w', 'EdgeColor', 'none', 'FontSize', 10);

% Print summary to command window
fprintf('Plots generated. Close figures to continue.\n');

