% =========================================================================
% Simulate LVBatt Voltage from Power Profile using Rint Model
%           (SOC–OCV LUT given as M×2 matrix)
% =========================================================================
%
% REQUIRED INPUTS in workspace:
%   power_vs_time  : [t  , P_lvbatt]  (W)
%   soc_ocv_lut    : [SOC(%) , OCV(V)]  (non-uniform spacing OK)
%
% USER PARAMETERS to edit below.
% =========================================================================

%% ----- USER-SET PARAMETERS ---------------------------------------------
Ns        = 4;          % cells in series
Np        = 8;           % parallel strings
Q_Ah      = 3.45;         % cell capacity (Ah)
R_ohm     = 0.038;       % internal resistance (Ω)
V0_cell   = 2.7;        % initial cell voltage (V)
Vmin_cell = 2.5;   % Minimum allowed cell voltage (V)
Vmin_lvbatt = Vmin_cell * Ns;

% Name of your SOC–OCV variable (change if different)
socOcvVar = 'soc_ocv_lut';   % << put your variable name here

%% ----- FETCH INPUT MATRICES --------------------------------------------
if ~exist('power_vs_time','var')
    error('Variable power_vs_time not found in workspace.');
end
if ~exist(socOcvVar,'var')
    error('SOC–OCV LUT variable "%s" not found.', socOcvVar);
end
soc_ocv_lut = eval(socOcvVar);          % matrix [SOC% , OCV]

time      = power_vs_time(:,1);
P_lvbatt  = power_vs_time(:,2);

SOC_LUT   = soc_ocv_lut(:,1) / 100;     % convert % → fraction
OCV_LUT   = soc_ocv_lut(:,2);

OCVf = @(soc) interp1(SOC_LUT, OCV_LUT, soc, 'linear', 'extrap');

%% ----- PRE-ALLOC & INITIAL CONDITIONS -----------------------------------
N      = numel(time);
dt     = [0; diff(time)];
Q_C    = Q_Ah*3600;                     % Coulombs per cell

SOC         = zeros(N,1);
V_cell      = zeros(N,1);
V_lvbatt    = zeros(N,1);
I_lvbatt    = zeros(N,1);
I_cell      = zeros(N,1);

V_cell(1)   = V0_cell;
V_lvbatt(1) = Ns * V0_cell;
% estimate initial SOC
[~, idx0] = min(abs(OCV_LUT - V0_cell));   % nearest OCV point
SOC(1)    = SOC_LUT(idx0);                 % initial SOC (fraction)

%% ----- MAIN LOOP --------------------------------------------------------
for k = 2:N
    I_lvbatt(k) = P_lvbatt(k-1) / V_lvbatt(k-1);
    I_cell(k)   = I_lvbatt(k) / Np;

    SOC(k) = SOC(k-1) - (I_cell(k)*dt(k))/Q_C;
    SOC(k) = max(0, min(1, SOC(k)));               % clamp 0-1

    OCV_k       = OCVf(SOC(k));
    V_cell(k)   = OCV_k - I_cell(k)*R_ohm;
    V_lvbatt(k) = Ns * V_cell(k);
end

%% ----- PLOTS ------------------------------------------------------------
figure;
subplot(3,1,1); plot(time,P_lvbatt,'LineWidth',1.8); grid on
ylabel('Power (W)')
title('LVBatt Power / Current / Voltage (Rint)')

subplot(3,1,2); plot(time,I_lvbatt,'LineWidth',1.8); grid on
ylabel('Current (A)')

subplot(3,1,3);
plot(time, V_lvbatt, 'LineWidth', 1.8); hold on;

% Plot minimum voltage limit line
yline(Vmin_lvbatt, 'r--', ...
    sprintf('Minimum Voltage: %.2f V', Vmin_lvbatt), ...
    'LabelVerticalAlignment','bottom', ...
    'LabelHorizontalAlignment','right', ...
    'LineWidth', 1.5);

ylabel('Voltage (V)');
xlabel('Time (s)');
grid on;


%% ----- SUMMARY INFO DISPLAY --------------------------------------------

% 1. Initial SOC estimate
[~, idx0] = min(abs(OCV_LUT - V0_cell));
initialSOC_pct = SOC_LUT(idx0) * 100;

% 2. Lowest voltage and time
[minV, minIdx] = min(V_lvbatt);
minV_time = time(minIdx);
minV_cell = minV / Ns;

% 3. Display results
fprintf('\n========== LVBATT VOLTAGE SIMULATION SUMMARY ==========\n');
fprintf('Initial cell voltage       : %.3f V\n', V0_cell);
fprintf('→ Estimated initial SOC     : %.1f %%\n', initialSOC_pct);
fprintf('Minimum simulated voltage  : %.2f V\n', minV);
fprintf('→ Corresponding cell voltage : %.3f V\n', minV_cell);
fprintf('→ Occurs at time            : %.2f s\n', minV_time);
fprintf('========================================================\n\n');

%% ----- EXPORT -----------------------------------------------------------
lvbatt_voltage_vs_time = [time , V_lvbatt];
lvbatt_current_vs_time = [time , I_lvbatt];
SOC_vs_time            = [time , SOC];

assignin('base','lvbatt_voltage_vs_time', lvbatt_voltage_vs_time);
assignin('base','lvbatt_current_vs_time', lvbatt_current_vs_time);
assignin('base','SOC_vs_time',            SOC_vs_time);