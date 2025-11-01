% =========================================================================
% Kalman Filter Utility Functions
% =========================================================================
%
% Helper functions for Kalman filter SOC estimation:
%   - kf_predict: Kalman filter prediction step
%   - kf_update: Kalman filter update step
%   - compute_rmse: Compute RMSE between two SOC traces
%   - tune_QR: Automatic tuning of Q and R to match Coulomb counting
%
% =========================================================================

%% ========================================================================
% KALMAN FILTER PREDICTION STEP
% ========================================================================
function [x_pred, P_pred] = kf_predict(x_k, P_k, I_cell, Ts, Q_C, Q)
    % Predict state and covariance
    %
    % Inputs:
    %   x_k    - Current state estimate [SOC; V_polarization (optional)]
    %   P_k    - Current covariance matrix
    %   I_cell - Cell current (A)
    %   Ts     - Sample time (s)
    %   Q_C    - Cell capacity in Coulombs (Ah * 3600)
    %   Q      - Process noise covariance matrix
    %
    % Outputs:
    %   x_pred - Predicted state
    %   P_pred - Predicted covariance
    
    n_states = length(x_k);
    
    % State transition matrix
    % For SOC: SOC(k+1) = SOC(k) - (I*dt) / Q_C
    F = eye(n_states);
    G = zeros(n_states, 1);
    G(1) = -Ts / Q_C;  % Current affects SOC
    
    % Predict state
    x_pred = F * x_k + G * I_cell;
    
    % Clamp SOC to [0, 1]
    if n_states >= 1
        x_pred(1) = max(0, min(1, x_pred(1)));
    end
    
    % Predict covariance
    P_pred = F * P_k * F' + Q;
end

%% ========================================================================
% KALMAN FILTER UPDATE STEP
% ========================================================================
function [x_upd, P_upd] = kf_update(x_pred, P_pred, z_k, I_cell, ...
    OCVf, R_ohm, R)
    % Update state and covariance using measurement
    %
    % Inputs:
    %   x_pred - Predicted state
    %   P_pred - Predicted covariance
    %   z_k    - Measurement (terminal voltage)
    %   I_cell - Cell current (A)
    %   OCVf   - Function handle for OCV(SOC)
    %   R_ohm  - Internal resistance (Ω)
    %   R      - Measurement noise covariance
    %
    % Outputs:
    %   x_upd  - Updated state
    %   P_upd  - Updated covariance
    
    n_states = length(x_pred);
    
    % Measurement model: V_terminal = OCV(SOC) - I*R
    OCV_pred = OCVf(x_pred(1));
    h_x = OCV_pred - I_cell * R_ohm;
    
    % Measurement Jacobian (dOCV/dSOC)
    eps = 1e-6;
    SOC_test = x_pred(1) + eps;
    OCV_plus = OCVf(SOC_test);
    dOCV_dSOC = (OCV_plus - OCV_pred) / eps;
    
    H = zeros(1, n_states);
    H(1) = dOCV_dSOC;  % Only SOC affects voltage measurement
    
    % Measurement residual
    y_k = z_k - h_x;
    
    % Measurement covariance
    S_k = H * P_pred * H' + R;
    
    % Kalman gain
    K_k = P_pred * H' / S_k;
    
    % Update state
    x_upd = x_pred + K_k * y_k;
    
    % Clamp SOC to [0, 1]
    if n_states >= 1
        x_upd(1) = max(0, min(1, x_upd(1)));
    end
    
    % Update covariance (Joseph form for numerical stability)
    I_KH = eye(n_states) - K_k * H;
    P_upd = I_KH * P_pred * I_KH' + K_k * R * K_k';
end

%% ========================================================================
% COMPUTE RMSE
% ========================================================================
function rmse = compute_rmse(SOC_est, SOC_ref)
    % Compute Root Mean Square Error between estimated and reference SOC
    %
    % Inputs:
    %   SOC_est - Estimated SOC vector
    %   SOC_ref - Reference SOC vector
    %
    % Output:
    %   rmse    - RMSE in SOC units
    
    if length(SOC_est) ~= length(SOC_ref)
        error('SOC vectors must have same length');
    end
    
    rmse = sqrt(mean((SOC_est - SOC_ref).^2));
end

