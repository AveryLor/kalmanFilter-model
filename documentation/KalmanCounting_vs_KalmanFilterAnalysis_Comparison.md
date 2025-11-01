# Comparison: KalmanCounting.m vs KalmanFilterAnalysis.m

## Quick Summary

- **KalmanCounting.m**: Comprehensive, feature-rich Kalman filter implementation with automatic parameter tuning
- **KalmanFilterAnalysis.m**: Simple, straightforward script focused on comparison and visualization

---

## Detailed Differences

### 1. **Purpose & Scope**

#### KalmanCounting.m
- **Purpose**: Full-featured SOC estimation system with automatic calibration
- **Focus**: Production-ready implementation with tuning capabilities
- **Use case**: When you need to optimize Q/R parameters automatically or switch between different modes

#### KalmanFilterAnalysis.m
- **Purpose**: Simple analysis and visualization tool
- **Focus**: Educational/demonstration - show how Kalman filter compares to Coulomb counting
- **Use case**: Quick comparison, understanding the algorithm, testing with fixed parameters

---

### 2. **Battery Parameters**

#### KalmanCounting.m
```matlab
Ns = 144;        % cells in series (inferred from pack voltage ~513V)
Np = 1;          % parallel strings
Q_Ah = 27;       % cell capacity (Ah)
R_ohm = 0.011;  % internal resistance (Ω)
```
- **Designed for**: Large pack (144 cells in series)
- **Capacity**: 27 Ah cells
- **Based on**: Michigan race data characteristics

#### KalmanFilterAnalysis.m
```matlab
Ns = 4;          % cells in series
Np = 8;          % parallel strings  
Q_Ah = 3.45;    % cell capacity (Ah)
R_ohm = 0.038;   % internal resistance (Ω)
```
- **Designed for**: Small pack (matches CoulombCounting.m exactly)
- **Capacity**: 3.45 Ah cells
- **Based on**: Original CoulombCounting.m parameters

---

### 3. **Parameter Tuning (Match Mode)**

#### KalmanCounting.m
- ✅ **Has automatic tuning**: `matchMode = true` enables Q/R optimization
- ✅ **Grid search**: Tests combinations of Q and R to minimize RMSE
- ✅ **Target tolerance**: Configurable `rmseTolerance` (default: 0.005)
- ✅ **Reports results**: Saves best parameters and match status (PASS/FAIL)
- ✅ **Uses helper functions**: Calls `tune_QR.m` or `kalman_utils.m`

**Example:**
```matlab
matchMode = true;        % Enable automatic tuning
rmseTolerance = 0.005;   % Target RMSE threshold
% ... runs grid search ...
% Output: Best Q, Best R, Final RMSE, PASS/FAIL status
```

#### KalmanFilterAnalysis.m
- ❌ **No automatic tuning**: Uses fixed Q and R parameters
- ✅ **Manual adjustment**: You edit Q and R values directly in code
- ✅ **Simple**: No optimization overhead

**Example:**
```matlab
Q = 1e-5;  % Fixed value - you change this manually
R = 0.01;  % Fixed value - you change this manually
```

---

### 4. **Features & Options**

#### KalmanCounting.m

**Advanced Features:**
- ✅ **Match mode**: Automatic Q/R tuning
- ✅ **Voltage mode toggle**: `relyOnVoltage` flag (use voltage or process-only)
- ✅ **Data resampling**: Handles non-uniform sampling automatically
- ✅ **Extended state support**: Can add polarization voltage (commented out)
- ✅ **Robust preprocessing**: Handles missing data, NaN values, non-uniform sampling
- ✅ **Random seed**: For reproducibility (`rng(42)`)
- ✅ **Output files**: Saves `.mat` files and `match_report.txt`

**Code length**: ~576 lines

#### KalmanFilterAnalysis.m

**Simple Features:**
- ✅ **Comparison focus**: Shows Kalman filter vs Coulomb counting side-by-side
- ✅ **Visualization**: Multiple plots including SOC-OCV relationship
- ✅ **Debug output**: Prints first few iterations for troubleshooting
- ✅ **Error metrics**: RMSE, max error, mean error
- ❌ **No automatic tuning**: Manual parameter adjustment only
- ❌ **No file output**: Just displays results and plots

**Code length**: ~260 lines

---

### 5. **Kalman Filter Parameters**

