% Simple Extended Kalman Filter (EKF) for Battery Pack SOC Estimation


% Try to load Michigan race data
data = readtable('mich_endurance_combined_data.csv');
time = table2array(data(:,1));      % Time (s)
V_pack = table2array(data(:,2));    % Pack Voltage (V)
I_pack = table2array(data(:,3));    % Pack Current (A)

fprintf('Loaded Michigan race data: %d points\n', length(time));

N = length(time);
dt_vec = [0; diff(time)];  % Time differences

%% Battery Parameters (Michigan HV pack)
Ns = 144;        % cells in series (593 V pack / ~4.1 V nominal per cell)
Np = 1;          % parallel strings (pack-level current measurements)
Q_Ah = 27;       % cell capacity (Ah) - from BatterySOCEstimationData.m
R_ohm = 0.011;   % internal resistance (Ω) - typical R0 at 293 K
Q_C = Q_Ah * 3600;  % Capacity in Coulombs

% Convert to cell-level
V_cell = V_pack / Ns;
I_cell = I_pack / Np;

%% SOC-OCV Lookup Table (101 points, SOC 0-100%)
SOC_pct = (0:100)';
OCV_vec = [ ...
    3.000000000; 3.322775518; 3.376440630; 3.419621913; 3.448126953; ...
    3.472891532; 3.496989988; 3.519821597; 3.540925045; 3.560773687; ...
    3.579194026; 3.596270224; 3.611903416; 3.626935677; 3.641106401; ...
    3.654100755; 3.665736409; 3.676746642; 3.687323805; 3.697453750; ...
    3.706748346; 3.715316273; 3.723507259; 3.730961650; 3.736662454; ...
    3.740838268; 3.744348421; 3.747791998; 3.752161666; 3.757724467; ...
    3.762981617; 3.767813156; 3.772543783; 3.777527910; 3.782571376; ...
    3.787495849; 3.792166172; 3.796700575; 3.801339451; 3.806355574; ...
    3.811789725; 3.817413280; 3.823141520; 3.829284677; 3.835929039; ...
    3.842663954; 3.849148503; 3.855548607; 3.861947319; 3.868487198; ...
    3.875060385; 3.881640944; 3.888222110; 3.894760649; 3.901407287; ...
    3.908060766; 3.914810461; 3.921678483; 3.928734069; 3.935957838; ...
    3.943485005; 3.951309090; 3.959313683; 3.967531918; 3.975882496; ...
    3.984465235; 3.993385279; 4.002545777; 4.011992056; 4.021594934; ...
    4.031235285; 4.040868397; 4.050407392; 4.059928997; 4.069367368; ...
    4.078788373; 4.088328200; 4.098147575; 4.108052612; 4.117855837; ...
    4.127479536; 4.137201836; 4.146981135; 4.156866263; 4.166709896; ...
    4.176549763; 4.186432631; 4.196401941; 4.206326093; 4.216413489; ...
    4.226581822; 4.236898422; 4.247374623; 4.258083406; 4.269120427; ...
    4.280550759; 4.292498607; 4.305246697; 4.316770204; 4.328240241; ...
    4.347009000];
SOC_vec = SOC_pct / 100;  % SOC (fraction)

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
    SOC0 = SOC_from_OCV(OCV_initial);
    fprintf('Warning: OCV (%.3f V) above lookup table range, using extrapolated SOC\n', OCV_initial);
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

%% EKF Parameters
Q = 1e-6;        % Process noise covariance (SOC uncertainty)
R = 0.7;         % Measurement noise covariance (V^2); large R limits voltage over-correction
P = 0.01;        % Initial state covariance
P_max = 0.01;    % Cap state covariance to keep Kalman gain bounded
residual_max = 0.10;  % Skip voltage update when model mismatch exceeds this (V)
corr_gain = 10;       % Max voltage correction as multiple of coulomb step this interval
corr_floor = 1e-5;    % Minimum allowed per-step voltage correction (SOC fraction)

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
    %       Negative current = charging (increases SOC) (could be from actual charging or regen)
    
    % Predict SOC using current integration (trapezoidal current average)
    I_avg = (I_cell(k-1) + I_cell(k)) / 2;
    delta_SOC = -(I_avg * dt_k) / Q_C;
    x_pred = x + delta_SOC;
    
    % State transition Jacobian: F = df/dx = 1 (SOC is directly integrated)
    F = 1;
    
    % Predict covariance
    P_pred = min(P_max, F * P * F' + Q);
    
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
    % Use a central finite difference for a more robust slope estimate.
    eps_soc = 1e-3;
    soc_hi = max(0, min(1, x_pred + eps_soc));
    soc_lo = max(0, min(1, x_pred - eps_soc));
    if soc_hi == soc_lo
        H = 0.5;
    else
        OCV_hi = OCVf(soc_hi);
        OCV_lo = OCVf(soc_lo);
        H = (OCV_hi - OCV_lo) / (soc_hi - soc_lo);
    end
    
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
    
    % Update state estimate
    % Only apply a small voltage correction when model and measurement agree
    if abs(residual) <= residual_max
        max_corr = max(corr_floor, corr_gain * abs(delta_SOC));
        soc_corr = max(-max_corr, min(max_corr, K * residual));
        x = x_pred + soc_corr;
    else
        x = x_pred;
    end
    x = max(0, min(1, x));  % Clamp to valid range
    
    % Update covariance (Joseph form for numerical stability)
    P = (1 - K * H) * P_pred * (1 - K * H)' + K * R * K';
    P = min(P_max, max(1e-6, P));
    
    % Store result
    SOC_ekf(k) = x;
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

%% Plot: EKF SOC vs Time
figure('Position', [100, 100, 800, 500]);
plot(time/3600, SOC_ekf*100, 'b-', 'LineWidth', 2);
grid on;
xlabel('Time (hours)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('State of Charge (SOC) [%]', 'FontSize', 12, 'FontWeight', 'bold');
title('EKF Predicted SOC vs Time', 'FontSize', 14, 'FontWeight', 'bold');
ylim([0 100]);
xlim([0 max(time)/3600]);

