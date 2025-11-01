% =========================================================================
% Coulomb Counting SOC Estimation from Michigan Race Data
%           (SOC–OCV LUT given as M×2 matrix)
% =========================================================================

%% ----- USER-SET PARAMETERS ---------------------------------------------
Ns        = 4;          % cells in series
Np        = 8;          % parallel strings
Q_Ah      = 3.45;       % cell capacity (Ah)
R_ohm     = 0.038;      % internal resistance (Ω)
Vmin_cell = 2.5;        % minimum allowed cell voltage (V)

% Name of your SOC–OCV variable (change if different)
socOcvVar = 'soc_ocv_lut';   % << put your variable name here

%% ----- LOAD MICHIGAN DATA ----------------------------------------------
if exist('mich_endurance_combined_data.csv','file')
    data = readtable('mich_endurance_combined_data.csv');
    time   = table2array(data(:,1));  % Time (s)
    V_pack = table2array(data(:,2));  % Pack Voltage (V)
    I_pack = table2array(data(:,3));  % Pack Current (A)
    
    valid = ~(isnan(time) | isnan(V_pack) | isnan(I_pack));
    time   = time(valid);
    V_pack = V_pack(valid);
    I_pack = I_pack(valid);
else
    error('Michigan race data not found. Place CSV in the working folder.');
end

%% ----- LOAD SOC–OCV LUT ------------------------------------------------
if ~exist(socOcvVar,'var')
    error('SOC–OCV LUT variable "%s" not found.', socOcvVar);
end
soc_ocv_lut = eval(socOcvVar);          % [SOC% , OCV(V)]

SOC_LUT = soc_ocv_lut(:,1)/100;  % fraction
OCV_LUT = soc_ocv_lut(:,2);

OCVf = @(soc) interp1(SOC_LUT, OCV_LUT, soc, 'linear', 'extrap');

%% ----- PRE-ALLOC & INITIAL CONDITIONS -----------------------------------
N      = numel(time);
dt_vec = [0; diff(time)];
Q_C    = Q_Ah*3600;   % Coulombs per cell

SOC      = zeros(N,1);
V_cell   = V_pack / Ns;
I_cell   = I_pack / Np;

% Initialize SOC from first voltage measurement (back-calculate OCV)
OCV_initial = V_cell(1) + I_cell(1)*R_ohm;
SOC0 = interp1(OCV_LUT, SOC_LUT, OCV_initial, 'linear', 'extrap');
SOC0 = max(0, min(1, SOC0));
SOC(1) = SOC0;

fprintf('Initial SOC estimated from OCV: %.1f%%\n', SOC0*100);

%% ----- MAIN LOOP --------------------------------------------------------
for k = 2:N
    % Coulomb counting update
    I_avg = (I_cell(k-1) + I_cell(k))/2;
    delta_SOC = -(I_avg * dt_vec(k)) / Q_C;  % discharge decreases SOC
    SOC(k) = SOC(k-1) + delta_SOC;
    SOC(k) = max(0, min(1, SOC(k)));  % clamp 0-1
end

%% ----- COMPUTE OCV FROM MEASURED VOLTAGE --------------------------------
OCV_measured = V_cell + I_cell * R_ohm;

%% ----- PLOTS ------------------------------------------------------------
figure('Position',[100,100,1200,600]);

% 1) SOC vs Time
subplot(1,2,1);
plot(time/3600, SOC*100, 'b-', 'LineWidth', 2); grid on;
xlabel('Time (hours)'); ylabel('SOC [%]');
title('Coulomb Counting SOC vs Time');
ylim([0 100]);

% 2) SOC vs OCV
subplot(1,2,2);
scatter(SOC*100, OCV_measured, 10, time/3600,'filled'); hold on;
SOC_smooth = linspace(0,1,1000);
plot(SOC_smooth*100, OCVf(SOC_smooth),'r-','LineWidth',2.5);
colormap('jet'); c = colorbar; c.Label.String = 'Time (hours)';
xlabel('SOC [%]'); ylabel('OCV [V]');
title('Coulomb Counting SOC vs OCV');
grid on;

%% ----- EXPORT -----------------------------------------------------------
SOC_vs_time = [time,SOC];
assignin('base','SOC_vs_time',SOC_vs_time);