#### KalmanCounting.m
```matlab
Q = 1e-4;       % Process noise (larger, more tuning flexibility)
R = 0.7;        % Measurement noise (larger, less trust in voltage)
P0 = 1e-5;      % Initial covariance (smaller)
SOC0 = 0.8;     % Initial SOC estimate (fixed)
```

#### KalmanFilterAnalysis.m
```matlab
Q = 1e-5;       % Process noise (smaller, more trust in physics)
R = 0.01;       % Measurement noise (smaller, more trust in voltage)
P = 0.01;       % Initial covariance (larger)
SOC0 = computed; % Initial SOC from voltage measurement
```

**Difference**: KalmanCounting.m uses more conservative (larger) noise values to allow tuning flexibility.

---

### 6. **Data Processing**

#### KalmanCounting.m
- ✅ **Resampling**: Checks if data is uniform, resamples if needed
- ✅ **Robust**: Handles edge cases (non-uniform sampling, missing data)
- ✅ **Configurable Ts**: Can set sample time or use actual data rate

**Code:**
```matlab
if std(dt_actual) / mean(dt_actual) > 0.01  % Check if non-uniform
    fprintf('Resampling data to uniform Ts = %.3f s...\n', Ts);
    time = (time_raw(1):Ts:time_raw(end))';
    V_pack = interp1(time_raw, V_pack_raw, time, 'linear', 'extrap');
    ...
```

#### KalmanFilterAnalysis.m
- ✅ **Simple**: Uses data as-is, assumes reasonably uniform
- ✅ **Basic cleanup**: Removes NaNs, computes average Ts
- ❌ **No resampling**: Assumes data is already uniform

**Code:**
```matlab
valid = ~(isnan(time) | isnan(V_pack) | isnan(I_pack));
time = time(valid);
Ts = mean(diff(time));  % Average sample time
```

---

### 7. **Outputs & Results**

#### KalmanCounting.m

**Saves to files:**
- ✅ `SOC_kalman.mat` - SOC results and time vectors
- ✅ `kalman_params.mat` - All parameters (Q, R, P0, etc.) and results
- ✅ `match_report.txt` - Detailed text report with metrics and PASS/FAIL status

**Console output:**
- Parameter tuning progress
- Final tuned parameters
- RMSE and match status

**Example output:**
```
Tuning complete. Best parameters:
  Q = 1.234e-05, R = 0.0567
  Final RMSE: 0.0042
  ✓ PASS: RMSE within tolerance
```

#### KalmanFilterAnalysis.m

**Saves to files:**
- ❌ **No file output** - Results only displayed

**Console output:**
- Initial conditions
- Debug info for first 5 iterations
- Error metrics (RMSE, max error, mean error)

**Plots:**
- ✅ SOC comparison plot
- ✅ Error plot
- ✅ Voltage and current plot
- ✅ SOC-OCV relationship (from measurements)
- ✅ **Separate dedicated SOC-OCV curve plot**

---

### 8. **Code Structure**

#### KalmanCounting.m

**Modular:**
- Main script with all logic
- Helper functions at bottom (`run_kalman_filter`)
- Can call external functions (`tune_QR`, `kalman_utils.m`)

**Sections:**
1. Parameter configuration
2. Data loading & preprocessing (robust)
3. SOC-OCV setup
4. Coulomb counting reference
5. Kalman filter setup
6. Kalman filter implementation
7. Error metrics
8. **Match mode tuning** (if enabled)
9. Plots
10. File output
11. Summary display

#### KalmanFilterAnalysis.m

**Streamlined:**
- All code in one script
- No external dependencies (self-contained)
- Simple linear flow

**Sections:**
1. Data loading (simple)
2. Battery parameters
3. SOC-OCV setup
4. Coulomb counting (ground truth)
5. Kalman filter (simple implementation)
6. Error metrics
7. **Visualization plots** (with SOC-OCV)

---

### 9. **Visualization**

#### KalmanCounting.m

**Plots:**
- SOC comparison (Coulomb vs Kalman)
- SOC error over time
- Cell voltage
- Cell current
- Detailed view (first 10% of data)

**Style**: Standard MATLAB plots, matching CoulombCounting.m style

#### KalmanFilterAnalysis.m

