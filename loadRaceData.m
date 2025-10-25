function [time, voltage, current, temperature, trueSOC] = loadRaceData(filename)
%% loadRaceData - Load Michigan race data for SOC estimation
% 
% This function loads the Michigan endurance race data from CSV file and
% prepares it for use with the EKF SOC estimation system.
%
% Inputs:
%   filename - Path to the CSV file containing race data
%
% Outputs:
%   time      - Time vector (seconds)
%   voltage   - Pack voltage (V)
%   current   - Pack current (A) 
%   temperature - Temperature vector (°C) - estimated from voltage/current
%   trueSOC   - Reference SOC calculated from coulomb counting
%
% Usage:
%   [t, V, I, T, SOC_true] = loadRaceData('mich_endurance_combined_data.csv');
%
% Copyright 2024 UTFR Electric Racing Team

%% Load CSV data
if nargin < 1
    filename = 'mich_endurance_combined_data.csv';
end

fprintf('Loading race data from: %s\n', filename);

% Read CSV file
data = readtable(filename);

% Extract data columns
time = data{:,1};           % Time (s)
voltage = data{:,2};        % Pack Voltage (V)
current = data{:,3};        % Pack Current (A)

%% Calculate derived parameters

% Estimate temperature from voltage characteristics
% This is a simplified model - in practice, you'd have temperature sensors
temperature = 25 + (voltage - mean(voltage)) * 0.1; % °C
temperature = max(15, min(45, temperature)); % Clamp to reasonable range

% Calculate true SOC using coulomb counting
% Assuming initial SOC = 100% (fully charged at start)
initialSOC = 1.0; % 100%
batteryCapacity = 27; % Ah (from BatterySOCEstimationData.m)

% Integrate current over time to get SOC
dt = diff(time);
dt = [dt(1); dt]; % Use first dt for first point
cumulativeCharge = cumsum(current .* dt / 3600); % Convert to Ah
trueSOC = initialSOC - cumulativeCharge / batteryCapacity;

% Ensure SOC stays within [0, 1] bounds
trueSOC = max(0, min(1, trueSOC));

%% Display data summary
fprintf('Data loaded successfully:\n');
fprintf('  Duration: %.1f seconds (%.1f minutes)\n', time(end), time(end)/60);
fprintf('  Voltage range: %.1f - %.1f V\n', min(voltage), max(voltage));
fprintf('  Current range: %.1f - %.1f A\n', min(current), max(current));
fprintf('  Temperature range: %.1f - %.1f °C\n', min(temperature), max(temperature));
fprintf('  SOC range: %.1f%% - %.1f%%\n', min(trueSOC)*100, max(trueSOC)*100);
fprintf('  Data points: %d\n', length(time));

%% Create workspace variables for Simulink
assignin('base', 'raceTime', time);
assignin('base', 'raceVoltage', voltage);
assignin('base', 'raceCurrent', current);
assignin('base', 'raceTemperature', temperature);
assignin('base', 'raceTrueSOC', trueSOC);

fprintf('Data variables created in workspace:\n');
fprintf('  raceTime, raceVoltage, raceCurrent, raceTemperature, raceTrueSOC\n');

end
