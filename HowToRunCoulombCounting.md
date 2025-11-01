# How to Run CoulombCounting.m

## Quick Answer

`CoulombCounting.m` requires **two variables** in your MATLAB workspace before you can run it. Use the helper script `RunCoulombCounting.m` for the easiest way!

## Method 1: Use the Helper Script (Easiest)

Simply run:
```matlab
RunCoulombCounting
```

This script will:
1. Load the Michigan race data
2. Convert it to the required format
3. Set up the SOC-OCV lookup table
4. Run `CoulombCounting.m` automatically

## Method 2: Manual Setup

If you want to set up the inputs manually:

### Step 1: Create `power_vs_time` Variable

This should be an **N×2 matrix** where:
- Column 1: Time (seconds)
- Column 2: Battery pack power (Watts)

**From Michigan data:**
```matlab
% Load data
data = readtable('mich_endurance_combined_data.csv');
time = table2array(data(:,1));      % Time (s)
V_pack = table2array(data(:,2));    % Pack Voltage (V)
I_pack = table2array(data(:,3));    % Pack Current (A)

% Calculate power: P = V × I
P_pack = V_pack .* I_pack;

% Create required matrix
power_vs_time = [time, P_pack];
```

**Or create custom data:**
```matlab
% Example: Simple power profile
time = (0:0.1:100)';              % 0 to 100 seconds, 0.1s steps
power = 100 * ones(size(time));   % Constant 100W
power_vs_time = [time, power];
```

### Step 2: Create `soc_ocv_lut` Variable

This should be an **M×2 matrix** where:
- Column 1: SOC (percentage, 0-100%)
- Column 2: OCV (Volts)

**Example:**
```matlab
% SOC-OCV lookup table
SOC_percent = [0, 10, 25, 50, 75, 90, 100];  % SOC (%)
OCV_volts = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];  % OCV (V)

soc_ocv_lut = [SOC_percent', OCV_volts'];
```

### Step 3: Run the Script

Once both variables are in your workspace:
```matlab
CoulombCounting
```

## Required Inputs Summary

| Variable | Format | Description | Example |
|----------|--------|-------------|---------|
| `power_vs_time` | N×2 matrix | [Time (s), Power (W)] | `[0, 100; 0.1, 95; ...]` |
| `soc_ocv_lut` | M×2 matrix | [SOC (%), OCV (V)] | `[0, 3.49; 10, 3.55; ...]` |

## What CoulombCounting.m Does

1. **Loads inputs** from workspace (`power_vs_time` and `soc_ocv_lut`)
2. **Calculates current** from power and voltage
3. **Performs Coulomb counting** to estimate SOC
4. **Calculates voltage** using Rint model (OCV - I×R)
5. **Generates plots** showing power, current, and voltage over time
6. **Saves outputs** to workspace variables

## Output Variables

After running, these variables are created in your workspace:

- `lvbatt_voltage_vs_time` - [Time, Pack Voltage]
- `lvbatt_current_vs_time` - [Time, Pack Current]
- `SOC_vs_time` - [Time, SOC (fraction)]

## Troubleshooting

### Error: "Variable power_vs_time not found"
- **Solution**: Create the `power_vs_time` matrix (see Step 1 above)
- **Or**: Use `RunCoulombCounting.m` which does this automatically

### Error: "SOC–OCV LUT variable not found"
- **Solution**: Create the `soc_ocv_lut` matrix (see Step 2 above)
- **Or**: Use `RunCoulombCounting.m` which does this automatically

### Plots don't look right
- Check that `power_vs_time` has positive power values
- Verify `soc_ocv_lut` covers the full SOC range (0-100%)
- Make sure time values are monotonically increasing

## Example Complete Script

```matlab
%% Setup inputs
% Power profile
time = (0:0.1:3600)';  % 1 hour, 0.1s steps
power = 150 * ones(size(time));  % Constant 150W
power_vs_time = [time, power];

% SOC-OCV lookup table
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
OCV_vec = [3.49, 3.55, 3.62, 3.71, 3.91, 4.07, 4.19];
soc_ocv_lut = [SOC_vec' * 100, OCV_vec'];

%% Run
CoulombCounting
```

## Differences from KalmanFilterAnalysis.m

- **CoulombCounting.m**: Requires power profile input (simulates voltage from power)
- **KalmanFilterAnalysis.m**: Uses measured voltage and current directly

The key difference is that `CoulombCounting.m` **predicts voltage** from power, while `KalmanFilterAnalysis.m` **uses measured voltage** for Kalman filtering.

