# UTFR EKF-based SOC Estimation System

This project implements an Extended Kalman Filter (EKF) based State of Charge (SOC) estimation system for the UTFR electric race car using MATLAB/Simulink. The system uses real Michigan endurance race data to validate and improve SOC accuracy under racing conditions.

## Project Overview

The goal is to implement, test, and validate a Kalman Filter-based SOC estimation system that can be deployed on the UTFR electric race car's Battery Management System (BMS). The system uses the Michigan race data containing current, voltage, temperature, and ground-truth SOC measurements.

## Files Description

### Core Scripts
- **`UTFRSOCSimulation.m`** - Main simulation script that orchestrates the entire SOC estimation process
- **`loadRaceData.m`** - Data import script for loading Michigan race data from CSV files
- **`UTFRBatteryParameters.m`** - UTFR-specific battery cell parameters and EKF configuration
- **`UTFRSOCCodeGeneration.m`** - Prepares the Simulink model for C-code generation

### Data Files
- **`mich_endurance_combined_data.csv`** - Michigan race data (158,564 data points, ~26.4 minutes)
- **`BatterySOCEstimation.slx`** - Simulink model implementing EKF SOC estimation

### Existing MATLAB Files
- **`BatterySOCEstimationData.m`** - Original battery parameters (MathWorks example)
- **`BatterySOCEstimationExample.m`** - Original example script
- **`BatterySOCEstimationPlotSOC.m`** - Original plotting script

## Michigan Race Data Structure

The CSV file contains:
- **Time (s)**: Timestamps from 0 to ~1585.6 seconds
- **Pack Voltage (V)**: Battery pack voltage (513-593V range)
- **Pack Current (A)**: Current measurements (-0.007 to 13.9A)

## UTFR Battery Configuration

### Pack Specifications
- **Series Cells**: 140 cells
- **Parallel Strings**: 1
- **Total Capacity**: 27 Ah
- **Nominal Voltage**: 518V (3.7V × 140 cells)
- **Voltage Range**: 448V - 602V

### Cell Parameters
- **Chemistry**: High-performance lithium-ion for racing
- **Capacity**: 27 Ah per cell
- **Temperature Range**: 5°C to 40°C
- **Optimized**: Lower resistance, higher power density

## EKF Configuration

### Filter Parameters
- **Process Noise Q**: `[1e-3, 0; 0, 1e-2]` (tuned for racing dynamics)
- **Measurement Noise R**: `0.5` (voltage measurement uncertainty)
- **Initial SOC**: `0.95` (95% - different from true initial SOC)
- **Sample Time**: `0.01s` (100 Hz for racing applications)

### Performance Targets
- **RMSE**: < 2% SOC estimation error
- **Convergence**: < 10 minutes to true SOC
- **Real-time**: Compatible with embedded BMS hardware

## Usage Instructions

### 1. Run Complete Simulation
```matlab
% Execute the main simulation script
UTFRSOCSimulation
```

This will:
- Load Michigan race data
- Configure UTFR battery parameters
- Run EKF SOC estimation
- Generate performance metrics
- Create visualization plots

### 2. Load Race Data Only
```matlab
% Load and examine race data
[t, V, I, T, SOC_true] = loadRaceData('mich_endurance_combined_data.csv');
```

### 3. Configure Battery Parameters
```matlab
% Load UTFR-specific parameters
UTFRBatteryParameters
```

### 4. Prepare for Code Generation
```matlab
% Configure model for embedded deployment
UTFRSOCCodeGeneration
```

## Expected Results

### Performance Metrics
- **RMSE**: Typically 1-3% SOC error
- **MAE**: Mean absolute error < 2%
- **Convergence**: 5-15 minutes to true SOC
- **Tracking**: Good transient response during acceleration/deceleration

### Output Files
- **`UTFR_SOC_Estimation_Results.png`** - Comprehensive results visualization
- **`UTFR_SOC_Embedded_Interface.md`** - Embedded integration documentation
- **`UTFR_SOC_Integration_Example.c`** - C-code integration example

## Technical Implementation

### Data Processing
1. **Data Import**: CSV parsing with proper scaling
2. **SOC Calculation**: Coulomb counting for ground truth
3. **Temperature Estimation**: Simplified thermal model
4. **Signal Conditioning**: Noise filtering and validation

### EKF Implementation
1. **State Vector**: [SOC, Temperature]
2. **Measurement**: Cell voltage
3. **Process Model**: Battery equivalent circuit model
4. **Update Rate**: 100 Hz for racing applications

### Validation Approach
1. **Ground Truth**: Coulomb counting from current integration
2. **Error Metrics**: RMSE, MAE, maximum error
3. **Convergence**: Time to reach steady-state accuracy
4. **Transient Response**: Performance during dynamic conditions

## Code Generation Compatibility

The system is prepared for C-code generation using Simulink Coder:

### Embedded Requirements
- **RAM**: ~2KB estimated
- **Flash**: ~10KB estimated  
- **CPU**: ARM Cortex-M4 @ 100MHz
- **Sample Rate**: 100 Hz

### Safety Features
- SOC bounds checking (0-1)
- Input signal validation
- Fault detection and recovery
- Watchdog timer implementation

## Future Enhancements

### Model Improvements
1. **Multi-cell Estimation**: Individual cell SOC tracking
2. **Thermal Modeling**: Enhanced temperature estimation
3. **Aging Compensation**: Capacity fade modeling
4. **Fault Detection**: Cell imbalance and degradation

### Integration
1. **CAN Communication**: BMS protocol integration
2. **Real-time Testing**: Hardware-in-the-loop validation
3. **Field Testing**: On-track validation with UTFR car
4. **Optimization**: Parameter tuning for specific race conditions

## Dependencies

### Required MATLAB Toolboxes
- **Simulink**: Model simulation and analysis
- **Simscape**: Battery modeling blocks
- **Simulink Coder**: C-code generation (optional)

### Optional Toolboxes
- **Control System Toolbox**: Advanced filtering
- **Signal Processing Toolbox**: Signal conditioning
- **Statistics and Machine Learning Toolbox**: Performance analysis

## Troubleshooting

### Common Issues
1. **Simulink Model Not Found**: Ensure `BatterySOCEstimation.slx` exists
2. **Data Loading Errors**: Check CSV file format and path
3. **Simulation Failures**: Verify model configuration and parameters
4. **Code Generation Issues**: Check Simulink Coder license

### Performance Tuning
1. **High RMSE**: Increase process noise Q or decrease measurement noise R
2. **Slow Convergence**: Adjust initial SOC estimate or covariance P0
3. **Poor Tracking**: Verify battery model parameters match actual cells
4. **Memory Issues**: Reduce sample rate or optimize data structures

## Contact

For questions or issues related to this SOC estimation system, contact the UTFR Electric Racing Team.

## License

Copyright 2024 UTFR Electric Racing Team. All rights reserved.