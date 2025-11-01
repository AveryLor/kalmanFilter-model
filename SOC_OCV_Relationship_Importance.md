# The Importance of SOC-OCV Relationship in Battery State Estimation

## Table of Contents
1. [What is SOC and OCV?](#what-is-soc-and-ocv)
2. [The Fundamental Relationship](#the-fundamental-relationship)
3. [Why This Relationship Matters](#why-this-relationship-matters)
4. [Characteristics of the SOC-OCV Curve](#characteristics-of-the-soc-ocv-curve)
5. [Practical Implications](#practical-implications)
6. [Challenges and Considerations](#challenges-and-considerations)

---

## What is SOC and OCV?

### State of Charge (SOC)

**SOC** is a measure of how much energy is stored in the battery relative to its maximum capacity.

- **Range**: 0% (completely empty) to 100% (completely full)
- **Definition**: `SOC = (Remaining Charge / Total Capacity) × 100%`
- **Cannot be directly measured**: You can't "see" or directly sense the charge inside a battery

**Think of it like:**
- A gas tank gauge showing how full your car's fuel tank is
- But unlike a fuel tank, you can't just "look" at the battery to see the charge

### Open Circuit Voltage (OCV)

**OCV** is the voltage across the battery terminals when no current is flowing (battery is at rest).

- **When measured**: After the battery has rested long enough for internal dynamics to settle
- **Units**: Volts (V)
- **Directly measurable**: Unlike SOC, voltage can be measured with a voltmeter

**Think of it like:**
- The pressure in a water tank (voltage) that relates to how full it is (SOC)
- But there's a relationship, not a perfect 1-to-1 mapping

---

## The Fundamental Relationship

### The Core Concept

**There exists a relationship between SOC and OCV** - this is the foundation of voltage-based SOC estimation.

```
OCV = f(SOC)
```

Where `f()` is a non-linear function that depends on:
- Battery chemistry (Li-ion, lead-acid, etc.)
- Temperature
- Battery age and degradation
- Manufacturing variations

### Why This Relationship Exists

**Physical Explanation:**

1. **Electrochemical Potential**: 
   - The voltage of a battery cell comes from the difference in electrochemical potential between the positive and negative electrodes
   - As the battery discharges, the concentration of ions in the electrolyte changes
   - This changes the electrochemical potential, which directly affects voltage

2. **Concentration Gradient**:
   - In a lithium-ion battery, SOC affects the concentration of lithium ions in each electrode
   - Higher SOC → more lithium in one electrode → higher voltage
   - Lower SOC → less lithium in one electrode → lower voltage

3. **Nernst Equation** (simplified):
   - The relationship between concentration and voltage follows electrochemical principles
   - `V ≈ V₀ + (RT/F) × ln(concentration ratio)`
   - This creates a logarithmic-like relationship

### Visual Representation

If you plot SOC vs. OCV, you get a characteristic curve:

```
      OCV (V)
         ↑
    4.2 |                      ╱
        |                    ╱
    4.0 |                ╱
        |            ╱
    3.8 |      ╱
        |  ╱
    3.5 |
        |
        └───────────────────────────→ SOC (%)
         0                         100
```

**Key observations:**
- **Non-linear**: Not a straight line
- **Regions**: Different slopes in different SOC ranges
- **Unique**: Each battery chemistry has its own curve

---

## Why This Relationship Matters

### 1. **Bridge Between Measurable and Unmeasurable**

- **Problem**: SOC cannot be directly measured
- **Solution**: Measure OCV and use the relationship to estimate SOC
- **This is the core principle behind voltage-based SOC estimation**

**Example:**
- Measure OCV = 3.75 V
- Look up in SOC-OCV table → SOC ≈ 60%
- This gives us an estimate of charge without directly measuring it

### 2. **Kalman Filter's Measurement Model**

In our Kalman filter implementation, we use this relationship:

```matlab
% Measurement model
V_terminal = OCV(SOC) - I × R
         ↓
Expected voltage = Lookup_OCV(predicted_SOC) - Current × Resistance
```

**What this does:**
- Predict what SOC should be (from current integration)
- Calculate what voltage we should see (using SOC-OCV relationship)
- Compare with actual measured voltage
- Use the difference to correct the SOC estimate

### 3. **Drift Correction**

**The Problem with Coulomb Counting:**
- Small errors in current measurement accumulate over time
- After hours of operation, SOC estimate drifts away from truth
- Example: 1% error per hour → 10% error after 10 hours

**The Solution:**
- Use SOC-OCV relationship as a "reference check"
- When voltage doesn't match expected voltage → correct the SOC estimate
- This prevents drift and keeps estimates accurate

### 4. **Initial SOC Estimation**

When starting an estimation algorithm:
- Measure voltage (OCV if battery has rested)
- Use SOC-OCV relationship to get initial SOC estimate
- This is much better than guessing or assuming a fixed starting value

**In our code:**
```matlab
[~, idx0] = min(abs(OCV_vec - V_cell(1)));
SOC0 = SOC_vec(idx0);  % Initial SOC from voltage
```

---

## Characteristics of the SOC-OCV Curve

### Three Distinct Regions

Most battery SOC-OCV curves have three distinct regions:

#### 1. **Low SOC Region (0-20%)**
- **Characteristic**: Steep slope
- **Meaning**: Voltage changes rapidly with small changes in SOC
- **Implication**: Good sensitivity - easy to distinguish SOC levels
- **Example**: SOC changes from 5% to 10% → voltage changes by ~0.15 V

**Why steep?**
- Near empty, small changes in ion concentration cause large voltage changes
- Electrodes are approaching their "empty" state

#### 2. **Mid SOC Region (20-80%)**
- **Characteristic**: Gentle/flat slope
- **Meaning**: Voltage changes slowly with large changes in SOC
- **Implication**: Lower sensitivity - harder to distinguish SOC levels
- **Example**: SOC changes from 40% to 60% → voltage changes by only ~0.10 V

**Why flat?**
- Battery is in its "comfort zone"
- Large concentration changes → small voltage changes
- Most of the battery's capacity lives in this region

**Challenge**: This is where voltage-based estimation is less accurate!

#### 3. **High SOC Region (80-100%)**
- **Characteristic**: Steep slope again
- **Meaning**: Voltage changes rapidly near full charge
- **Implication**: Good sensitivity near full charge
- **Example**: SOC changes from 90% to 95% → voltage changes by ~0.12 V

**Why steep?**
- Near full, small changes in ion concentration cause large voltage changes
- Electrodes are approaching their "full" state

### Slope Analysis (Jacobian)

The **slope** of the SOC-OCV curve tells us how sensitive voltage is to SOC changes.

**Mathematical definition:**
```
dOCV/dSOC = Slope of the curve
```

**In Kalman filter:**
- This is the **Jacobian** or **H matrix**
- It tells us: "If SOC changes by 1%, how much does voltage change?"

**Regions:**
- **Steep regions**: High dOCV/dSOC → voltage is very sensitive to SOC → good for estimation
- **Flat regions**: Low dOCV/dSOC → voltage is less sensitive to SOC → harder to estimate

**Example from our lookup table:**
- Low SOC: dOCV/dSOC ≈ (3.55 - 3.49) / 0.1 = 0.6 V per SOC unit
- Mid SOC: dOCV/dSOC ≈ (3.71 - 3.62) / 0.25 = 0.36 V per SOC unit
- High SOC: dOCV/dSOC ≈ (4.19 - 4.07) / 0.1 = 1.2 V per SOC unit

**This is why:**
- Kalman filter corrections are larger in steep regions (high sensitivity)
- Corrections are smaller in flat regions (low sensitivity)

---

## Practical Implications

### 1. **Accuracy Varies with SOC**

**Best accuracy**: High and low SOC regions (steep slopes)
- Voltage measurement errors translate to smaller SOC errors
- Good for battery management systems (BMS)

**Worst accuracy**: Mid SOC region (flat slope)
- Voltage measurement errors translate to larger SOC errors
- This is where current integration (Coulomb counting) helps most

**Solution**: Combine both methods (like Kalman filter does!)

### 2. **Temperature Effects**

**Critical point**: The SOC-OCV relationship **changes with temperature**.

**Why?**
- Electrochemical reactions are temperature-dependent
- Ion mobility changes with temperature
- At different temperatures, same SOC → different OCV

**Implication:**
- Must account for temperature in the lookup table
- Or use temperature-compensated measurements

**Example from BatterySOCEstimationData.m:**
```matlab
% OCV depends on both SOC and Temperature
V0_mat = [3.49, 3.5, 3.51; ...]  % Different columns for different temperatures
```

### 3. **Hysteresis Effects**

**Important phenomenon**: The SOC-OCV curve can be different for charging vs. discharging.

**Why?**
- During charging, ions move in one direction
- During discharging, ions move in opposite direction
- The battery "remembers" which direction it was going

**Example:**
- Charging to 50% → OCV ≈ 3.70 V
- Discharging to 50% → OCV ≈ 3.68 V
- **Difference**: ~0.02 V

**Implication:**
- Must account for charge/discharge history
- Some advanced BMS track both charge and discharge curves

### 4. **Aging and Degradation**

**Over time**: The SOC-OCV relationship changes.

**Why?**
- Battery capacity decreases (aging)
- Internal resistance increases
- Electrode materials degrade

**Implication:**
- Lookup tables may need periodic updates
- Or use adaptive algorithms that learn the relationship

---

## Challenges and Considerations

### 1. **Voltage Drop Under Load**

**The Problem:**
- When current flows, voltage drops due to internal resistance
- `V_terminal = OCV - I × R`
- Terminal voltage ≠ OCV

**The Solution:**
- Must account for current in measurement model
- Wait for battery to rest before measuring OCV
- Or compensate for voltage drop (as we do in Kalman filter)

**In our code:**
```matlab
V_pred = OCV_pred - I_cell(k) * R_ohm;  % Account for voltage drop
```

### 2. **OCV vs. Terminal Voltage**

**Important distinction:**
- **OCV**: Voltage with no current (resting state)
- **Terminal Voltage**: Voltage during operation (with current)

**For SOC estimation:**
- We measure terminal voltage during operation
- We must convert to OCV to use the SOC-OCV relationship
- This requires knowing the current and resistance

### 3. **Non-Linearity**

**Challenge**: The relationship is non-linear.

**Implication:**
- Simple linear interpolation may introduce errors
- Need good lookup table with sufficient resolution
- Or use non-linear function approximation

**In our code:**
```matlab
OCVf = @(soc) interp1(SOC_vec, OCV_vec, soc, 'linear', 'extrap');
% Linear interpolation between lookup table points
```

### 4. **Lookup Table Resolution**

**Trade-off:**
- **High resolution** (many points): More accurate but more memory
- **Low resolution** (few points): Less accurate but simpler

**Our lookup table:**
```matlab
SOC_vec = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];  % 7 points
```

**Is this enough?**
- For this example: Yes, linear interpolation between points works well
- For production: Might want more points in flat regions

---

## Summary: Why SOC-OCV Relationship is Critical

### The Big Picture

1. **SOC cannot be directly measured** → We need an indirect method
2. **OCV can be measured** → But it's related to SOC, not equal to it
3. **The relationship provides the bridge** → From measurable (voltage) to unmeasurable (SOC)

### In Kalman Filter Context

**The SOC-OCV relationship enables:**

1. **Measurement Model**:
   - "If SOC is X, what voltage should we see?"
   - Compare prediction with measurement
   - Use difference to correct SOC estimate

2. **Drift Correction**:
   - Voltage provides periodic "ground truth" checks
   - Prevents accumulation of current measurement errors

3. **Initialization**:
   - Start estimation with voltage-based initial SOC
   - Better than guessing or assuming fixed value

### Key Takeaways

✅ **SOC-OCV relationship is fundamental** to voltage-based SOC estimation

✅ **Non-linear relationship** with three distinct regions (steep-flat-steep)

✅ **Slope matters**: Steep regions = better estimation accuracy

✅ **Must account for**: Temperature, current flow, aging, hysteresis

✅ **Kalman filter uses it** to correct predictions and prevent drift

✅ **Combined with current integration** (Coulomb counting), provides robust SOC estimation

---

**The relationship between SOC and OCV is the cornerstone of modern battery state estimation. Without understanding this relationship, accurate SOC estimation would be impossible!**

---

*End of Documentation*


