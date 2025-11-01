# Kalman Filter SOC Estimation

This project implements a Kalman-filter-only State-of-Charge (SOC) estimator for battery systems, designed to match the output of a Coulomb counting reference implementation.

## Files

- **KalmanCounting.m** - Main script implementing Kalman filter SOC estimation
- **kalman_utils.m** - Helper functions for Kalman filter operations and parameter tuning
- **CoulombCounting.m** - Reference Coulomb counting implementation
- **mich_endurance_combined_data.csv** - Michigan race dataset (Time, Pack Voltage, Pack Current)

## Quick Start

1. Ensure MATLAB can access the following files:
   - `mich_endurance_combined_data.csv`
   - `KalmanCounting.m`
   - `kalman_utils.m` (optional, for advanced tuning)

2. Run the main script:
   ```matlab
   KalmanCounting
   ```

3. The script will:
   - Load and preprocess the Michigan race dataset
   - Compute reference SOC using Coulomb counting
   - Run Kalman filter SOC estimation
   - (If `matchMode = true`) Automatically tune Q and R parameters to match Coulomb counting
   - Generate comparison plots
   - Save results to `.mat` files and `match_report.txt`

## Configuration

Edit the parameter block at the top of `KalmanCounting.m`:

### Battery Parameters
- `Ns` - Number of cells in series
- `Np` - Number of parallel strings
- `Q_Ah` - Cell capacity (Ah)
- `R_ohm` - Internal resistance (Ω)
- `V0_pack` - Initial pack voltage (V)

### Kalman Filter Parameters
- `Q` - Process noise covariance matrix
- `R` - Measurement noise covariance
- `P0` - Initial state error covariance
- `SOC0` - Initial SOC estimate (fraction, 0-1)

### Operating Modes
- `matchMode` - If `true`, automatically tunes Q/R to match Coulomb counting
- `relyOnVoltage` - If `true`, fuses voltage measurements; if `false`, uses process model only
- `rmseTolerance` - Target RMSE tolerance for match mode (default: 0.005 SOC units)

## Match Mode

When `matchMode = true`, the script performs automatic parameter tuning:

1. **Grid Search**: Tests combinations of Q and R parameters across logarithmic ranges
2. **Optimization**: Selects parameters that minimize RMSE vs. Coulomb counting
3. **Validation**: Checks if RMSE meets the target tolerance
4. **Report**: Generates `match_report.txt` with results

### Tuning Strategy

The tuning function (`tune_QR` in `kalman_utils.m`) performs:
- Logarithmic grid search over Q and R parameter spaces
- Evaluation of each combination using the full Kalman filter
- Early termination if target RMSE is achieved
- Selection of best-performing parameters

### Expected Results

- **Target RMSE**: ≤ 0.005 SOC units (0.5%) when match mode succeeds
- **Best Achievable**: Reported in `match_report.txt` if tolerance cannot be met
- **Convergence**: Typically converges within 100-200 parameter combinations

## Outputs

### Generated Files

1. **SOC_kalman.mat**
   - `SOC_kalman_data` - [time, SOC(%)] matrix
   - `time` - Time vector
   - `SOC_kalman` - Kalman filter SOC estimate (fraction)
   - `SOC_coulomb` - Reference Coulomb counting SOC (fraction)

2. **kalman_params.mat**
   - `kalman_params` - Structure containing:
     - Q, R, P0, SOC0 (parameters)
     - matchMode, relyOnVoltage (configuration)
     - rmse, max_error, mean_error (results)
     - match_result (PASS/FAIL/N/A)

3. **match_report.txt**
   - Summary of estimation results
   - Final parameters
   - Error metrics
   - Match mode status

### Generated Plots

1. **SOC Estimation Comparison** (Figure 1)
   - Subplot 1: SOC comparison (Coulomb counting vs. Kalman filter)
   - Subplot 2: SOC error over time
   - Subplot 3: Cell voltage (measured vs. model)
   - Subplot 4: Cell current

2. **SOC Detailed View** (Figure 2)
   - Zoomed view of first 10% of data
   - SOC comparison detail
   - Error detail

## Implementation Details

### State Vector

For the basic implementation:
- **State**: `[SOC]` (1×1)

For extended models (future):
- **State**: `[SOC; V_polarization]` (2×1)
- Includes RC dynamics for improved accuracy

### Process Model

Discrete-time state update:
```
SOC(k+1) = SOC(k) - (I(k) * Ts) / Q_C
```

Where:
- `I(k)` - Cell current at time k
- `Ts` - Sample time
- `Q_C` - Cell capacity in Coulombs (Q_Ah × 3600)

### Measurement Model

Terminal voltage:
```
V_terminal = OCV(SOC) - I * R_ohm
```

Where:
- `OCV(SOC)` - Open-circuit voltage from lookup table
- `R_ohm` - Internal resistance

### Kalman Filter Equations

**Predict Step:**
```
x_pred = F * x_k + G * I_k
P_pred = F * P_k * F' + Q
```

**Update Step (if `relyOnVoltage = true`):**
```
y_k = V_measured - h(x_pred)
S_k = H * P_pred * H' + R
K_k = P_pred * H' / S_k
x_k = x_pred + K_k * y_k
P_k = (I - K_k * H) * P_pred
```

Where:
- `H` - Measurement Jacobian (dOCV/dSOC)
- `K_k` - Kalman gain

## Matching Coulomb Counting

The Kalman filter can closely match Coulomb counting by:

1. **Low Process Noise (Q)**: Reduces uncertainty in process model, making it track current integration closely
2. **High Measurement Noise (R)**: When voltage is unreliable or not used, de-emphasizes measurement updates
3. **Process-Only Mode**: Set `relyOnVoltage = false` to use only the process model (identical dynamics to Coulomb counting)

## Assumptions

1. **SOC-OCV Relationship**: Uses lookup table from `BatterySOCEstimationData.m` (T=293K)
2. **Constant Temperature**: OCV lookup assumes constant temperature
3. **Rint Model**: Simple internal resistance model (no RC dynamics in basic version)
4. **Uniform Sampling**: Data is resampled to uniform `Ts` if needed
5. **Cell Configuration**: Pack voltage divided by `Ns` to get cell voltage

## Troubleshooting

### High RMSE
- Adjust `Q` and `R` manually or enable `matchMode`
- Verify battery parameters (`Q_Ah`, `R_ohm`, `Ns`)
- Check SOC-OCV lookup table accuracy

### Match Mode Fails
- Increase grid search range in `tune_QR` function
- Verify data quality (no missing values, reasonable voltage/current)
- Check that Coulomb counting reference is reasonable

### Memory Issues
- Reduce grid search resolution in `kalman_utils.m`
- Process data in chunks for very long datasets

## Extending the Implementation

To add RC dynamics:
1. Set `use_polarization = true` in `KalmanCounting.m`
2. Extend state vector to `[SOC; V_polarization]`
3. Update process model with RC dynamics
4. Extend measurement model: `V = OCV(SOC) - I*R - V_polarization`

## Citation

This implementation follows the structure and coding style of `CoulombCounting.m` and uses parameters from `BatterySOCEstimationData.m` (MathWorks Battery SOC Estimation example).

## License

See project license file.
