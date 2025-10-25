%% UTFR Battery Parameters for SOC Estimation
% 
% This file contains the battery cell parameters for the UTFR electric race car
% configured for use with MATLAB's SOC Estimator (Kalman Filter) block.
% Parameters are based on lithium-ion chemistry typical for racing applications.
%
% Copyright 2024 UTFR Electric Racing Team

%% Battery Cell Parameters
% Based on high-performance lithium-ion cells for racing applications

% SOC lookup vector (0 to 100%)
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];

% Temperature lookup vector (K) - racing temperature range
T_vec = [278, 293, 313]; % 5°C, 20°C, 40°C

% Cell capacity (Ah) - typical for racing cells
AH = 27; % Ampere-hours

% Thermal mass (J/K) - cell thermal mass
thermal_mass = 100;

% Initial SOC for simulation
initialSOC = 1.0; % Start fully charged

%% Open Circuit Voltage (V0) vs SOC and Temperature
% Higher voltage cells for racing applications
V0_mat = [
    3.2,  3.25, 3.3;   % SOC = 0%
    3.4,  3.45, 3.5;   % SOC = 10%
    3.6,  3.65, 3.7;   % SOC = 25%
    3.7,  3.75, 3.8;   % SOC = 50%
    3.9,  3.95, 4.0;   % SOC = 75%
    4.1,  4.15, 4.2;   % SOC = 90%
    4.2,  4.25, 4.3    % SOC = 100%
];

%% Terminal Resistance (R0) vs SOC and Temperature
% Lower resistance for high-performance cells
R0_mat = [
    0.008, 0.006, 0.005;  % SOC = 0%
    0.007, 0.005, 0.004;  % SOC = 10%
    0.006, 0.004, 0.003;  % SOC = 25%
    0.005, 0.003, 0.002;  % SOC = 50%
    0.004, 0.002, 0.001;  % SOC = 75%
    0.003, 0.001, 0.0008; % SOC = 90%
    0.002, 0.0008, 0.0006 % SOC = 100%
];

%% First Polarization Resistance (R1) vs SOC and Temperature
R1_mat = [
    0.005, 0.002, 0.001;  % SOC = 0%
    0.004, 0.0015, 0.0008; % SOC = 10%
    0.003, 0.001, 0.0006;  % SOC = 25%
    0.002, 0.0008, 0.0005; % SOC = 50%
    0.0015, 0.0006, 0.0004; % SOC = 75%
    0.001, 0.0004, 0.0003; % SOC = 90%
    0.0008, 0.0003, 0.0002 % SOC = 100%
];

%% First Time Constant (tau1) vs SOC and Temperature
tau1_mat = [
    15, 25, 30;  % SOC = 0%
    20, 30, 35;  % SOC = 10%
    25, 35, 40;  % SOC = 25%
    30, 40, 45;  % SOC = 50%
    35, 45, 50;  % SOC = 75%
    40, 50, 55;  % SOC = 90%
    45, 55, 60   % SOC = 100%
];

%% Thermal Parameters
cell_area = 0.1019; % Cell area (m^2)
h_conv = 8;         % Heat transfer coefficient (W/(K*m^2)) - higher for racing

%% Extended Kalman Filter Parameters
% Tuned for racing conditions with higher process noise due to aggressive driving

% Process noise covariance matrix Q
% [SOC variance, temperature variance]
Q = [1e-3, 0; 0, 1e-2]; % Higher SOC noise for racing dynamics

% Measurement noise covariance R
R = 0.5; % Voltage measurement noise (V^2)

% Initial state error covariance P0
P0 = [1e-2, 0; 0, 1]; % Initial uncertainty

% Initial SOC for estimator (different from true initial SOC)
SOC0 = 0.95; % Start estimator at 95% SOC

% Sample time (seconds)
Ts = 0.01; % 100 Hz sampling for racing applications

%% Pack Configuration
% UTFR battery pack specifications
numCellsSeries = 140;    % Number of cells in series
numCellsParallel = 1;    % Number of parallel strings
totalCapacity = AH * numCellsParallel; % Total pack capacity (Ah)
nominalVoltage = 3.7 * numCellsSeries; % Nominal pack voltage (V)

fprintf('UTFR Battery Pack Configuration:\n');
fprintf('  Series cells: %d\n', numCellsSeries);
fprintf('  Parallel strings: %d\n', numCellsParallel);
fprintf('  Total capacity: %.1f Ah\n', totalCapacity);
fprintf('  Nominal voltage: %.1f V\n', nominalVoltage);
fprintf('  Voltage range: %.1f - %.1f V\n', ...
    min(V0_mat(:)) * numCellsSeries, max(V0_mat(:)) * numCellsSeries);
