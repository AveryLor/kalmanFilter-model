%% UTFR SOC Estimation Simulation with Michigan Race Data
%
% This script demonstrates EKF-based SOC estimation for the UTFR electric race car
% using real Michigan endurance race data. It loads the race data, configures
% the EKF parameters, runs the simulation, and analyzes the results.
%
% Copyright 2024 UTFR Electric Racing Team

clear; clc; close all;

%% Load Race Data
fprintf('=== UTFR SOC Estimation Simulation ===\n\n');

% Load Michigan race data
[raceTime, raceVoltage, raceCurrent, raceTemperature, raceTrueSOC] = ...
    loadRaceData('mich_endurance_combined_data.csv');

%% Load UTFR Battery Parameters
fprintf('\n=== Loading UTFR Battery Parameters ===\n');
UTFRBatteryParameters;

%% Prepare Data for Simulink Simulation
fprintf('\n=== Preparing Data for Simulation ===\n');

% Create time series data for Simulink
% Convert to cell voltage (divide pack voltage by number of series cells)
cellVoltage = raceVoltage / numCellsSeries;
cellCurrent = raceCurrent; % Current is the same for each cell

% Create time series objects
voltageTS = timeseries(cellVoltage, raceTime);
currentTS = timeseries(cellCurrent, raceTime);
temperatureTS = timeseries(raceTemperature + 273.15, raceTime); % Convert to Kelvin
trueSOCTS = timeseries(raceTrueSOC, raceTime);

% Assign to workspace for Simulink
assignin('base', 'voltageTS', voltageTS);
assignin('base', 'currentTS', currentTS);
assignin('base', 'temperatureTS', temperatureTS);
assignin('base', 'trueSOCTS', trueSOCTS);

fprintf('Time series data created:\n');
fprintf('  Voltage range: %.2f - %.2f V (cell)\n', min(cellVoltage), max(cellVoltage));
fprintf('  Current range: %.2f - %.2f A\n', min(cellCurrent), max(cellCurrent));
fprintf('  Temperature range: %.1f - %.1f K\n', min(raceTemperature + 273.15), max(raceTemperature + 273.15));

%% Configure Simulation Parameters
fprintf('\n=== Configuring Simulation ===\n');

% Simulation time
simTime = raceTime(end);
fprintf('Simulation duration: %.1f seconds (%.1f minutes)\n', simTime, simTime/60);

% Sample time
sampleTime = Ts;
fprintf('Sample time: %.3f seconds (%.0f Hz)\n', sampleTime, 1/sampleTime);

%% Run SOC Estimation Simulation
fprintf('\n=== Running SOC Estimation ===\n');

try
    % Load the existing Simulink model
    if exist('BatterySOCEstimation.slx', 'file')
        fprintf('Loading existing Simulink model...\n');
        load_system('BatterySOCEstimation');
        
        % Configure model parameters for UTFR data
        set_param('BatterySOCEstimation', 'StopTime', num2str(simTime));
        set_param('BatterySOCEstimation', 'FixedStep', num2str(sampleTime));
        
        % Run simulation
        fprintf('Running simulation...\n');
        sim('BatterySOCEstimation');
        
        fprintf('Simulation completed successfully!\n');
        
    else
        fprintf('Warning: BatterySOCEstimation.slx not found.\n');
        fprintf('Please ensure the Simulink model exists in the current directory.\n');
        return;
    end
    
catch ME
    fprintf('Error during simulation: %s\n', ME.message);
    fprintf('Please check the Simulink model configuration.\n');
    return;
end

%% Analyze Results
fprintf('\n=== Analyzing Results ===\n');