**Plots:**
- SOC comparison (Coulomb vs Kalman)
- SOC error over time
- Cell voltage and current (dual y-axis)
- **SOC-OCV relationship from measurements** (4th subplot with colormap)
- **Dedicated SOC-OCV curve figure** (separate figure with annotations)

**Style**: Enhanced visualization with SOC-OCV focus, color-coded by time

---

### 10. **Use Cases**

#### When to Use KalmanCounting.m

✅ **Production/Research**: When you need automatic parameter optimization  
✅ **Large datasets**: Better handling of non-uniform or messy data  
✅ **Experimentation**: Want to test different modes (with/without voltage)  
✅ **Documentation**: Need detailed reports and saved parameters  
✅ **Large packs**: Configured for 144-cell packs (or easily adaptable)  
✅ **Integration**: Can be integrated into larger systems (saves outputs)

**Example scenarios:**
- Battery management system development
- Research paper results generation
- Parameter optimization studies
- Production system integration

#### When to Use KalmanFilterAnalysis.m

✅ **Learning/Education**: Simple, easy to understand implementation  
✅ **Quick analysis**: Fast comparison without tuning overhead  
✅ **Visualization**: Focus on SOC-OCV relationship plots  
✅ **Small packs**: Matches original CoulombCounting.m parameters exactly  
✅ **Debugging**: Debug output helps understand what's happening  
✅ **Teaching**: Great for explaining Kalman filter concepts

**Example scenarios:**
- Teaching Kalman filter basics
- Quick SOC comparison
- Visualizing SOC-OCV relationship
- Understanding algorithm behavior
- Prototyping

---

### 11. **Key Code Differences**

#### Initialization

**KalmanCounting.m:**
```matlab
% Uses fixed initial SOC estimate
SOC0 = 0.8;  % Fixed value
```

**KalmanFilterAnalysis.m:**
```matlab
% Computes initial SOC from voltage
OCV_initial = V_cell(1) + I_cell(1) * R_ohm;
[~, idx0] = min(abs(OCV_vec - OCV_initial));
SOC0 = SOC_vec(idx0);
```

#### Kalman Filter Loop

**KalmanCounting.m:**
- Uses `I_cell(k)` for prediction
- More complex structure (supports extended states)
- Part of larger system with tuning

**KalmanFilterAnalysis.m:**
- Uses average current `(I_cell(k-1) + I_cell(k)) / 2` for prediction
- Simpler, focused implementation
- Has debug output
- More safeguards (bounds checking)

#### Error Handling

**KalmanCounting.m:**
- Robust error handling for tuning
- Try-catch blocks in tuning loop
- Skips problematic parameter combinations

**KalmanFilterAnalysis.m:**
- Basic safeguards (H bounds, S bounds, K clamping)
- Filters out unreasonable residuals (> 10V)
- Prevents numerical issues

---

## Summary Table

| Feature | KalmanCounting.m | KalmanFilterAnalysis.m |
|---------|------------------|------------------------|
| **Lines of Code** | ~576 | ~260 |
| **Auto Tuning** | ✅ Yes (match mode) | ❌ No |
| **Voltage Mode Toggle** | ✅ Yes | ❌ No |
| **Data Resampling** | ✅ Yes | ❌ No |
| **File Output** | ✅ Yes (.mat + .txt) | ❌ No |
| **SOC-OCV Plot** | ❌ No | ✅ Yes (dedicated) |
| **Debug Output** | ❌ No | ✅ Yes |
| **Pack Configuration** | Large (144 cells) | Small (4 cells) |
| **Complexity** | High | Low |
| **Use Case** | Production/Research | Education/Demo |
| **Dependencies** | tune_QR.m, kalman_utils.m | None (self-contained) |
| **Initial SOC** | Fixed (0.8) | From voltage |
| **Parameter Defaults** | Tuning-oriented | Fixed, tuned values |

---

## Recommendation

**For learning and visualization**: Use `KalmanFilterAnalysis.m`
- Simpler to understand
- Great plots including SOC-OCV relationship
- Easy to modify parameters manually
- Good for demonstrations

**For production/research**: Use `KalmanCounting.m`
- Automatic parameter optimization
- More robust data handling
- File outputs for analysis
- More configurable

**For both**: You can use both!
- Start with `KalmanFilterAnalysis.m` to understand
- Use `KalmanCounting.m` for optimization and production work

---

*Both scripts implement the same core Kalman filter algorithm, just with different features and complexity levels!*