%% ========================================================================
% TUNE Q AND R PARAMETERS
% ========================================================================
function [Q_best, R_best, SOC_kalman, P_kalman] = tune_QR(...
    time, I_cell, V_cell, SOC_ref, OCVf, ...
    Q0, R0, P0, x0, Q_C, R_ohm, Ts, relyOnVoltage, rmseTolerance)
    % Automatically tune Q and R to match reference SOC
    %
    % Inputs:
    %   time          - Time vector
    %   I_cell        - Cell current vector
    %   V_cell        - Cell voltage vector
    %   SOC_ref       - Reference SOC (from Coulomb counting)
    %   OCVf          - OCV function handle
    %   Q0            - Initial Q guess
    %   R0            - Initial R guess
    %   P0            - Initial covariance
    %   x0            - Initial state
    %   Q_C           - Cell capacity in Coulombs
    %   R_ohm         - Internal resistance
    %   Ts            - Sample time
    %   relyOnVoltage - Whether to use voltage measurements
    %   rmseTolerance - Target RMSE tolerance
    %
    % Outputs:
    %   Q_best        - Best Q parameter
    %   R_best        - Best R parameter
    %   SOC_kalman    - SOC estimate with best parameters
    %   P_kalman      - Covariance history with best parameters
    
    fprintf('Starting Q/R tuning optimization...\n');
    
    % Grid search strategy
    if isscalar(Q0)
        Q_candidates = logspace(log10(Q0) - 2, log10(Q0) + 2, 15);
    else
        Q_candidates = logspace(-6, -2, 15);
    end
    
    if isscalar(R0)
        R_candidates = logspace(log10(R0) - 2, log10(R0) + 2, 15);
    else
        R_candidates = logspace(-3, 1, 15);
    end
    
    best_rmse = inf;
    best_Q = Q0;
    best_R = R0;
    best_SOC = [];
    best_P = [];
    
    fprintf('Grid search: %d Q values x %d R values = %d combinations\n', ...
        length(Q_candidates), length(R_candidates), ...
        length(Q_candidates) * length(R_candidates));
    
    total_combos = length(Q_candidates) * length(R_candidates);
    combo_count = 0;
    
    % Grid search
    for i = 1:length(Q_candidates)
        for j = 1:length(R_candidates)
            Q_test = Q_candidates(i);
            R_test = R_candidates(j);
            
            combo_count = combo_count + 1;
            
            % Run Kalman filter with test parameters
            try
                [SOC_test, P_test] = run_kf_with_params(...
                    time, I_cell, V_cell, OCVf, Q_test, R_test, ...
                    P0, x0, Q_C, R_ohm, Ts, relyOnVoltage);
                
                rmse_test = compute_rmse(SOC_test, SOC_ref);
                
                if rmse_test < best_rmse
                    best_rmse = rmse_test;
                    best_Q = Q_test;
                    best_R = R_test;
                    best_SOC = SOC_test;
                    best_P = P_test;
                end
                
                if mod(combo_count, 50) == 0 || rmse_test < rmseTolerance
                    fprintf('  Progress: %d/%d (%.1f%%), Best RMSE: %.6f\n', ...
                        combo_count, total_combos, ...
                        100 * combo_count / total_combos, best_rmse);
                end
                
                % Early exit if target met
                if rmse_test < rmseTolerance
                    fprintf('  Target RMSE achieved! Stopping search.\n');
                    break;
                end
                
            catch ME
                % Skip problematic parameter combinations
                fprintf('  Warning: Skipped Q=%.2e, R=%.2e (error: %s)\n', ...
                    Q_test, R_test, ME.message);
                continue;
            end
        end
        
        % Early exit if target met
        if best_rmse < rmseTolerance
            break;
        end
    end
    
    Q_best = best_Q;
    R_best = best_R;
    SOC_kalman = best_SOC;
    P_kalman = best_P;
    
    fprintf('Tuning complete. Best parameters:\n');
    fprintf('  Q = %.6e, R = %.6e\n', Q_best, R_best);
    fprintf('  Best RMSE = %.6f\n', best_rmse);
end

%% ========================================================================
% HELPER: RUN KF WITH PARAMETERS
% ========================================================================
function [SOC_out, P_out] = run_kf_with_params(...
    time, I_cell, V_cell, OCVf, Q, R, P0, x0, Q_C, R_ohm, Ts, relyOnVoltage)
    % Run Kalman filter with given parameters
    
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
        [x_pred, P_pred] = kf_predict(x_k, P_k, I_cell(k), Ts, Q_C, Q);
        
        if relyOnVoltage
            % Update step
            [x_k, P_k] = kf_update(x_pred, P_pred, V_cell(k), I_cell(k), ...
                OCVf, R_ohm, R);
        else
            x_k = x_pred;
            P_k = P_pred;
        end
        
        SOC_out(k) = x_k(1);
        P_out(:,:,k) = P_k;
    end
end