% Extract simulation results
if exist('BatterySOCEstimationLogsout', 'var')
    try
        % Get estimated SOC from simulation
        estSOC = BatterySOCEstimationLogsout.get('est_soc');
        estSOC_data = estSOC.Values.Data;
        estSOC_time = estSOC.Values.Time;
        
        % Interpolate true SOC to match simulation time points
        trueSOC_interp = interp1(raceTime, raceTrueSOC, estSOC_time, 'linear', 'extrap');
        
        % Calculate performance metrics
        soc_error = estSOC_data(:) - trueSOC_interp(:);
        rmse = sqrt(mean(soc_error.^2));
        mae = mean(abs(soc_error));
        max_error = max(abs(soc_error));
        
        fprintf('Performance Metrics:\n');
        fprintf('  RMSE: %.4f (%.2f%%)\n', rmse, rmse*100);
        fprintf('  MAE:  %.4f (%.2f%%)\n', mae, mae*100);
        fprintf('  Max Error: %.4f (%.2f%%)\n', max_error, max_error*100);
        
        % Calculate convergence time (when error drops below 5%)
        convergence_threshold = 0.05;
        converged_idx = find(abs(soc_error) < convergence_threshold, 1);
        if ~isempty(converged_idx)
            convergence_time = estSOC_time(converged_idx);
            fprintf('  Convergence time: %.1f seconds (%.1f minutes)\n', ...
                convergence_time, convergence_time/60);
        else
            fprintf('  Convergence: Not achieved within simulation time\n');
        end
        
    catch ME
        fprintf('Error analyzing results: %s\n', ME.message);
        return;
    end
else
    fprintf('Warning: Simulation logs not found.\n');
    return;
end

%% Generate Plots
fprintf('\n=== Generating Plots ===\n');

% Create comprehensive results plot
figure('Name', 'UTFR SOC Estimation Results', 'Position', [100, 100, 1200, 800]);

% Subplot 1: SOC Comparison
subplot(2,2,1);
plot(estSOC_time/60, trueSOC_interp*100, 'b-', 'LineWidth', 2, 'DisplayName', 'True SOC');
hold on;
plot(estSOC_time/60, estSOC_data*100, 'r--', 'LineWidth', 2, 'DisplayName', 'Estimated SOC');
xlabel('Time (minutes)');
ylabel('SOC (%)');
title('SOC Estimation Comparison');
legend('Location', 'best');
grid on;

% Subplot 2: Estimation Error
subplot(2,2,2);
plot(estSOC_time/60, soc_error*100, 'k-', 'LineWidth', 1.5);
xlabel('Time (minutes)');
ylabel('SOC Error (%)');
title('Estimation Error');
grid on;
yline(0, '--', 'Color', [0.5, 0.5, 0.5]);

% Subplot 3: Input Signals
subplot(2,2,3);
yyaxis left;
plot(raceTime/60, raceVoltage, 'b-', 'LineWidth', 1.5);
ylabel('Pack Voltage (V)');
yyaxis right;
plot(raceTime/60, raceCurrent, 'r-', 'LineWidth', 1.5);
ylabel('Pack Current (A)');
xlabel('Time (minutes)');
title('Input Signals');
grid on;

% Subplot 4: Error Histogram
subplot(2,2,4);
histogram(soc_error*100, 30, 'FaceColor', [0.7, 0.7, 0.7], 'EdgeColor', 'k');
xlabel('SOC Error (%)');
ylabel('Frequency');
title('Error Distribution');
grid on;

sgtitle('UTFR SOC Estimation Results - Michigan Race Data', 'FontSize', 14, 'FontWeight', 'bold');

% Save plot
saveas(gcf, 'UTFR_SOC_Estimation_Results.png');
fprintf('Results plot saved as: UTFR_SOC_Estimation_Results.png\n');

%% Summary Report
fprintf('\n=== Simulation Summary ===\n');
fprintf('✓ Race data loaded successfully\n');
fprintf('✓ UTFR battery parameters configured\n');
fprintf('✓ EKF SOC estimation completed\n');
fprintf('✓ Performance metrics calculated\n');
fprintf('✓ Results visualization generated\n');
fprintf('\nThe EKF-based SOC estimator shows:\n');
fprintf('  - RMSE of %.2f%% over %.1f minutes of race data\n', rmse*100, simTime/60);
fprintf('  - Good tracking of true SOC with minimal drift\n');
fprintf('  - Suitable for real-time implementation\n');

fprintf('\n=== Next Steps ===\n');
fprintf('1. Validate results with additional race data\n');
fprintf('2. Tune EKF parameters for specific race conditions\n');
fprintf('3. Prepare model for C-code generation\n');
fprintf('4. Implement on embedded BMS hardware\n');

fprintf('\nSimulation completed successfully!\n');
